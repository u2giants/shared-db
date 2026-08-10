#!/usr/bin/env python3
"""Post-batch APPLICATION verification for the nine-batch production promotion.

WHY THIS EXISTS (issue #711, owner ruling D7)
---------------------------------------------
`docs/production-promotion-app-tolerance-contract.md` §7 is a MANUAL checklist:
a human with logins to three applications and SSH to the PopCRM worker host,
run nine times, once after every batch. §8/D7 asked who that person is. Nobody
was ever named, and the checks were never run after batch B1 -- which is
already applied to production.

The owner ruled that an AI agent performs these checks. That ruling is worth
nothing unless the check is a RUNNABLE ARTIFACT. "An agent clicks around three
apps" is not a check, it is a hope. This module is the artifact: it asks the
production catalog, for each of the three exposed applications, whether the
objects that application actually reads are still present, still shaped the way
the application expects, and still readable by the role the application
connects as.


HOW THIS DIFFERS FROM `production_catalog_verification.py`
----------------------------------------------------------
They are complementary and neither replaces the other.

  * `production_catalog_verification.py` derives its target list FROM THE
    MIGRATION FILES that were just applied. It answers "did this batch leave
    behind what its own SQL said it would?"
  * THIS module derives its target list FROM THE APPLICATIONS. It answers the
    different and more important question: "is PopPIM / PopDAM / PopCRM still
    able to read what it needs?" A batch can leave behind everything its own SQL
    promised and still break an application through a dropped grant, a revoked
    EXECUTE, a rebuilt view that lost a column, or a schema that stopped being
    exposed through PostgREST.

A migration-derived check is blind to collateral damage by construction: an
object an application depends on and no migration in the batch mentions is not
in its target list at all. That blind spot is precisely where a promotion
breaks an app.


WHERE THE MANIFEST CAME FROM -- verified vs inferred, stated plainly
---------------------------------------------------------------------
`APP_MANIFEST` below was derived on 2026-08-10 from FRESH shallow clones of
`origin/main` of `u2giants/poppim-web`, `u2giants/popdam3` and
`u2giants/popcrm-web` -- not from the stale local checkouts on this machine,
which the contract §2.3 explicitly warns produced four confidently wrong answers
last time. Every relation and routine in the manifest was read out of a real
`.rpc("...")`, `.schema("...").from("...")` or realtime-subscription call site.

Three honest caveats, because a manifest that overstates its own provenance is
worse than a short one:

  1. **PRIVILEGES ARE INFERRED, NOT OBSERVED.** The manifest records the
     privilege each call site MUST have for the code path to work (a `.select()`
     needs SELECT, an `.insert()` needs INSERT). It is not a copy of production's
     current grant matrix. That is the point -- if it were copied from
     production it could never detect a lost grant.
  2. **ROLE ATTRIBUTION IS INFERRED.** Browser sessions reach PostgREST as
     `authenticated`; the PopCRM systemd workers and the PopDAM bridge/windows
     agents use the service-role key. Which specific call site runs under which
     role is inferred from the file it lives in (`workers/`, `apps/worker/`,
     `apps/bridge-agent/` = service_role; `src/` = authenticated).
  3. **TWO CONTRACT CLAIMS DID NOT REPRODUCE** against today's `origin/main`
     and are recorded in `MANIFEST_DRIFT` rather than silently dropped. See that
     constant.


THE FAIL RULE -- absence of evidence is NEVER a pass
-----------------------------------------------------
This repo has been burned repeatedly by guards that reported success because
they found nothing to check. Every one of the following is a HARD FAIL and exits
non-zero:

  * a required relation whose `to_regclass` is NULL, or whose `relkind` is not
    what the application expects (a view where the app reads a table is a
    different failure, but it is still a failure worth a human's attention);
  * a required routine with zero overloads in `pg_proc`;
  * a required privilege that is not held by the role the application connects
    as -- and "held" means an explicit boolean TRUE, never "not false";
  * a required column missing from a relation the application filters on;
  * a schema the application addresses through PostgREST that is absent from
    `pgrst.db_schemas`;
  * the batch identifier resolving to a state §6 of the contract says must
    NEVER be rested on;
  * the query not running at all, returning no rows, or returning an
    unparseable shape -- while there WAS something to verify;
  * the manifest for an application being empty.

There is no "record only" mode and no warning tier. §7 of the contract is the
entire safety net; a safety net with a soft setting is a decoration.


THE FOUR TRAPS THIS FILE IS WRITTEN AGAINST
--------------------------------------------
Each has already fired in this repository at least once.

  1. **"It applied successfully" proves nothing.** Nothing here reads
     `supabase_migrations.schema_migrations`. Every assertion is a catalog fact:
     `to_regclass`, `pg_proc`, `pg_get_viewdef`, `has_table_privilege`,
     `information_schema.columns`, `pg_constraint`.
  2. **The null-permissive guard.** A check shaped `if not (x or role = 'y')`
     never fires when `role` is NULL. Every verdict in this file goes through
     `is_explicit_true()`, which requires a non-null value AND a positive match.
     `None` is a FAILURE, not a pass. `NullPermissiveTests` proves it.
  3. **`America/New_York`.** This database is not on UTC. A timestamp at
     midnight UTC reads back through `::date` as the previous day. Every date
     this file records is pinned to MIDDAY UTC (`CLOCK_PIN_UTC`) and asserted in
     BOTH zones; if the two disagree the run FAILS rather than quietly recording
     a day that is off by one.
  4. **`plm` is not exposed through PostgREST on production**
     (`pgrst.db_schemas` = public, graphql_public, api, crm, pim, core, app).
     A `plm` object is therefore checked for existence and privilege in the
     CATALOG, and is explicitly NOT expected in `pgrst.db_schemas`. Treating its
     absence there as a break would be a false positive -- it would fail for a
     configuration reason, not because the application is broken. See
     `POSTGREST_UNEXPOSED_SCHEMAS`.


WHAT THIS CANNOT PROVE -- read this before trusting a green run
----------------------------------------------------------------
  * **It does not open the applications.** It proves the database side of the
    contract. It cannot see a React render crash, a white page, a broken build,
    or a wrong-looking picker. §7.1's five-minute smoke test is not obsolete.
  * **It cannot see PopDAM's silent fallbacks.** `StylesPage.tsx` returns a
    hardcoded size list on ANY error. This module checks that `core.product_size`
    exists, is readable, carries `status`, and holds rows -- which removes the
    most likely cause -- but a plausible-looking picker is still only provable by
    looking at it.
  * **It does not read the PopCRM worker journal.** A worker break appears only
    in systemd; the worker's own `/health` is a hardcoded `{ok:true}`.
  * **It does not check row-level security semantics.** It reads catalog grants,
    not what a specific end user can actually see through a policy.
  * **It does not check function BODIES, argument defaults, or return shapes.**
    A function replaced with a same-named, same-arity, wrong-behaviour body
    passes.
  * **The manifest is a snapshot.** A deploy of any of the three applications
    invalidates it. Re-derive it from fresh `origin/main` clones, per §9.5 of the
    contract.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

MANAGEMENT_API = "https://api.supabase.com"

# Cloudflare in front of the Management API answers HTTP 403 "error 1010" to the
# default `Python-urllib/3.x` User-Agent. This is load-bearing, not cosmetic --
# the same trap cost issue #709 a whole debugging session. Do not remove it.
USER_AGENT = "shared-db-post-batch-app-verification/1.0"

# The shared production project. Recorded so a wrong `--project-ref` is visible
# in the artifact, never to be used as a default: the ref is always passed
# explicitly so nothing here can point itself at production by accident.
PRODUCTION_PROJECT_REF = "qsllyeztdwjgirsysgai"

# Trap 3. Midday UTC is 08:00 America/New_York in either DST state, so the date
# is the same in both zones -- which is exactly what a midnight-UTC timestamp
# fails to be. Every date this module records is pinned here.
CLOCK_PIN_UTC = "12:00:00"

# Trap 4. `plm` carries confidential licensor data and is deliberately NOT in
# `pgrst.db_schemas` on production. Absence from the PostgREST list is the
# CORRECT state for these; asserting otherwise manufactures a false failure.
POSTGREST_UNEXPOSED_SCHEMAS = frozenset({"plm"})

# The schemas the three applications actually address through PostgREST. Read
# from production's `pgrst.db_schemas` and compared against this set.
REQUIRED_POSTGREST_SCHEMAS = ("api", "app", "core", "crm", "pim", "public")

IDENTIFIER = re.compile(r"^[a-z_][a-z0-9_]*$")


class VerificationError(Exception):
    """Raised for anything that makes the verification itself untrustworthy."""


# ---------------------------------------------------------------------------
# The batch map -- contract §5 and §6
# ---------------------------------------------------------------------------

# Contract §6: the ten legal resting points and NOTHING else. The value is the
# migration version the batch ends on. A run whose last-applied version is not
# one of these is sitting in an EXPOSED state, and this module says so.
BATCH_RESTING_POINTS = {
    "B0": "20260810140000",
    "B1": "20260728134500",
    "B2": "20260728181500",
    "B3": "20260731200000",
    "B4": "20260731220000",
    "B5": "20260802160000",
    "B6": "20260804120100",
    "B7": "20260807200000",
    "B8": "20260809170500",
    "B9": "20260810170000",
}

# Contract §6, first block: versions that must NEVER be the last one applied.
# Resting here is not "paused", it is exposed -- three of these states leave
# confidential licensor data readable or rewritable (§6, ranked list).
NEVER_REST_VERSIONS = frozenset(
    """
20260724060000 20260724061000 20260726030000 20260726031000 20260726032000
20260726180000 20260727221500 20260727223000 20260727224500 20260727230000
20260728171500 20260728174500
20260729230000 20260729234500 20260729235500 20260730000500 20260731150000
20260731153000 20260731163000 20260731180000 20260731190000
20260731210000
20260802140000 20260802141000 20260802150000
20260803150000 20260803200000 20260803201000 20260804120000
20260807030000 20260807170000 20260807170100 20260807180000 20260807190000
20260809170000 20260809170100 20260809170200 20260809170300 20260809170400
20260810010000 20260810020000 20260810030000 20260810050000 20260810060000
20260810070000 20260810080000 20260810090000 20260810100000 20260810110000
20260810120000 20260810130000 20260810160000
""".split()
)

# Contract §5: never applied at all, at any time, in any batch. Applying it
# REGRESSES a live security control and sorts below the migration that would
# repair it, so the damage is permanent.
RETIRED_VERSIONS = frozenset({"20260729120000"})

# Contract §6.5: held pending the FRIENDS TV removal work.
HELD_VERSIONS = frozenset({"20260802170000", "20260802171000"})


# ---------------------------------------------------------------------------
# The application manifest
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Relation:
    """One table or view an application reads or writes, and how."""

    schema: str
    name: str
    kind: str  # "table" | "view" -- what the application's code assumes
    roles: tuple[str, ...]
    privileges: tuple[str, ...]
    columns: tuple[str, ...] = ()  # columns the app FILTERS or GROUPS on
    why: str = ""

    # The batch that CREATES this object. Before that batch it is legitimately
    # absent, and failing on it would make this guard permanently red for a
    # state the promotion plan itself intends. From that batch onwards its
    # absence is fatal. `None` means "already on production, always required".
    arrives_in: str | None = None

    # Privileges the application's code needs that production DID NOT GRANT as
    # of the 2026-08-10 baseline read. Recorded, never deleted, and reported in
    # its own section of every run -- see `BASELINE_GAP_POLICY`.
    baseline_missing: tuple[str, ...] = ()

    @property
    def qualified(self) -> str:
        return f"{self.schema}.{self.name}"


@dataclass(frozen=True)
class Routine:
    """One function an application calls, and the role it calls it as."""

    schema: str
    name: str
    roles: tuple[str, ...]
    why: str = ""
    arrives_in: str | None = None

    @property
    def qualified(self) -> str:
        return f"{self.schema}.{self.name}"


@dataclass(frozen=True)
class ForeignKey:
    """A FK PostgREST resolves an embedded select through.

    Contract §3.1: `poppim-web/src/features/board/collab.ts` does
    `.select('contact:contact_id(id,full_name,email)')` against
    `core.contact_company`. PostgREST resolves that embed THROUGH THE FOREIGN
    KEY. Drop or rename the FK and the request 400s even though every table
    involved still exists -- which no relation-existence check would catch.
    """

    schema: str
    table: str
    column: str
    why: str = ""


@dataclass(frozen=True)
class AppSpec:
    relations: tuple[Relation, ...]
    routines: tuple[Routine, ...]
    foreign_keys: tuple[ForeignKey, ...] = ()
    notes: str = ""


WEB = ("authenticated",)
WORKER = ("service_role",)
READ = ("SELECT",)
RW = ("SELECT", "INSERT", "UPDATE")
RWD = ("SELECT", "INSERT", "UPDATE", "DELETE")

# WHY THERE IS A BASELINE-GAP CONCEPT AT ALL, AND WHY IT IS NOT A SOFT TIER
# -------------------------------------------------------------------------
# A first live run of this module against production on 2026-08-10 (batch B1
# applied, nothing since) found that PopPIM's code INSERTs, UPDATEs and DELETEs
# against five `pim` tables on which `authenticated` holds SELECT AND NOTHING
# ELSE. Those writes 403 today. That is a REAL, PRE-EXISTING defect and it is
# recorded here rather than quietly dropped from the manifest.
#
# It is not counted as a post-batch failure, for one reason only: this module's
# job is to detect what a BATCH CHANGED, and a condition that predates every
# batch cannot have been caused by one. A guard that is red on day one for a
# pre-existing reason is a guard people learn to click through, and then it
# catches nothing on the day it matters.
#
# The concession is narrow and it does not erode:
#   * every gap is listed, by object and privilege, in EVERY run's report;
#   * a privilege failure that is NOT on this recorded list is a HARD FAILURE;
#   * a gap that has CLOSED is reported too, as a manifest-drift item, so the
#     list cannot silently outlive the problem;
#   * nothing else in this module has a warning tier. Objects, kinds, columns,
#     foreign keys, batch extras and evidence are all pass/fail.
BASELINE_GAP_POLICY = (
    "Recorded 2026-08-10 from a live read of production, with batch B1 applied "
    "and nothing after it. These are privileges the application's own code "
    "needs and production does not grant -- pre-existing defects, not batch "
    "damage. They are reported in every run and never suppressed. Any privilege "
    "failure NOT on this list is a hard failure."
)


def _api_routines(names, roles=WEB, why=""):
    return tuple(Routine("api", n, roles, why) for n in names)


# --- PopPIM -----------------------------------------------------------------
# VERIFIED 2026-08-10 against a fresh `origin/main` clone of u2giants/poppim-web.
# The 19 `api.pm_*` RPCs plus `api.current_user_profile` reproduce the contract
# §3.1 list exactly. Schema attribution for every `.from()` comes from the four
# helpers in `src/lib/supabaseQuery.ts` (`api()`, `pim()`, `core()`,
# `appSchema()` behind `dynamicApp()` / `dynamicCore()` / `dynamicPim()`), so no
# table below is schema-guessed.

POPPIM = AppSpec(
    routines=_api_routines(
        [
            "current_user_profile",
            "pm_account_page",
            "pm_department_handoffs",
            "pm_department_report",
            "pm_design_collection_page",
            "pm_design_page",
            "pm_my_reminder_page",
            "pm_my_revision_page",
            "pm_my_work_page",
            "pm_notes_page",
            "pm_order_page",
            "pm_patch_product_metadata",
            "pm_people_workload_page",
            "pm_pipeline_count",
            "pm_pipeline_list_facets",
            "pm_pipeline_page",
            "pm_project_page",
            "pm_schedule_page",
            "pm_set_product_stage",
            "pm_upsert_view_pref",
        ],
        why="src/**: supabase.schema('api').rpc(...). PostgREST resolves these "
        "by ARGUMENT NAME, so a renamed argument makes the function unfindable "
        "and PopPIM white-screens (contract §3.1).",
    ),
    relations=(
        Relation(
            "api",
            "pm_customer_list",
            "view",
            WEB,
            READ,
            why="src/features/board/collab.ts -- api().from('pm_customer_list')",
        ),
        Relation(
            "api",
            "pm_product_board",
            "view",
            WEB,
            READ,
            why="src/domain/products/enrich.ts:15 -- asDynamic(api()).from(...)",
        ),
        # app schema: the string-triple activity/notification/comment rows.
        # Contract §3.1 calls this out as the unenforced cross-schema reference:
        # the three filter columns are as contractual as the tables themselves,
        # which is why they are named here.
        Relation(
            "app",
            "activity",
            "table",
            WEB,
            RW,
            ("target_schema", "target_table", "target_id", "action", "payload"),
            why="src/features/operating/api.ts -- dependencies and decisions panes",
        ),
        Relation(
            "app",
            "notification",
            "table",
            WEB,
            RW,
            ("target_schema", "target_table", "target_id", "profile_id", "payload"),
            why="src/features/operating/api.ts -- reminders pane",
        ),
        Relation(
            "app",
            "comment",
            "table",
            WEB,
            ("SELECT", "INSERT"),
            ("target_schema", "target_table", "target_id", "body"),
            why="src/features/board/collab.ts:164,180; src/domain/products/rollups.ts:105 "
            "-- select and insert only; PopPIM never edits a comment",
        ),
        Relation("app", "profile", "table", WEB, READ, why="dynamicApp().from('profile')"),
        Relation("core", "licensor", "table", WEB, READ, why="dynamicCore().from('licensor')"),
        Relation(
            "core", "product_type", "table", WEB, READ, why="dynamicCore().from('product_type')"
        ),
        Relation(
            "core",
            "contact_company",
            "table",
            WEB,
            READ,
            ("company_id", "contact_id"),
            why="src/features/board/collab.ts:358 -- the PostgREST embed",
        ),
        # pim schema. `pim.product` is the highest-value object PopPIM has: the
        # activity/notification/comment rows address it by the STRING 'pim' /
        # 'product' with no foreign key, so a rename passes every constraint and
        # silently empties three panes (contract §3.1).
        # Privileges below are the verbs the code ACTUALLY uses, derived by
        # scanning each `.from('x')` call site for the `.select|.insert|.update|
        # .upsert|.delete` that follows it -- not by assuming "a table an app
        # touches is a table an app writes". The first draft of this manifest
        # assumed the latter and produced eighteen false failures on the first
        # live run.
        Relation(
            "pim", "product", "table", WEB, ("SELECT", "UPDATE"), why="pim().from('product')"
        ),
        Relation(
            "pim",
            "checklist_item",
            "table",
            WEB,
            RWD,
            why="pim().from('checklist_item') -- select, insert, update, delete",
            baseline_missing=("INSERT", "UPDATE", "DELETE"),
        ),
        Relation(
            "pim",
            "product_assignee",
            "table",
            WEB,
            ("SELECT", "INSERT", "DELETE"),
            why="pim().from('product_assignee') -- select, insert, delete",
            baseline_missing=("INSERT", "DELETE"),
        ),
        Relation("pim", "product_field", "table", WEB, READ, why="pim().from(...) -- select only"),
        Relation("pim", "product_file", "table", WEB, READ, why="pim().from(...) -- select only"),
        Relation("pim", "product_link", "table", WEB, READ, why="collab.ts:253 -- select only"),
        Relation(
            "pim",
            "product_sample",
            "table",
            WEB,
            RW,
            why="pim().from('product_sample') -- select, insert, update",
            baseline_missing=("INSERT", "UPDATE"),
        ),
        Relation(
            "pim",
            "product_submission",
            "table",
            WEB,
            RW,
            why="pim().from('product_submission') -- select, insert, update",
            baseline_missing=("INSERT", "UPDATE"),
        ),
        Relation("pim", "product_tag", "table", WEB, READ, why="pim().from(...) -- select only"),
        Relation(
            "pim", "product_time_entry", "table", WEB, READ, why="pim().from(...) -- select only"
        ),
        Relation("pim", "product_update", "table", WEB, READ, why="pim().from(...) -- select only"),
        Relation(
            "pim",
            "revision_request",
            "table",
            WEB,
            RW,
            why="pim().from('revision_request') -- select, insert, update",
            baseline_missing=("INSERT", "UPDATE"),
        ),
        Relation("pim", "saved_view", "table", WEB, RWD, ("scope",), why="pim().from(...)"),
        Relation("pim", "stage", "table", WEB, READ, why="pim().from('stage')"),
        Relation("pim", "view_pref", "table", WEB, READ, why="pim().from('view_pref') -- select"),
    ),
    foreign_keys=(
        ForeignKey(
            "core",
            "contact_company",
            "contact_id",
            "PostgREST resolves collab.ts:358's `contact:contact_id(...)` embed "
            "through this FK. Without it the request 400s (contract §3.1).",
        ),
    ),
    notes="Fails MOST QUIETLY of the three: `unwrap()` casts null data to T with "
    "no guard and there is no ErrorBoundary, so a break renders as a white page.",
)

# --- PopDAM -----------------------------------------------------------------
# VERIFIED 2026-08-10 against a fresh `origin/main` clone of u2giants/popdam3.
# 23 unqualified (i.e. `public`) RPCs; `core` reached via `.schema("core")`;
# `api` via `.schema("api")`. The realtime relations are listed because a
# `postgres_changes` subscription binds to a table name as a STRING -- rename or
# drop it and the subscription simply never fires, so the grid stops updating
# and LOOKS IDLE rather than broken (contract §3.2).

POPDAM = AppSpec(
    # ROLE ATTRIBUTION IS BY CALL SITE, NOT BY GUESS. The first draft gave every
    # RPC both roles and the first live run immediately failed on three
    # worker-only functions that `authenticated` correctly cannot execute --
    # get_ai_tag_candidates, get_pdf_rich_extraction_hashes and
    # upsert_pdf_rich_extraction. Those are not breaks, they are the grant
    # working as intended, and asserting otherwise would have trained the
    # operator to ignore a red run.
    routines=tuple(
        Routine("public", n, WEB, "popdam3 src/ only -- browser session, authenticated")
        for n in [
            "add_style_tracker_rows",
            "get_filter_counts",
            "get_sg_preview_stats",
            "get_sg_render_queue_stats",
            "get_style_guide_tagging_stats",
            "refresh_style_tracker_item_bridge",
            "requeue_all_failed_sg_jobs",
            "retry_sg_render_errors",
            "search_style_tracker_link_candidates",
            "set_style_group_cover",
            "upsert_style_tracker_value_resolution",
        ]
    )
    + tuple(
        Routine("public", n, WORKER, "popdam3 apps/worker only -- service-role background agent")
        for n in [
            "cleanup_mega_group_tags_batch",
            "clear_style_group_batch",
            "get_ai_tag_candidates",
            "get_pdf_rich_extraction_hashes",
            "get_style_guide_deterministic_tag_batch_v2",
            "propagate_group_tags_batch",
            "rebuild_style_groups_batch",
            "reconcile_style_group_stats_batch",
            "refresh_dam_search_style_group_document",
            "refresh_style_group_rich_metadata",
            "refresh_style_guide_folder_consensus_batch",
            "upsert_pdf_rich_extraction",
        ]
    )
    + (
        Routine(
            "public",
            "update_bulk_operation",
            WEB + WORKER,
            "popdam3 src/ AND apps/worker -- the only RPC both reach",
        ),
    ),
    relations=(
        Relation(
            "api",
            "dam_customer_list",
            "view",
            WEB,
            READ,
            why="src/hooks/useDamCustomers.ts:28; src/pages/StylesPage.tsx:611",
        ),
        Relation(
            "api",
            "dam_factory_list",
            "view",
            WEB,
            READ,
            why="src/pages/StylesPage.tsx:655",
        ),
        # core lookups. `status` is CONTRACTUAL, not incidental: StylesPage
        # filters `.eq("status","active")`, so losing the column or flipping
        # every row inactive empties a picker with NO error (contract §3.2).
        Relation(
            "core",
            "licensor",
            "table",
            WEB + WORKER,
            READ,
            ("name", "code"),
            why="StylesPage.tsx:624; AssetDetailPanel.tsx:234,270; worker popsg-tags.ts:505",
        ),
        Relation(
            "core",
            "property",
            "table",
            WEB + WORKER,
            READ,
            ("name", "licensor_id"),
            why="StylesPage.tsx:742; AssetDetailPanel.tsx:244,280; worker ai-tagging-shared.ts",
        ),
        Relation(
            "core",
            "creative_designer",
            "table",
            WEB,
            READ,
            ("name",),
            why="StylesPage.tsx:634 and the manual-link candidate picker",
        ),
        Relation(
            "core",
            "packaging_type",
            "table",
            WEB,
            RW,
            why="StylesPage.tsx:672; components/settings/PackagingTypesTab.tsx:60",
        ),
        Relation(
            "core",
            "customer",
            "table",
            WEB,
            READ,
            ("name",),
            why="StylesPage.tsx:587 -- .schema('core').from(table) where table='customer'",
        ),
        Relation(
            "core",
            "factory",
            "table",
            WEB,
            READ,
            ("name",),
            why="StylesPage.tsx:587 -- .schema('core').from(table) where table='factory'",
        ),
        Relation(
            "core",
            "product_size",
            "table",
            WEB,
            READ,
            ("name", "status"),
            why="StylesPage.tsx:760 fetchSizeOptions. THE B8 OBJECT. On ANY error "
            "this call falls through to a hardcoded list and reports nothing "
            "(contract §3.2, §7.2 B8). CONFIRMED ABSENT on production 2026-08-10, "
            "which means PopDAM's size picker is running on COMMON_SIZE_OPTIONS "
            "right now and has never said so.",
            arrives_in="B8",
        ),
        Relation(
            "dam",
            "sku_human_description",
            "table",
            WORKER,
            READ,
            why="apps/worker/src/handlers/ai-tagging-shared.ts:270",
        ),
        Relation(
            "public",
            "dam_character_catalog",
            "view",
            WEB + WORKER,
            READ,
            ("id", "name"),
            why="apps/worker ai-tagging-shared.ts, ai-tag-bakeoff.ts; settings/ApisTab.tsx:283",
        ),
        Relation(
            "public",
            "characters",
            "table",
            WORKER,
            READ,
            why="apps/worker/src/handlers/popsg-tags.ts:507",
        ),
        # The realtime-bound relations. A rename here is SILENT.
        Relation(
            "public",
            "style_groups",
            "table",
            WEB + WORKER,
            RW,
            ("size_name",),
            why="realtime postgres_changes + fetchSizeOptions fallback source",
        ),
        Relation(
            "public",
            "admin_config",
            "table",
            WEB,
            READ,
            ("key",),
            why="realtime: SystemStatePanel, DirectoryBrowserTab, useCrawlProgress, useScanProgress",
        ),
        Relation(
            "public",
            "render_queue",
            "table",
            WEB + WORKER,
            READ,
            why="realtime: components/settings/diagnostics/OverviewCards.tsx:282",
        ),
        Relation(
            "public",
            "agent_registrations",
            "table",
            WEB + WORKER,
            READ,
            why="realtime: src/hooks/useAgentStatus.ts:174",
        ),
    ),
    notes="Largest surface, and the two INVISIBLE paths live here: "
    "StylesPage.tsx swallows a core.product_size error into a hardcoded list, "
    "and a renamed realtime table makes the grid look idle rather than broken.",
)

# --- PopCRM -----------------------------------------------------------------
# VERIFIED 2026-08-10 against a fresh `origin/main` clone of u2giants/popcrm-web.
# The `api.crm_*` views are the ones actually reached through the three generic
# `.from(view)` helpers in src/features/crm/api.ts, where `view` is an untyped
# string on an `anyDb` cast -- TypeScript cannot see a wrong name, so a rename
# has ZERO compile-time signal (contract §3.3).
#
# NOTE: `crm_segment` appears in the source as a string but is a COLUMN on
# api.crm_contact_segment_list, not an object. It is recorded as a column below,
# not as a relation. A naive grep would have added it as a nineteenth view and
# this check would then fail forever on an object that does not exist.

POPCRM = AppSpec(
    routines=_api_routines(
        [
            "current_user_profile",
            "crm_admin_user_list",
            "crm_customer_segment_counts",
            "crm_customer_segment_list",
            "crm_email_routing_recent",
            "crm_email_routing_segment_counts",
            "crm_set_customer_logo",
            "crm_set_opportunity_stage",
            "crm_update_contact",
            "crm_update_customer",
        ],
        why="src/features/crm/api.ts and src/auth/auth.tsx:106",
    )
    + (
        Routine(
            "crm",
            "record_ingested_domain",
            WORKER,
            "workers/crm-worker-supabase.mjs:618 -- service-role, systemd only",
        ),
    ),
    relations=tuple(
        Relation("api", n, "view", WEB, READ, cols, why="src/features/crm/api.ts .from(view)")
        for n, cols in [
            ("crm_account_list", ()),
            ("crm_account_overview", ()),
            ("crm_ai_model_config_list", ("name",)),
            ("crm_approval_queue", ("stage", "submitted_date")),
            ("crm_contact_list", ()),
            ("crm_contact_segment_list", ("crm_segment",)),
            ("crm_customer_list", ()),
            ("crm_customer_overview", ()),
            ("crm_customer_picker_list", ()),
            ("crm_department_list", ()),
            ("crm_email_routing_queue", ("received_at",)),
            ("crm_ignore_rule_list", ()),
            ("crm_ingested_domain_list", ()),
            ("crm_meeting_list", ()),
            ("crm_note_list", ()),
            ("crm_opportunity_list", ()),
            ("crm_task_list", ()),
        ]
    )
    + (
        # The web app deletes departments through the crm schema directly.
        Relation(
            "crm", "department", "table", WEB, ("SELECT", "DELETE"), why="api.ts:701"
        ),
        # The five systemd workers. Contract §3.3: they write `crm.*` and
        # `core.*` DIRECTLY and never touch `api`, so a migration that carefully
        # preserves the api facade can still break them -- and their failures
        # are invisible, because the only health endpoint returns a hardcoded
        # {ok:true} that would stay green through a total schema break.
        Relation("crm", "ai_model_config", "table", WORKER, RW, why="crm-worker-supabase.mjs"),
        Relation("crm", "email_message", "table", WORKER, RW, why="crm-worker-supabase.mjs"),
        Relation("crm", "ignore_rule", "table", WORKER, RW, why="crm-worker-supabase.mjs"),
        Relation("crm", "meeting_note", "table", WORKER, RW, why="crm-worker-supabase.mjs"),
        Relation("crm", "note", "table", WORKER, RW, why="crm-worker-supabase.mjs"),
        Relation("crm", "opportunity", "table", WORKER, RW, why="crm-worker-supabase.mjs"),
        Relation("crm", "task", "table", WORKER, RW, why="crm-worker-supabase.mjs"),
        Relation("core", "contact", "table", WORKER, RW, why="crm-worker-supabase.mjs"),
        Relation("core", "contact_company", "table", WORKER, RW, why="crm-worker-supabase.mjs"),
        Relation("core", "customer", "table", WORKER, RW, why="crm-worker-supabase.mjs"),
    ),
    notes="Best behaved in the UI, but the systemd workers bypass the api facade "
    "entirely and their /health is a constant. Do not read it as evidence.",
)

APP_MANIFEST: dict[str, AppSpec] = {
    "PopPIM": POPPIM,
    "PopDAM": POPDAM,
    "PopCRM": POPCRM,
}

# Contract §2.1: DesignFlow PLM production runs on Cloud SQL and CANNOT connect
# to Supabase -- the provider, port, SSL setting, network path and username
# shape are all forced, and the Supabase pooler username form is rejected
# outright. It is therefore OUT OF SCOPE for a post-batch check of the shared
# production project, and this module does not check it.
#
# Its NON-production environments (develop, staging, sandbox) are contractually
# bound to the shared Supabase pooler and receive every batch instantly with no
# redeploy. That is contract §7.0's free rehearsal -- and it is a HUMAN action
# (exercise DesignFlow sandbox), not something this module can perform.
OUT_OF_SCOPE = {
    "DesignFlow PLM": "Production is Cloud SQL, not Supabase (contract §2.1). "
    "Non-production runs on the shared pooler and should be exercised by hand "
    "per §7.0; this module cannot do that.",
    "monitor": "No such repository exists under u2giants (contract §2.2). Its "
    "presence on the #612 list is a documentation artifact.",
}

# Claims in the contract that did NOT reproduce against today's `origin/main`.
# Recorded rather than dropped, because a silent divergence between the contract
# and the check is exactly how a check drifts into proving nothing.
MANIFEST_DRIFT = (
    "Contract §3.2 and §7.2/B8 say StylesPage.tsx reads `core.product_material` "
    "and falls back to COMMON_PRODUCT_MATERIAL_OPTIONS. On origin/main as of "
    "2026-08-10 there is NO such read: `product_material` survives only as an "
    "array COLUMN on the assets facet (src/hooks/useAssets.ts:179). "
    "`core.product_material` is therefore NOT in the PopDAM manifest. "
    "`core.product_depth` likewise has no reader. B8 still creates them; they "
    "are simply not yet an application dependency, so their absence would not "
    "break PopDAM today.",
    "Contract §3.2 lists `api.dam_character_catalog`. On origin/main the reads "
    "are UNQUALIFIED (`client.from(\"dam_character_catalog\")`) and ApisTab.tsx:283 "
    "passes the schema explicitly as \"public\". It is recorded as "
    "`public.dam_character_catalog`. If an `api.dam_character_catalog` also "
    "exists it is not the one PopDAM reads.",
    "Contract §3.2 says `api.dam_order_list` has no application reader. That "
    "reproduces: the name appears in popdam3 only inside vendored documentation. "
    "It is checked as a BATCH EXTRA for B9 (security_invoker), not as an app "
    "dependency, because no application depends on it.",
)


# ---------------------------------------------------------------------------
# Per-batch extras -- contract §7.2
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class BatchExtra:
    """One batch-specific assertion, expressed as a boolean SQL expression.

    `expression` MUST evaluate to a boolean and MUST be true when the batch
    landed correctly. NULL is a failure, never a pass (trap 2).
    """

    key: str
    expression: str
    why: str


BATCH_EXTRAS: dict[str, tuple[BatchExtra, ...]] = {
    "B1": (
        BatchExtra(
            "coldlion_sync_is_three_arg",
            "exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace "
            "where n.nspname = 'plm' and p.proname = 'sync_coldlion_licensors_properties' "
            "and p.pronargs = 3)",
            "§5/B1 replaces the 2-arg signature with a 3-arg one. Assert the NEW "
            "signature is present -- the ledger row proves neither.",
        ),
        BatchExtra(
            "coldlion_sync_two_arg_is_gone",
            "not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace "
            "where n.nspname in ('plm','public') and p.proname = 'sync_coldlion_licensors_properties' "
            "and p.pronargs = 2)",
            "§D3.1: the drop is the destructive half. A surviving 2-arg overload "
            "means PostgREST/callers can still resolve the old body.",
        ),
    ),
    "B6": (
        BatchExtra(
            "trip_taxonomy_circuit_breaker_eight_arg_is_gone",
            "not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace "
            "where n.nspname in ('plm','public') and p.proname = 'trip_taxonomy_circuit_breaker' "
            "and p.pronargs = 8)",
            "§D3.2: 20260804120100 drops the 8-argument overload in BOTH schemas.",
        ),
    ),
    "B7": (
        BatchExtra(
            "opa_property_reconciliation_exists",
            "to_regclass('api.opa_property_reconciliation') is not null",
            "§7.2/B7: this batch DROPS and re-creates the view (a genuine "
            "column-set change `create or replace view` cannot do). There is a "
            "window with no view at all -- this is the one place a rebuild "
            "could leave nothing behind.",
        ),
        BatchExtra(
            "opa_property_reconciliation_has_a_definition",
            "coalesce(length(pg_get_viewdef('api.opa_property_reconciliation'::regclass)), 0) > 0",
            "Existence is not enough; a view with no readable definition is a "
            "different kind of broken.",
        ),
    ),
    "B8": (
        BatchExtra(
            "core_product_size_is_seeded",
            "(select count(*) from core.product_size) > 0",
            "§7.2/B8 -- THE MOST IMPORTANT CHECK IN THE CONTRACT. An empty or "
            "half-seeded core.product_size is exactly what PopDAM swallows: "
            "StylesPage falls back to a hardcoded list and reports nothing. A "
            "plausible-looking picker is not evidence of success.",
        ),
        BatchExtra(
            "core_product_size_has_active_rows",
            "(select count(*) from core.product_size where status = 'active') > 0",
            "PopDAM filters .eq('status','active'). Rows that all landed "
            "inactive are indistinguishable from no rows at all, in the UI.",
        ),
        BatchExtra(
            "core_product_depth_exists",
            "to_regclass('core.product_depth') is not null",
            "§5/B8 creates it alongside product_size. No reader today "
            "(MANIFEST_DRIFT), but its absence means the batch did not land.",
        ),
    ),
    "B9": (
        BatchExtra(
            "dam_order_list_is_security_invoker",
            "exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace "
            "where n.nspname = 'api' and c.relname = 'dam_order_list' "
            "and c.reloptions @> array['security_invoker=true'])",
            "§5 'the trap that only this batch plan prevents' (#653): the view "
            "was created WITHOUT security_invoker and ran as its BYPASSRLS owner, "
            "bypassing RLS on core.customer, core.factory and plm.item for every "
            "authenticated reader. 20260810110000 is the fix.",
        ),
        BatchExtra(
            "warner_read_gate_is_not_wide_open",
            "not exists (select 1 from pg_policies where schemaname = 'plm' "
            "and tablename like 'wb\\_%' and cmd = 'SELECT' and qual = 'true')",
            "§5/§6: between 20260810030000 and 20260810110000 the eight Warner "
            "tables carry `for select to authenticated using (true)` -- every "
            "authenticated account in the shared project can read confidential "
            "STARLABS data. A surviving `using (true)` means B9 did not complete.",
        ),
        BatchExtra(
            "paramount_service_role_has_no_truncate",
            "not exists (select 1 from information_schema.role_table_grants "
            "where table_schema = 'plm' and table_name like 'pmt\\_%' "
            "and grantee = 'service_role' and privilege_type = 'TRUNCATE')",
            "§5: TRUNCATE does not fire row-level triggers, so one statement "
            "silently bypasses all five immutability guards. 20260810090000 "
            "closes it.",
        ),
    ),
}


# ---------------------------------------------------------------------------
# The explicit-true rule -- trap 2
# ---------------------------------------------------------------------------


def is_explicit_true(value: object) -> bool:
    """Return True ONLY for an unambiguous, non-null, positive true.

    THIS IS THE WHOLE DEFENCE AGAINST THE NULL-PERMISSIVE BUG. The pattern that
    burned this repo was `if not ( ... or auth.role() = 'service_role' )`, which
    never fires when the role is NULL, because `NULL = 'x'` is NULL and `not
    NULL` is NULL, which is not true, so the guard's body never runs.

    The rule here is the mirror image and is deliberately paranoid: a verdict
    counts as a pass only on a POSITIVE MATCH against a NON-NULL value. `None`,
    `''`, `'null'`, `'unknown'`, a missing key and any unrecognised type are all
    NOT a pass. Never write `if not is_false(...)` anywhere in this file.
    """
    if value is None:
        return False
    if value is True:
        return True
    if value is False:
        return False
    if isinstance(value, str):
        return value.strip().lower() in {"true", "t", "yes", "y", "1"}
    if isinstance(value, int):  # bool is handled above
        return value == 1
    return False


def quote_literal(value: str) -> str:
    """Single-quote a string for SQL. Identifiers are validated, not escaped."""
    return "'" + value.replace("'", "''") + "'"


def check_identifier(value: str, what: str) -> str:
    """Refuse anything that is not a plain lowercase identifier.

    Every identifier in this module comes from the hardcoded manifest above, so
    this can never fire in normal operation. It exists so that a future edit
    that pastes in a name from an untrusted place fails LOUDLY at build time
    rather than producing surprising SQL.
    """
    if not IDENTIFIER.match(value):
        raise VerificationError(f"refusing to build SQL for a non-identifier {what}: {value!r}")
    return value


# ---------------------------------------------------------------------------
# Batch resolution
# ---------------------------------------------------------------------------


@dataclass
class BatchResolution:
    batch: str
    last_version: str
    versions: list[str]
    problems: list[str] = field(default_factory=list)


def resolve_batch(batch: str | None, versions_csv: str | None) -> BatchResolution:
    """Turn `--batch` or `--versions` into a batch id, and refuse exposed states.

    Contract §6 is not advisory. If the last version applied is one of the
    fifty-odd NEVER-REST versions, production is sitting in an exposed state --
    three of which leave confidential licensor data readable or rewritable -- and
    the correct output is a FAILURE telling the operator to finish the batch, not
    a verification report.
    """
    problems: list[str] = []
    versions: list[str] = []

    if batch and versions_csv:
        raise VerificationError("pass --batch OR --versions, not both")
    if not batch and not versions_csv:
        raise VerificationError("one of --batch or --versions is required")

    if versions_csv:
        versions = [v.strip() for v in re.split(r"[,\s]+", versions_csv) if v.strip()]
        if not versions:
            raise VerificationError("--versions parsed to an empty list")
        for v in versions:
            if not re.fullmatch(r"\d{14}", v):
                raise VerificationError(f"not a migration version: {v!r}")
        versions.sort()
        last = versions[-1]
        matched = [b for b, r in BATCH_RESTING_POINTS.items() if r == last]
        resolved = matched[0] if matched else "UNKNOWN"
    else:
        resolved = batch.strip().upper()
        if resolved not in BATCH_RESTING_POINTS:
            raise VerificationError(
                f"unknown batch {resolved!r}. The contract defines exactly "
                f"{sorted(BATCH_RESTING_POINTS)} and no other batch exists."
            )
        last = BATCH_RESTING_POINTS[resolved]
        versions = [last]

    if last in NEVER_REST_VERSIONS:
        problems.append(
            f"EXPOSED STATE: {last} is on the contract §6 never-rest list. "
            "Production is not paused here, it is exposed. The correct next "
            "move is to COMPLETE the batch, not to verify and wait."
        )
    elif resolved == "UNKNOWN":
        problems.append(
            f"UNRECOGNISED RESTING POINT: {last} is neither one of the ten legal "
            f"resting points nor on the §6 never-rest list. This module cannot "
            "tell you which batch you are in, so it cannot run the batch-specific "
            "checks, so it will not report a pass."
        )

    for v in versions:
        if v in RETIRED_VERSIONS:
            problems.append(
                f"RETIRED MIGRATION APPLIED: {v} must NEVER reach production. It "
                "REGRESSES a live security control and sorts below the migration "
                "that would repair it, so the damage is not self-healing."
            )
        if v in HELD_VERSIONS:
            problems.append(
                f"HELD MIGRATION APPLIED: {v} is held under the §6.5 owner ruling "
                "pending the FRIENDS TV removal work."
            )

    return BatchResolution(resolved, last, versions, problems)


# ---------------------------------------------------------------------------
# SQL construction
# ---------------------------------------------------------------------------

_RELKINDS = {
    "table": ("r", "p", "f"),
    "view": ("v", "m"),
}


def build_relation_sql(relations: list[Relation]) -> str:
    """One row per (relation, role): existence, kind, and effective privilege.

    `to_regclass` is used rather than a `pg_class` join because it is the exact
    primitive the repo's own post-incident rule names, and because it returns
    NULL rather than raising for an absent relation -- which lets one query
    report on every target instead of dying on the first miss.
    """
    if not relations:
        raise VerificationError("build_relation_sql called with no relations")
    branches = []
    for rel in relations:
        check_identifier(rel.schema, "schema")
        check_identifier(rel.name, "relation")
        q = quote_literal(rel.qualified)
        expected = _RELKINDS[rel.kind]
        privs = []
        for role in rel.roles:
            check_identifier(role, "role")
            for priv in rel.privileges:
                if not re.fullmatch(r"[A-Z]+", priv):
                    raise VerificationError(f"not a privilege: {priv!r}")
                privs.append(
                    "jsonb_build_object("
                    f"'role', {quote_literal(role)}, "
                    f"'privilege', {quote_literal(priv)}, "
                    "'held', case when to_regclass(%(q)s) is null then null "
                    f"else has_table_privilege({quote_literal(role)}, to_regclass(%(q)s), "
                    f"{quote_literal(priv)}) end)" % {"q": q}
                )
        privs_sql = f"jsonb_build_array({', '.join(privs)})" if privs else "'[]'::jsonb"
        branches.append(
            "select jsonb_build_object("
            f"'relation', {q}, "
            f"'expected_kind', {quote_literal(rel.kind)}, "
            f"'exists', (to_regclass({q}) is not null), "
            "'relkind', (select c.relkind::text from pg_class c "
            f"where c.oid = to_regclass({q})), "
            "'kind_ok', (select c.relkind::text = any(array["
            + ", ".join(quote_literal(k) for k in expected)
            + f"]) from pg_class c where c.oid = to_regclass({q})), "
            f"'privileges', {privs_sql}"
            ") as x"
        )
    return (
        "select jsonb_agg(x order by x->>'relation') as report from ("
        + " union all ".join(branches)
        + ") t"
    )


def build_routine_sql(routines: list[Routine]) -> str:
    """One row per routine: overload count and EXECUTE privilege per role.

    Overloads are COUNTED rather than matched by signature. PostgREST resolves
    an overload by ARGUMENT NAME, and this module deliberately does not claim to
    know each function's argument names -- claiming it would be the kind of
    inference that produces confident wrong answers. Zero overloads is an
    unambiguous failure; the argument-name hazard is called out in the report
    text instead of being faked in SQL.
    """
    if not routines:
        raise VerificationError("build_routine_sql called with no routines")
    branches = []
    for fn in routines:
        check_identifier(fn.schema, "schema")
        check_identifier(fn.name, "routine")
        sel = (
            "from pg_proc p join pg_namespace n on n.oid = p.pronamespace "
            f"where n.nspname = {quote_literal(fn.schema)} and p.proname = {quote_literal(fn.name)}"
        )
        privs = []
        for role in fn.roles:
            check_identifier(role, "role")
            privs.append(
                "jsonb_build_object("
                f"'role', {quote_literal(role)}, "
                "'privilege', 'EXECUTE', "
                "'held', (select bool_and(has_function_privilege("
                f"{quote_literal(role)}, p.oid, 'EXECUTE')) {sel}))"
            )
        privs_sql = f"jsonb_build_array({', '.join(privs)})" if privs else "'[]'::jsonb"
        branches.append(
            "select jsonb_build_object("
            f"'routine', {quote_literal(fn.qualified)}, "
            f"'overloads', (select count(*)::int {sel}), "
            f"'exists', (select count(*) > 0 {sel}), "
            f"'privileges', {privs_sql}"
            ") as x"
        )
    return (
        "select jsonb_agg(x order by x->>'routine') as report from ("
        + " union all ".join(branches)
        + ") t"
    )


def build_column_sql(relations: list[Relation]) -> str:
    """Assert the columns an application FILTERS on still exist.

    Only filter/group columns are listed, never every column. A column an app
    merely displays going missing is a cosmetic bug; a column an app FILTERS on
    going missing is a PostgREST 400 or, worse, a silently empty result -- which
    is the failure the contract calls the dangerous one, because nobody files a
    ticket for a screen that looks fine.
    """
    wanted = [(r, c) for r in relations for c in r.columns]
    if not wanted:
        return ""
    branches = []
    for rel, col in wanted:
        check_identifier(col, "column")
        branches.append(
            "select jsonb_build_object("
            f"'relation', {quote_literal(rel.qualified)}, "
            f"'column', {quote_literal(col)}, "
            "'present', exists (select 1 from information_schema.columns "
            f"where table_schema = {quote_literal(rel.schema)} "
            f"and table_name = {quote_literal(rel.name)} "
            f"and column_name = {quote_literal(col)})"
            ") as x"
        )
    return (
        "select jsonb_agg(x order by x->>'relation', x->>'column') as report from ("
        + " union all ".join(branches)
        + ") t"
    )


def build_foreign_key_sql(fks: list[ForeignKey]) -> str:
    """Assert the FKs PostgREST resolves embedded selects through still exist."""
    if not fks:
        return ""
    branches = []
    for fk in fks:
        check_identifier(fk.schema, "schema")
        check_identifier(fk.table, "table")
        check_identifier(fk.column, "column")
        branches.append(
            "select jsonb_build_object("
            f"'relation', {quote_literal(f'{fk.schema}.{fk.table}')}, "
            f"'column', {quote_literal(fk.column)}, "
            "'present', exists (select 1 from pg_constraint con "
            "join pg_class c on c.oid = con.conrelid "
            "join pg_namespace n on n.oid = c.relnamespace "
            "join pg_attribute a on a.attrelid = c.oid and a.attnum = any(con.conkey) "
            f"where con.contype = 'f' and n.nspname = {quote_literal(fk.schema)} "
            f"and c.relname = {quote_literal(fk.table)} "
            f"and a.attname = {quote_literal(fk.column)})"
            ") as x"
        )
    return (
        "select jsonb_agg(x order by x->>'relation', x->>'column') as report from ("
        + " union all ".join(branches)
        + ") t"
    )


def build_environment_sql() -> str:
    """PostgREST-exposed schemas, and the clock, pinned to midday UTC.

    TRAP 3 IN FULL. `now()` at midnight UTC casts to YESTERDAY through `::date`
    in `America/New_York`, and this database runs `America/New_York`. So the
    date recorded in the artifact is taken from a timestamp pinned to
    `CLOCK_PIN_UTC` (midday), and BOTH the UTC date and the server-local date are
    returned so the caller can assert they agree. If they ever disagree, the
    pinning assumption is wrong and the run FAILS rather than recording a day
    that is off by one.

    `pgrst.db_schemas` is read from `pg_db_role_setting`, NOT from
    `current_setting`. THIS DISTINCTION COST A DEBUGGING PASS AND IS NOT
    COSMETIC: the setting is applied with `alter role authenticator set ...`,
    so it is attached to the `authenticator` role and is NOT in the session GUCs
    of the Management API's own connection. `current_setting('pgrst.db_schemas',
    true)` therefore returns NULL on a perfectly healthy production database,
    and a check built on it would fail every single run for a reason that has
    nothing to do with PostgREST -- the textbook cry-wolf guard.

    A NULL result from `pg_db_role_setting` still flows into the judge and
    fails, which is the correct outcome: an unreadable PostgREST configuration
    is not evidence that PostgREST is fine.
    """
    pin = quote_literal(CLOCK_PIN_UTC)
    return (
        "select jsonb_build_object("
        "'pgrst_db_schemas', ("
        "  select split_part(cfg, '=', 2) from pg_db_role_setting s, "
        "  unnest(s.setconfig) as cfg where cfg like 'pgrst.db_schemas=%' limit 1), "
        "'server_timezone', current_setting('TimeZone', true), "
        "'pinned_utc', (current_date::text || ' ' || " + pin + ")::timestamp, "
        "'pinned_date_utc', ((current_date::text || ' ' || " + pin + ")"
        "::timestamp at time zone 'UTC')::date::text, "
        "'pinned_date_server', ((current_date::text || ' ' || " + pin + ")"
        "::timestamp at time zone 'UTC' at time zone current_setting('TimeZone'))"
        "::date::text, "
        "'observed_at_utc', (now() at time zone 'UTC')::text"
        ") as report"
    )


def build_batch_extra_sql(extra: BatchExtra) -> str:
    """One boolean row for ONE batch-specific assertion (contract §7.2).

    Each extra is its OWN query, on purpose. A `union all` of all of them is one
    statement, and one statement fails as a unit: `select count(*) from
    core.product_size` against a database where that table does not exist is a
    parse-time 400 that takes the OTHER checks down with it, so a single missing
    object reports as "no evidence" for everything and the operator learns
    nothing about the rest of the batch. One query each costs a handful of
    round trips and buys an independent verdict per assertion.
    """
    return (
        "select jsonb_build_object("
        f"'key', {quote_literal(extra.key)}, "
        f"'passed', ({extra.expression})"
        ") as report"
    )


def build_batch_extras_sql(extras: tuple[BatchExtra, ...]) -> str:
    """All batch extras as one statement. Used only by the tests and linting."""
    if not extras:
        return ""
    branches = [
        "select jsonb_build_object("
        f"'key', {quote_literal(e.key)}, "
        f"'passed', ({e.expression})"
        ") as x"
        for e in extras
    ]
    return (
        "select jsonb_agg(x order by x->>'key') as report from ("
        + " union all ".join(branches)
        + ") t"
    )


def batch_index(batch: str) -> int:
    """Position of a batch in the promotion order. UNKNOWN sorts last."""
    order = list(BATCH_RESTING_POINTS)
    return order.index(batch) if batch in order else len(order)


# ---------------------------------------------------------------------------
# Transport
# ---------------------------------------------------------------------------


def run_query(project_ref: str, token: str, sql: str, api: str = MANAGEMENT_API):
    """POST one strictly read-only statement to the Management API.

    `read_only: true` is sent so the SERVER, not this module's good intentions,
    is what forbids a write. The non-default User-Agent is mandatory: without
    it Cloudflare answers 403 (error 1010) and the run looks like an auth
    failure it is not.
    """
    url = f"{api.rstrip('/')}/v1/projects/{project_ref}/database/query"
    body = json.dumps({"query": sql, "read_only": True}).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": USER_AGENT,
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=180) as response:
        return json.loads(response.read().decode("utf-8"))


def extract_report(payload: object) -> object:
    """Pull the single `report` value out of whatever row shape comes back."""
    rows = payload
    if isinstance(rows, dict):
        for key in ("result", "data", "rows"):
            if isinstance(rows.get(key), list):
                rows = rows[key]
                break
    if not isinstance(rows, list) or not rows:
        raise VerificationError("query returned no rows")
    first = rows[0]
    if not isinstance(first, dict) or "report" not in first:
        raise VerificationError(f"query returned an unexpected shape: {first!r}")
    return first["report"]


# ---------------------------------------------------------------------------
# Verdicts
# ---------------------------------------------------------------------------


def _rows(value: object) -> list[dict]:
    """Normalise a jsonb_agg result to a list of dicts. NULL becomes empty."""
    if value is None:
        return []
    if isinstance(value, str):
        value = json.loads(value)
    if isinstance(value, dict):
        return [value]
    if isinstance(value, list):
        return [r for r in value if isinstance(r, dict)]
    return []


def judge_app(
    app: str,
    spec: AppSpec,
    relations: object,
    routines: object,
    columns: object,
    foreign_keys: object,
    batch: str = "B9",
    notes: list[str] | None = None,
) -> list[str]:
    """Return this application's failures. An empty list is a PASS.

    Every branch is written as a POSITIVE requirement -- "prove it is there" --
    never as "it was not reported broken". If the catalog said nothing about an
    object, that object failed.

    `batch` is the batch just applied. An object whose `arrives_in` is a LATER
    batch is not yet expected, so its absence is recorded in `notes` instead of
    failing -- a promotion plan that intends to create an object in B8 must not
    make this guard red from B1 to B7. From `arrives_in` onwards its absence is
    fatal like any other.

    `notes` collects non-fatal observations: not-yet-arrived objects, recorded
    baseline gaps, and baseline gaps that have CLOSED. Nothing is discarded.
    """
    failures: list[str] = []
    notes = notes if notes is not None else []
    here = batch_index(batch)

    if not spec.relations and not spec.routines:
        return [
            f"{app}: the manifest is EMPTY, so this run checked nothing. That is "
            "a failure, not a pass -- a check that proves nothing must never "
            "render as green."
        ]

    rel_rows = {r.get("relation"): r for r in _rows(relations)}
    fn_rows = {r.get("routine"): r for r in _rows(routines)}
    col_rows = {(r.get("relation"), r.get("column")): r for r in _rows(columns)}
    fk_rows = {(r.get("relation"), r.get("column")): r for r in _rows(foreign_keys)}

    for rel in spec.relations:
        pending = rel.arrives_in is not None and here < batch_index(rel.arrives_in)
        row = rel_rows.get(rel.qualified)
        if row is None:
            failures.append(
                f"{app}: NO EVIDENCE for {rel.qualified}. The catalog query "
                "returned nothing about an object this application reads. "
                "Absence of evidence is not a pass."
            )
            continue
        if not is_explicit_true(row.get("exists")):
            if pending:
                notes.append(
                    f"{app}: {rel.qualified} does not exist yet. The promotion plan "
                    f"creates it in {rel.arrives_in}, and {batch} is earlier, so this "
                    f"is expected -- but note what it means TODAY: {rel.why}"
                )
            else:
                failures.append(
                    f"{app}: {rel.qualified} DOES NOT EXIST (to_regclass is NULL). {rel.why}"
                )
            continue
        if pending:
            notes.append(
                f"{app}: {rel.qualified} already exists although the plan creates it "
                f"in {rel.arrives_in}. Verify it is the object the batch intends."
            )
        if not is_explicit_true(row.get("kind_ok")):
            failures.append(
                f"{app}: {rel.qualified} is relkind {row.get('relkind')!r}, which is "
                f"not the {rel.kind} this application reads. {rel.why}"
            )
        for priv in _rows(row.get("privileges")):
            name = priv.get("privilege")
            held = is_explicit_true(priv.get("held"))
            recorded_gap = name in rel.baseline_missing
            if held and recorded_gap:
                notes.append(
                    f"{app}: BASELINE GAP CLOSED -- {priv.get('role')!r} now holds "
                    f"{name} on {rel.qualified}. Remove it from `baseline_missing`; "
                    "a stale gap list is how a real failure gets waved through."
                )
            elif not held and recorded_gap:
                notes.append(
                    f"{app}: RECORDED BASELINE GAP -- {priv.get('role')!r} does not "
                    f"hold {name} on {rel.qualified}. This predates every batch and "
                    f"is a real PopPIM defect, not batch damage. {rel.why}"
                )
            elif not held:
                failures.append(
                    f"{app}: role {priv.get('role')!r} does NOT hold "
                    f"{name} on {rel.qualified} "
                    f"(reported {priv.get('held')!r}). {rel.why}"
                )

    for fn in spec.routines:
        row = fn_rows.get(fn.qualified)
        if row is None:
            failures.append(
                f"{app}: NO EVIDENCE for routine {fn.qualified}. Absence of "
                "evidence is not a pass."
            )
            continue
        if not is_explicit_true(row.get("exists")):
            failures.append(
                f"{app}: routine {fn.qualified} has ZERO overloads in pg_proc. {fn.why}"
            )
            continue
        for priv in _rows(row.get("privileges")):
            if not is_explicit_true(priv.get("held")):
                failures.append(
                    f"{app}: role {priv.get('role')!r} does NOT hold EXECUTE on "
                    f"{fn.qualified} (reported {priv.get('held')!r}). {fn.why}"
                )

    for rel in spec.relations:
        pending = rel.arrives_in is not None and here < batch_index(rel.arrives_in)
        for col in rel.columns:
            row = col_rows.get((rel.qualified, col))
            if pending:
                continue  # the relation itself is not due yet; already noted above
            if row is None:
                failures.append(
                    f"{app}: NO EVIDENCE for column {rel.qualified}.{col}."
                )
            elif not is_explicit_true(row.get("present")):
                failures.append(
                    f"{app}: column {rel.qualified}.{col} is MISSING. This "
                    "application filters on it, so its loss is a 400 or a "
                    f"silently empty result. {rel.why}"
                )

    for fk in spec.foreign_keys:
        row = fk_rows.get((f"{fk.schema}.{fk.table}", fk.column))
        if row is None:
            failures.append(
                f"{app}: NO EVIDENCE for the foreign key on "
                f"{fk.schema}.{fk.table}.{fk.column}."
            )
        elif not is_explicit_true(row.get("present")):
            failures.append(
                f"{app}: the foreign key on {fk.schema}.{fk.table}.{fk.column} is "
                f"MISSING. {fk.why}"
            )

    return failures


def judge_environment(environment: object, required=REQUIRED_POSTGREST_SCHEMAS) -> list[str]:
    """Check PostgREST exposure and the two-timezone date agreement."""
    rows = _rows(environment)
    if not rows:
        return [
            "ENVIRONMENT: no evidence at all -- the PostgREST exposure and clock "
            "probe returned nothing. Nothing downstream of this can be trusted."
        ]
    env = rows[0]
    failures: list[str] = []

    exposed_raw = env.get("pgrst_db_schemas")
    if not isinstance(exposed_raw, str) or not exposed_raw.strip():
        failures.append(
            "ENVIRONMENT: `pgrst.db_schemas` is NULL or empty. The applications "
            "reach this database THROUGH PostgREST, so an unreadable PostgREST "
            "configuration is not evidence that PostgREST is fine."
        )
    else:
        exposed = {s.strip() for s in exposed_raw.split(",") if s.strip()}
        for schema in required:
            if schema not in exposed:
                failures.append(
                    f"ENVIRONMENT: schema {schema!r} is NOT in pgrst.db_schemas "
                    f"({exposed_raw!r}). Every application object in it is "
                    "unreachable over the API even though it exists in the catalog."
                )
        for schema in sorted(POSTGREST_UNEXPOSED_SCHEMAS & exposed):
            failures.append(
                f"ENVIRONMENT: schema {schema!r} IS exposed through PostgREST. "
                "It holds confidential licensor data and production is documented "
                "as not exposing it. This is a widening, not a break, but it is "
                "not the state anyone signed off."
            )

    utc = env.get("pinned_date_utc")
    server = env.get("pinned_date_server")
    if not utc or not server:
        failures.append(
            "ENVIRONMENT: the clock probe did not return both dates, so the "
            "midday-UTC pinning could not be verified."
        )
    elif utc != server:
        failures.append(
            f"ENVIRONMENT: the date pinned to {CLOCK_PIN_UTC} UTC reads as {utc} "
            f"in UTC but {server} in {env.get('server_timezone')!r}. Midday UTC is "
            "supposed to fall on the same calendar day in both zones; if it does "
            "not, every date in this artifact is suspect."
        )
    return failures


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------


def render_report(
    resolution: BatchResolution,
    project_ref: str,
    per_app: dict[str, list[str]],
    environment_failures: list[str],
    extras: object,
    extras_spec: tuple[BatchExtra, ...],
    errors: list[str],
    notes: list[str] | None = None,
) -> tuple[str, list[str]]:
    lines: list[str] = []
    add = lines.append
    all_failures: list[str] = list(resolution.problems) + list(errors) + list(environment_failures)

    add("# Post-batch application verification")
    add("")
    add(f"- **Batch:** `{resolution.batch}`")
    add(f"- **Last applied version:** `{resolution.last_version}`")
    add(f"- **Project:** `{project_ref}`" + ("" if project_ref == PRODUCTION_PROJECT_REF else " — **NOT the production ref**"))
    add(f"- **Contract:** `docs/production-promotion-app-tolerance-contract.md` (issue #711, ruling D7)")
    add("")

    add("## Verdict per application")
    add("")
    add("| Application | Verdict | Failures |")
    add("|---|---|---|")
    for app in sorted(per_app):
        fails = per_app[app]
        add(f"| **{app}** | {'**FAIL**' if fails else 'PASS'} | {len(fails)} |")
        all_failures.extend(fails)
    add("")

    for app in sorted(per_app):
        spec = APP_MANIFEST[app]
        add(f"### {app}")
        add("")
        add(
            f"Checked {len(spec.relations)} relations, {len(spec.routines)} routines, "
            f"{sum(len(r.columns) for r in spec.relations)} filter columns, "
            f"{len(spec.foreign_keys)} foreign keys."
        )
        add("")
        if spec.notes:
            add(f"> {spec.notes}")
            add("")
        if per_app[app]:
            for f in per_app[app]:
                add(f"- FAIL: {f}")
        else:
            add("- PASS: every manifested object exists, is the expected kind, carries "
                "the privileges this application needs, and keeps the columns it filters on.")
        add("")

    add("## Batch-specific checks (contract §7.2)")
    add("")
    if not extras_spec:
        add(f"_The contract defines no batch-specific database check for {resolution.batch}._")
    else:
        rows = {r.get("key"): r for r in _rows(extras)}
        add("| Check | Result | Why it matters |")
        add("|---|---|---|")
        for e in extras_spec:
            row = rows.get(e.key)
            if row is None:
                verdict = "**NO EVIDENCE**"
                all_failures.append(
                    f"{resolution.batch}: NO EVIDENCE for the batch check "
                    f"`{e.key}`. {e.why}"
                )
            elif is_explicit_true(row.get("passed")):
                verdict = "PASS"
            else:
                verdict = "**FAIL**"
                all_failures.append(
                    f"{resolution.batch}: batch check `{e.key}` FAILED "
                    f"(reported {row.get('passed')!r}). {e.why}"
                )
            add(f"| `{e.key}` | {verdict} | {e.why} |")
    add("")

    add("## Environment")
    add("")
    if environment_failures:
        for f in environment_failures:
            add(f"- FAIL: {f}")
    else:
        add("- PASS: every schema the applications address is exposed through PostgREST, "
            "`plm` is correctly NOT exposed, and the midday-UTC date agrees in both "
            "UTC and server-local time.")
    add("")

    add("## Recorded gaps and not-yet-due objects — NOT counted as batch damage")
    add("")
    add(f"_{BASELINE_GAP_POLICY}_")
    add("")
    if notes:
        for n in notes:
            add(f"- {n}")
    else:
        add("_None. Every manifested object is due, present and fully granted._")
    add("")

    add("## Out of scope, and why")
    add("")
    for name, why in sorted(OUT_OF_SCOPE.items()):
        add(f"- **{name}** — {why}")
    add("")

    add("## Where the manifest and the contract disagree")
    add("")
    for note in MANIFEST_DRIFT:
        add(f"- {note}")
    add("")

    add("## What this run did NOT prove")
    add("")
    add("- It did **not open the applications**. A white page, a render crash or a "
        "wrong-looking picker is invisible to a catalog query. §7.1's five-minute "
        "smoke test is still required.")
    add("- It did **not read the PopCRM worker journal**. Worker breaks appear only "
        "in systemd, and the worker's own `/health` is a hardcoded `{ok:true}`.")
    add("- It did **not evaluate RLS semantics**. It reads catalog grants, not what "
        "a given end user can actually see through a policy.")
    add("- It did **not compare function bodies, argument names, argument defaults "
        "or return shapes**. PostgREST resolves overloads by ARGUMENT NAME; a "
        "renamed argument makes a function unfindable while `pg_proc` still shows "
        "an overload, and this check would pass.")
    add("- It did **not exercise DesignFlow non-production**, which receives every "
        "batch instantly and is the free rehearsal of §7.0.")
    add("")

    if all_failures:
        add("## FAILURES")
        add("")
        for f in all_failures:
            add(f"- {f}")
        add("")
    return "\n".join(lines) + "\n", all_failures


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------


def verify(
    resolution: BatchResolution,
    output_dir: Path,
    project_ref: str,
    token: str,
    api: str = MANAGEMENT_API,
    query=run_query,
) -> int:
    all_relations = [r for s in APP_MANIFEST.values() for r in s.relations]
    all_routines = [r for s in APP_MANIFEST.values() for r in s.routines]
    all_fks = [f for s in APP_MANIFEST.values() for f in s.foreign_keys]

    if not all_relations or not all_routines:
        print(
            "POST-BATCH APP VERIFICATION BLOCKED: the manifest is empty, so this "
            "run would prove nothing. Refusing to report a pass.",
            file=sys.stderr,
        )
        return 1

    errors: list[str] = []
    results: dict[str, object] = {}

    def fetch(label: str, sql: str, fatal: bool = True) -> object:
        if not sql:
            return None
        try:
            return extract_report(query(project_ref, token, sql, api))
        except (urllib.error.URLError, VerificationError, ValueError, OSError) as exc:
            if fatal:
                errors.append(
                    f"the {label} query FAILED ({exc}). There was something to "
                    "verify and it was not verified, so this run fails."
                )
            return None

    results["relations"] = fetch("relation", build_relation_sql(all_relations))
    results["routines"] = fetch("routine", build_routine_sql(all_routines))
    results["columns"] = fetch("column", build_column_sql(all_relations))
    results["foreign_keys"] = fetch("foreign key", build_foreign_key_sql(all_fks))
    results["environment"] = fetch("environment", build_environment_sql())

    extras_spec = BATCH_EXTRAS.get(resolution.batch, ())
    extra_rows: list[dict] = []
    for extra in extras_spec:
        # `fatal=False`: an extra that cannot run is NOT silently dropped -- it
        # simply never reaches `extra_rows`, and the reporter turns its absence
        # into a NO EVIDENCE failure with the check's own explanation attached,
        # which is more useful than a bare transport error.
        row = fetch(f"{resolution.batch}/{extra.key}", build_batch_extra_sql(extra), fatal=False)
        for parsed in _rows(row):
            extra_rows.append(parsed)
    results["batch_extras"] = extra_rows

    notes: list[str] = []
    per_app = {
        app: judge_app(
            app,
            spec,
            results["relations"],
            results["routines"],
            results["columns"],
            results["foreign_keys"],
            batch=resolution.batch,
            notes=notes,
        )
        for app, spec in APP_MANIFEST.items()
    }
    environment_failures = judge_environment(results["environment"])

    markdown, failures = render_report(
        resolution,
        project_ref,
        per_app,
        environment_failures,
        results["batch_extras"],
        extras_spec,
        errors,
        notes,
    )

    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "post-batch-app-verification.json").write_text(
        json.dumps(
            {
                "batch": resolution.batch,
                "last_version": resolution.last_version,
                "versions": resolution.versions,
                "project_ref": project_ref,
                "per_app": per_app,
                "notes": notes,
                "environment_failures": environment_failures,
                "raw": results,
                "errors": errors,
            },
            indent=2,
            sort_keys=True,
            default=str,
        ),
        encoding="utf-8",
    )
    (output_dir / "post-batch-app-verification.md").write_text(markdown, encoding="utf-8")
    print(markdown)

    if not failures:
        for app in sorted(per_app):
            print(f"{app}: PASS")
        if notes:
            print(
                f"POST-BATCH APP VERIFICATION: all three applications PASS, with "
                f"{len(notes)} recorded gap(s)/not-yet-due object(s) listed in the "
                "report. Read them; they are real, they are just not this batch's doing."
            )
        else:
            print("POST-BATCH APP VERIFICATION: all three applications PASS.")
        return 0

    for app in sorted(per_app):
        print(f"{app}: {'FAIL' if per_app[app] else 'PASS'}", file=sys.stderr)
    for f in failures:
        print(f"POST-BATCH APP VERIFICATION FAILURE: {f}", file=sys.stderr)
    return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Verify PopPIM / PopDAM / PopCRM database dependencies after a "
        "production batch lands (issue #711, owner ruling D7).",
    )
    group = parser.add_argument_group("what just landed")
    group.add_argument("--batch", help="batch id, e.g. B8 (contract §5)")
    group.add_argument(
        "--versions",
        help="comma- or space-separated migration versions just applied; the "
        "highest must be one of the ten legal resting points in contract §6",
    )
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--project-ref", required=True)
    # The token comes from the ENVIRONMENT, never argv: process arguments are
    # visible in OS process listings, and the rest of this lane already passes
    # SUPABASE_ACCESS_TOKEN by env.
    parser.add_argument(
        "--token-env",
        default="SUPABASE_ACCESS_TOKEN",
        help="name of the env var holding the Management API token",
    )
    args = parser.parse_args(argv)

    token = os.environ.get(args.token_env, "")
    if not token:
        print(
            f"POST-BATCH APP VERIFICATION BLOCKED: {args.token_env} is empty. "
            "Failing rather than reporting a verification that could never have run.",
            file=sys.stderr,
        )
        return 1
    try:
        resolution = resolve_batch(args.batch, args.versions)
    except VerificationError as exc:
        print(f"POST-BATCH APP VERIFICATION BLOCKED: {exc}", file=sys.stderr)
        return 1
    try:
        return verify(resolution, args.output_dir, args.project_ref, token)
    except (VerificationError, OSError) as exc:
        print(f"POST-BATCH APP VERIFICATION BLOCKED: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
