import tempfile
import unittest
from pathlib import Path

from check_pass2_routine_supersession import declared_routines, later_collisions, snapshot_query


class Pass2RoutineSupersessionTests(unittest.TestCase):
    def test_exact_orderlist_failure_is_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            old = root / "20260810010000_popdam_order_list_contract.sql"
            old.write_text(
                "create or replace function public.create_dam_order(p jsonb) returns void language sql as $$ select $$;\n"
                "create or replace function plm.dam_order_allowed_header_keys() returns text[] language sql as $$ select '{}'::text[] $$;\n",
                encoding="utf-8",
            )
            newer = root / "20260830111545_popdam_orderlist_input_only_write_contract.sql"
            newer.write_text(
                "CREATE OR REPLACE FUNCTION public.create_dam_order(p jsonb) returns void language sql as $$ select $$;\n"
                "CREATE OR REPLACE FUNCTION plm.dam_order_allowed_header_keys() returns text[] language sql as $$ select '{}'::text[] $$;\n",
                encoding="utf-8",
            )
            self.assertEqual(
                later_collisions(old, root),
                {
                    "plm.dam_order_allowed_header_keys": [newer.name],
                    "public.create_dam_order": [newer.name],
                },
            )

    def test_only_later_files_count(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            current = root / "20260810010000_current.sql"
            current.write_text("create or replace function public.f() returns void language sql as $$ select $$;", encoding="utf-8")
            (root / "20260809000000_earlier.sql").write_text("create or replace function public.f() returns void language sql as $$ select $$;", encoding="utf-8")
            self.assertEqual(later_collisions(current, root), {})

    def test_ignores_comment_mentions(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "x.sql"
            path.write_text("-- create or replace function public.fake()\nselect 1;", encoding="utf-8")
            self.assertEqual(declared_routines(path), set())

    def test_snapshot_query_selects_every_colliding_routine(self):
        query = snapshot_query({"public.f": ["later.sql"], '"plm"."g"': ["later.sql"]})
        self.assertIn("'public.f'", query)
        self.assertIn("'plm.g'", query)
        self.assertIn("pg_get_function_identity_arguments", query)

    def test_snapshot_restores_routine_attributes_not_in_function_definition(self):
        query = snapshot_query({"public.f": ["later.sql"]}).lower()
        self.assertIn("security %s", query)
        self.assertIn("then 'definer' else 'invoker'", query)
        self.assertIn("reset all", query)
        self.assertNotIn("p.proconfig", query)
        self.assertNotIn(" set %s to ", query)
        self.assertIn("p.prokind = 'p'", query)
        self.assertIn("do $pass2$ begin if exists", query)
        self.assertIn("then execute %l", query)
        self.assertLess(query.index("reset all"), query.index("pg_get_functiondef"))
        self.assertLess(query.index("pg_get_functiondef"), query.index("security %s"))

    def test_real_dam_search_restore_uses_newlines_not_psql_backslash_commands(self):
        query = snapshot_query(
            {
                "public.search_assets_full_text": ["20260831074401_later.sql"],
                "public.search_style_groups_full_text": ["20260831074401_later.sql"],
            }
        ).lower()
        self.assertIn("'public.search_assets_full_text'", query)
        self.assertIn("'public.search_style_groups_full_text'", query)
        self.assertIn("pg_get_function_identity_arguments(p.oid)", query)
        self.assertEqual(query.count("format(e'alter"), 1)
        self.assertNotIn("format('alter %s %i.%i(%s) security", query)
        self.assertIn("format('alter %s %i.%i(%s) reset all", query)

    def test_search_path_lists_are_left_to_pg_get_functiondef(self):
        query = snapshot_query({"public.search_dam_documents": ["later.sql"]}).lower()
        self.assertIn("pg_get_functiondef(p.oid)", query)
        self.assertNotIn("unnest(p.proconfig)", query)
        self.assertNotIn("split_part(setting", query)
        self.assertNotIn("substr(setting", query)

    def test_missing_saved_overload_skips_only_reset_before_recreation(self):
        query = snapshot_query({"public.search_dam_documents": ["later.sql"]}).lower()
        self.assertIn("if exists (select 1 from pg_proc p2", query)
        self.assertIn("pg_get_function_identity_arguments(p2.oid) = %l", query)
        self.assertIn("p2.prokind = %l", query)
        self.assertIn("then execute %l; end if", query)
        self.assertLess(query.index("end $pass2$"), query.index("pg_get_functiondef"))


if __name__ == "__main__":
    unittest.main()
