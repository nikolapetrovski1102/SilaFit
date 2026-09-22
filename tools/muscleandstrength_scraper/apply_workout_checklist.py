#!/usr/bin/env python3
"""Build the final workout dataset from a checklist and one or more scrapes."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from scrape import checklist_workout_cards, normalize_workout_days, parse_workout_detail


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CATALOG = ROOT / "data" / "scraped" / "muscleandstrength" / "workout_catalog.json"
DEFAULT_OUTPUT = ROOT / "data" / "scraped" / "muscleandstrength" / "workouts.json"


def load_records(paths: list[Path]) -> dict[str, dict[str, Any]]:
    records: dict[str, dict[str, Any]] = {}
    for path in paths:
        loaded = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(loaded, list):
            raise ValueError(f"Expected a JSON array in {path}")
        for item in loaded:
            if isinstance(item, dict) and item.get("url"):
                records[str(item["url"])] = item
    return records


def exercise_row_count(record: dict[str, Any]) -> int:
    return sum(
        len(table)
        for day in record.get("days") or []
        for table in day.get("exercise_tables") or []
        if isinstance(table, list)
    )


def repair_nested_workout_tables(record: dict[str, Any]) -> dict[str, Any]:
    if not record.get("description_html"):
        return {**record, "days": normalize_workout_days(record.get("days") or [])}
    wrapped_html = (
        "<html><body><div class='field-name-body'><div class='field-items'>"
        + str(record["description_html"])
        + "</div></div></body></html>"
    )
    reparsed = parse_workout_detail(wrapped_html, str(record["url"]))
    if exercise_row_count(reparsed):
        return {**record, "sections": reparsed["sections"], "days": reparsed["days"]}
    return {**record, "days": normalize_workout_days(record.get("days") or [])}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checklist", type=Path, required=True)
    parser.add_argument("--source", type=Path, action="append", required=True)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    cards = checklist_workout_cards(args.checklist, args.catalog)
    records = load_records(args.source)
    selected: list[dict[str, Any]] = []
    missing: list[str] = []
    invalid: list[str] = []
    for card in cards:
        detail = records.get(card["url"])
        if detail is None:
            missing.append(card["url"])
            continue
        detail = repair_nested_workout_tables(detail)
        if not detail.get("days") or not exercise_row_count(detail):
            invalid.append(card["url"])
            continue
        final = dict(detail)
        final.update(
            {
                "popularity_rank": card.get("popularity_rank"),
                "popularity_window": card.get("popularity_window"),
                "catalog_rank": card["catalog_rank"],
                "source_categories": card.get("source_categories", []),
                "catalog_summary": card.get("summary"),
                "catalog_tag": card.get("tag"),
                "catalog_metadata": card.get("metadata", []),
                "source_title": detail.get("source_title") or detail.get("title"),
                "title": card["import_title"],
            }
        )
        selected.append(final)

    if missing or invalid:
        messages = []
        if missing:
            messages.append("missing records:\n  " + "\n  ".join(missing))
        if invalid:
            messages.append("records without workout days:\n  " + "\n  ".join(invalid))
        raise ValueError("\n".join(messages))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(selected, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(args.output)
    print(f"wrote {len(selected)} checklist workouts to {args.output}")


if __name__ == "__main__":
    main()
