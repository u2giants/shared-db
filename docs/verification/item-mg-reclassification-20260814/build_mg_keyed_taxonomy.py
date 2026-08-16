"""Build the post-change description dictionary with MG01|MG02|MG03 as the hard key."""

from __future__ import annotations

import json
import re
import unicodedata
from collections import Counter, defaultdict
from difflib import SequenceMatcher
from pathlib import Path

import pandas as pd


PRIVATE = Path(__file__).resolve().parents[3] / ".private" / "item-mg-reclassification-20260814"
CUTOFF = pd.Timestamp("2025-05-14")
REWORK = Path(r"T:\shared\_11 designflow\MerchGroup_Rework.xlsx")


def normalized(value: object) -> str:
    text = unicodedata.normalize("NFKD", "" if pd.isna(value) else str(value)).encode("ascii", "ignore").decode().lower()
    text = text.replace("shadow box", "shadowbox").replace("die-cut", "diecut")
    return " ".join(re.sub(r"[^a-z0-9]+", " ", text).split())


def dimension_signature(value: object) -> str:
    text = unicodedata.normalize("NFKD", str(value)).encode("ascii", "ignore").decode().lower().replace("×", "x")
    match = re.search(
        r"(?<![a-z0-9])(\d+(?:\.\d+)?)\s*x\s*(\d+(?:\.\d+)?)(?:\s*[\"']?\s*x\s*(\d+(?:\.\d+)?))?",
        text,
    )
    if not match:
        return ""
    face = sorted(float(value) for value in match.groups()[:2])
    result = f"{face[0]:g}x{face[1]:g}"
    if match.group(3):
        result += f"x{float(match.group(3)):g}"
    return result


def comparison_signature(value: object) -> str:
    text = unicodedata.normalize("NFKD", str(value)).encode("ascii", "ignore").decode().lower().replace("×", "x")
    text = text.replace("holo foil", "holofoil").replace("shadow box", "shadowbox").replace("die-cut", "diecut")
    text = re.sub(
        r"(?<![a-z0-9])\d+(?:\.\d+)?\s*x\s*\d+(?:\.\d+)?(?:\s*[\"']?\s*x\s*\d+(?:\.\d+)?)?\s*(?:inches|inch|in|cm|mm|\")?",
        " ",
        text,
    )
    text = re.sub(r"\b(?:with|and|the|a|an|w)\b", " ", text)
    return " ".join(re.sub(r"[^a-z0-9]+", " ", text).split())


def treatment_profile(value: object) -> str:
    text = normalized(value).replace("holo foil", "holofoil")
    treatments = []
    patterns = (
        ("foil", r"\b(?:holofoil|foil)\b"),
        ("high-gloss", r"\b(?:hi gloss|high gloss|gloss)\b"),
        ("embroidery", r"\b(?:embroidery|embroidered|chenille)\b"),
        ("diy", r"\b(?:diy|pbn|paint by numbers?|paint your own)\b"),
        ("led", r"\b(?:led|light up|lighted)\b"),
        ("glitter", r"\b(?:glitter|sequins?|rhinestones?)\b"),
        ("handpaint", r"\b(?:handpaint|hand painted)\b"),
        ("attachment", r"\b(?:attachment|physical attachment)\b"),
        ("gel", r"\b(?:gel coat|gel coated|gel paint)\b"),
        ("staggered", r"\bstaggered\b"),
        ("shaped", r"\b(?:shaped|diecut|round)\b"),
    )
    for name, pattern in patterns:
        if re.search(pattern, text):
            treatments.append(name)
    return "+".join(treatments)


def token_similarity(left: str, right: str) -> tuple[float, float]:
    left_tokens, right_tokens = set(left.split()), set(right.split())
    union = left_tokens | right_tokens
    jaccard = len(left_tokens & right_tokens) / len(union) if union else 0.0
    sequence = SequenceMatcher(None, left, right).ratio()
    return sequence, jaccard


def assign_from_later_analog(row: pd.Series, candidates: list[dict]) -> dict:
    signature = comparison_signature(row["Original Item Desc"])
    size = dimension_signature(row["Original Item Desc"])
    if not signature or signature in {"test", "fees", "mdpd fees"} or not candidates:
        return {}

    exact = [candidate for candidate in candidates if candidate["signature"] == signature]
    exact_same_size = [candidate for candidate in exact if size and candidate["size"] == size]
    strongest_exact = exact_same_size or exact
    exact_keys = {candidate["key"] for candidate in strongest_exact}
    if strongest_exact and len(exact_keys) == 1:
        best = max(strongest_exact, key=lambda candidate: candidate["date"])
        return {**best, "score": 100.0, "reason": "Same normalized product, treatment and artwork wording in a later item"}

    if not row["Treatment Profile"]:
        return {}
    scored = []
    for candidate in candidates:
        sequence, jaccard = token_similarity(signature, candidate["signature"])
        size_score = 1.0 if size and size == candidate["size"] else (0.4 if not size or not candidate["size"] else 0.0)
        score = 0.55 * sequence + 0.35 * jaccard + 0.10 * size_score
        scored.append((score, candidate))
    scored.sort(key=lambda value: (value[0], value[1]["date"]), reverse=True)
    best_score, best = scored[0]
    runner_score = scored[1][0] if len(scored) > 1 and scored[1][1]["key"] != best["key"] else 0.0
    close_keys = {candidate["key"] for score, candidate in scored if score >= best_score - 0.03}
    if best_score >= 0.80 and len(close_keys) == 1 and best_score - runner_score >= 0.08:
        return {**best, "score": round(best_score * 100, 1), "reason": "Strong later analog with the same product, explicit treatment and comparable wording"}
    return {}


def canonical_for_row(description: str, semantic: str, chunk: str) -> str:
    value = normalized(description)
    if "canvas" in value and ("diy" in value or "paint by numbers" in value or re.search(r"\bpbn\b", value)):
        return "Paint-Your-Own Canvas Set"
    return semantic or chunk


def join_unique(values, limit: int = 60) -> str:
    seen = []
    for value in values:
        value = str(value).strip()
        if value and value not in seen:
            seen.append(value)
    return " | ".join(seen[:limit])


def main() -> None:
    semantic = pd.read_csv(PRIVATE / "semantic_product_type_rows.csv", dtype=str).fillna("")
    chunks = pd.read_csv(PRIVATE / "item_description_chunks.csv", dtype=str).fillna("")
    chunk_by_row = chunks.set_index("Source CSV Row")["Item Type"].to_dict()
    semantic["Date"] = pd.to_datetime(semantic["Created Date"], errors="coerce")
    post = semantic[semantic["Date"].ge(CUTOFF)].copy()
    for column in ("MG01", "MG02", "MG03"):
        post[column] = post[column].astype(str).str.strip().str.upper()
    post["MG Key"] = post[["MG01", "MG02", "MG03"]].astype(str).agg("|".join, axis=1)
    post["Complete MG Key"] = post[["MG01", "MG02", "MG03"]].ne("").all(axis=1)
    post["Chunk Item Type"] = post["Source CSV Row"].map(chunk_by_row).fillna("")
    post["Canonical Product Wording"] = post.apply(
        lambda row: canonical_for_row(row["Original Item Desc"], row["Canonical Product Type"], row["Chunk Item Type"]), axis=1
    )
    post["Observed Product Wording"] = post.apply(
        lambda row: row["Matched Wording"] or row["Chunk Item Type"] or row["Canonical Product Wording"], axis=1
    )

    complete = post[post["Complete MG Key"]].copy()
    definitions = pd.read_excel(REWORK, sheet_name="Final Version", header=2, dtype=str).fillna("")
    definition_map = defaultdict(list)
    for _, row in definitions.iterrows():
        codes = tuple(str(row[column]).strip().upper() for column in ("MG01 code", "MG02 code", "MG03 code"))
        if not all(codes):
            continue
        definition_map[codes].append({
            "MG01 Meaning": str(row["MG01 - Product Type"]).strip(),
            "MG02 Meaning": str(row["MG02 - Product Sub-Type"]).strip(),
            "MG03 Meaning": str(row["MG03 - Prod Sub-Sub-Type"]).strip() or "No additional description",
        })
    groups = []
    for key, part in complete.groupby("MG Key", sort=True):
        types = sorted(set(value for value in part["Canonical Product Wording"] if value))
        base_codes = tuple(str(part.iloc[0][column]).strip().upper()[:1] for column in ("MG01", "MG02", "MG03"))
        options = definition_map.get(base_codes, [])
        evidence = normalized(" ".join(types) + " " + " ".join(part["Observed Product Wording"].astype(str).unique()))
        def score(option):
            terms = normalized(f"{option['MG02 Meaning']} {option['MG03 Meaning']}").split()
            meaningful = [term for term in terms if len(term) > 2 and term not in {"with", "other", "additional", "description"}]
            return (sum(re.search(rf"\b{re.escape(term)}\b", evidence) is not None for term in meaningful), -len(meaningful))
        definition = max(options, key=score) if options else {}
        option_text = " | ".join(
            f"{option['MG01 Meaning']} > {option['MG02 Meaning']} > {option['MG03 Meaning']}" for option in options
        ) or "Unmapped"
        combined_meaning = " > ".join(value for value in (
            definition.get("MG01 Meaning", ""), definition.get("MG02 Meaning", ""), definition.get("MG03 Meaning", "")
        ) if value)
        unresolved = int(part["Canonical Product Wording"].eq("").sum())
        examples = part["Original Item Desc"].drop_duplicates().head(5).tolist()
        groups.append({
            "MG Primary Key": key,
            "MG01": part.iloc[0]["MG01"], "MG02": part.iloc[0]["MG02"], "MG03": part.iloc[0]["MG03"],
            "MG01 Meaning": definition.get("MG01 Meaning", "Unmapped"),
            "MG02 Meaning": definition.get("MG02 Meaning", "Unmapped"),
            "MG03 Meaning": definition.get("MG03 Meaning", "Unmapped"),
            "Combined Product Meaning": combined_meaning or "Unmapped",
            "Rework Definition Options": option_text,
            "Definition Status": "Unmapped" if not options else ("Multiple definitions; interpreted from descriptions" if len(options) > 1 else "Unique definition"),
            "Item Count": len(part), "Resolved Item Count": len(part) - unresolved, "Unresolved Item Count": unresolved,
            "Distinct Product Wording Count": len(types),
            "Associated Product Wordings": " | ".join(types),
            "Observed Wording Variants": join_unique(part["Observed Product Wording"]),
            "Example Item Description 1": examples[0] if examples else "",
            "Example Item Description 2": examples[1] if len(examples) > 1 else "",
            "Example Item Description 3": examples[2] if len(examples) > 2 else "",
            "Example Item Description 4": examples[3] if len(examples) > 3 else "",
            "Example Item Description 5": examples[4] if len(examples) > 4 else "",
            "Reviewer Decision": "", "Reviewer Notes": "",
        })

    detail = post.drop(columns=["Date", "Complete MG Key", "Chunk Item Type"]).rename(columns={
        "Canonical Product Type": "Previous Extracted Product Type",
    })
    detail["Review Status"] = detail.apply(
        lambda row: "Incomplete MG Key" if not all([row["MG01"], row["MG02"], row["MG03"]]) else ("Resolved" if row["Canonical Product Wording"] else "Unresolved Product Wording"), axis=1
    )
    detail_records = detail.to_dict(orient="records")
    pre = semantic[semantic["Date"].lt(CUTOFF)].copy()
    pre["Chunk Item Type"] = pre["Source CSV Row"].map(chunk_by_row).fillna("")
    pre["Extracted Product Wording"] = pre.apply(
        lambda row: canonical_for_row(row["Original Item Desc"], row["Canonical Product Type"], row["Chunk Item Type"]), axis=1
    )
    post["Product Signature"] = post["Canonical Product Wording"].map(normalized)
    post["Treatment Profile"] = post["Original Item Desc"].map(treatment_profile)
    analogs = defaultdict(list)
    for _, later in post[post["Complete MG Key"]].iterrows():
        analogs[(later["Product Signature"], later["Treatment Profile"])].append({
            "key": later["MG Key"], "item": later["Item #"], "description": later["Original Item Desc"],
            "date": later["Created Date"], "source_row": later["Source CSV Row"],
            "signature": comparison_signature(later["Original Item Desc"]),
            "size": dimension_signature(later["Original Item Desc"]),
        })
    pre["Product Signature"] = pre["Extracted Product Wording"].map(normalized)
    pre["Treatment Profile"] = pre["Original Item Desc"].map(treatment_profile)
    assignments = []
    for _, old in pre.iterrows():
        candidates = analogs.get((old["Product Signature"], old["Treatment Profile"]), [])
        assignments.append(assign_from_later_analog(old, candidates))
    pre["Proposed MG01"] = [match.get("key", "").split("|")[0] if match else "" for match in assignments]
    pre["Proposed MG02"] = [match.get("key", "").split("|")[1] if match else "" for match in assignments]
    pre["Proposed MG03"] = [match.get("key", "").split("|")[2] if match else "" for match in assignments]
    pre["Matched Later Item #"] = [match.get("item", "") for match in assignments]
    pre["Matched Later Item Desc"] = [match.get("description", "") for match in assignments]
    pre["Matched Later Date"] = [match.get("date", "") for match in assignments]
    pre["Matched Later MG Key"] = [match.get("key", "") for match in assignments]
    pre["Analog Match Score"] = [match.get("score", "") for match in assignments]
    pre["MG Evidence"] = [match.get("reason", "") for match in assignments]
    statuses = []
    for (_, old), match in zip(pre.iterrows(), assignments):
        if match:
            current = "|".join(str(old[column]).strip() for column in ("MG01", "MG02", "MG03"))
            statuses.append("High-confidence later analog; current MG differs" if current != match["key"] else "High-confidence later analog; current MG agrees")
        elif old["Extracted Product Wording"]:
            statuses.append("Product wording extracted; MG unresolved")
        else:
            statuses.append("Product wording unresolved")
    pre["MG Assignment Status"] = statuses
    pre_records = pre.drop(columns=["Date", "Chunk Item Type"]).to_dict(orient="records")
    assigned_count = sum(bool(match) for match in assignments)
    changed_count = sum(
        bool(match) and "|".join(str(old[column]).strip() for column in ("MG01", "MG02", "MG03")) != match["key"]
        for (_, old), match in zip(pre.iterrows(), assignments)
    )
    summary = {
        "cutoff": "2025-05-14", "post_change_items": len(post),
        "complete_key_items": len(complete), "incomplete_key_items": len(post) - len(complete),
        "mg_primary_keys": len(groups),
        "mapped_rework_keys": sum(group["Combined Product Meaning"] != "Unmapped" for group in groups),
        "unmapped_rework_keys": sum(group["Combined Product Meaning"] == "Unmapped" for group in groups),
        "resolved_product_wording_items": int(complete["Canonical Product Wording"].ne("").sum()),
        "unresolved_product_wording_items": int(complete["Canonical Product Wording"].eq("").sum()),
        "pre_change_items": len(pre),
        "pre_change_product_wording_resolved": int(pre["Extracted Product Wording"].ne("").sum()),
        "pre_change_product_wording_unresolved": int(pre["Extracted Product Wording"].eq("").sum()),
        "pre_change_high_confidence_mg_assignments": assigned_count,
        "pre_change_high_confidence_mg_changes": changed_count,
    }
    for name, value in {
        "mg_key_groups.json": groups, "mg_post_change_rows.json": detail_records,
        "mg_pre_change_rows.json": pre_records, "mg_keyed_summary.json": summary,
    }.items():
        (PRIVATE / name).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
