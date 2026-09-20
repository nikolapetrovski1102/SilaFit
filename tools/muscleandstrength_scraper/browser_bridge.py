#!/usr/bin/env python3
"""Local-only JSON receiver for collections made in an accepted browser session."""

from __future__ import annotations

import argparse
import base64
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from scrape import parse_workout_detail


def repair_workout_day_tables(output_dir: Path) -> int:
    """Repair repeated arrays flattened by some browser serialization bridges."""
    path = output_dir / "workouts.json"
    if not path.exists():
        return 0
    records = json.loads(path.read_text(encoding="utf-8"))
    repaired = 0
    for workout in records:
        sections = {section.get("heading"): section for section in workout.get("sections", [])}
        for day in workout.get("days", []):
            if day.get("exercise_tables") != "[Circular]":
                continue
            section = sections.get(day.get("title"))
            day["exercise_tables"] = section.get("tables", []) if section else []
            repaired += 1
    if repaired:
        temporary = path.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary.replace(path)
    return repaired


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--token", required=True)
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    repaired = repair_workout_day_tables(args.output_dir)
    if repaired:
        print(f"repaired {repaired} workout day-table references", flush=True)
    chunks: dict[tuple[str, str], dict[int, str]] = {}
    chunk_lock = threading.Lock()
    save_lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802
            parsed = urlparse(self.path)
            query = parse_qs(parsed.query)
            if query.get("token", [""])[0] != args.token:
                self.send_error(403)
                return
            if parsed.path != "/record":
                self.send_error(404)
                return
            dataset = query.get("dataset", [""])[0]
            record_id = query.get("id", [""])[0]
            if dataset not in {"workouts", "workout_html", "workout_catalog", "diets", "recipes", "manifest"} or not record_id:
                self.send_error(400)
                return
            try:
                index = int(query.get("index", [""])[0])
                total = int(query.get("total", [""])[0])
                chunk = query.get("data", [""])[0]
                key = (dataset, record_id)
                with chunk_lock:
                    parts = chunks.setdefault(key, {})
                    parts[index] = chunk
                    complete = len(parts) == total
                    if complete:
                        encoded = "".join(parts[i] for i in range(total))
                        del chunks[key]
                if complete:
                    padding = "=" * (-len(encoded) % 4)
                    record = json.loads(base64.urlsafe_b64decode(encoded + padding))
                    self._save_record(dataset, record)
            except (ValueError, KeyError, json.JSONDecodeError) as exc:
                self.send_error(400, str(exc))
                return
            self.send_response(204)
            self.end_headers()

        def do_OPTIONS(self) -> None:  # noqa: N802
            self.send_response(204)
            self._cors()
            self.end_headers()

        def do_POST(self) -> None:  # noqa: N802
            target = urlparse(self.path).path.strip("/")
            if self.headers.get("X-Bridge-Token") != args.token:
                self.send_error(403)
                return
            if target == "ping":
                self.send_response(204)
                self._cors()
                self.end_headers()
                return
            if target not in {"workouts", "workout_html", "diets", "recipes", "manifest"}:
                self.send_error(404)
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                payload = json.loads(self.rfile.read(length))
                self._save_record(target, payload)
            except (ValueError, json.JSONDecodeError) as exc:
                self.send_error(400, str(exc))
                return
            self.send_response(204)
            self._cors()
            self.end_headers()

        def _cors(self) -> None:
            self.send_header("Access-Control-Allow-Origin", "https://www.muscleandstrength.com")
            self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Bridge-Token")
            self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
            self.send_header("Access-Control-Allow-Private-Network", "true")

        def _save_record(self, dataset: str, record: object) -> None:
            if dataset == "workout_html":
                if not isinstance(record, dict) or not record.get("url") or not record.get("html"):
                    raise ValueError("workout_html requires url and html")
                parsed = parse_workout_detail(str(record["html"]), str(record["url"]))
                parsed.update({
                    "popularity_rank": record.get("popularity_rank"),
                    "popularity_window": record.get("popularity_window"),
                    "catalog_rank": record.get("catalog_rank"),
                    "source_categories": record.get("source_categories", []),
                    "catalog_summary": record.get("catalog_summary"),
                    "catalog_tag": record.get("catalog_tag"),
                    "catalog_metadata": record.get("catalog_metadata", []),
                })
                dataset = "workouts"
                record = parsed
            with save_lock:
                destination = args.output_dir / f"{dataset}.json"
                if isinstance(record, dict) and "__replace__" in record:
                    value = record["__replace__"]
                elif dataset == "manifest":
                    value = record
                else:
                    value = []
                    if destination.exists():
                        loaded = json.loads(destination.read_text(encoding="utf-8"))
                        if isinstance(loaded, list):
                            value = loaded
                    assert isinstance(value, list)
                    source_url = record.get("url") if isinstance(record, dict) else None
                    if source_url:
                        previous = next(
                            (item for item in value if isinstance(item, dict) and item.get("url") == source_url),
                            None,
                        )
                        if previous and isinstance(record, dict):
                            record = {
                                **previous,
                                **{key: item for key, item in record.items() if item is not None},
                            }
                        value = [item for item in value if not isinstance(item, dict) or item.get("url") != source_url]
                    value.append(record)
                temporary = destination.with_name(
                    f"{destination.name}.{threading.get_ident()}.tmp"
                )
                temporary.write_text(
                    json.dumps(value, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8",
                )
                temporary.replace(destination)

        def log_message(self, format: str, *values: object) -> None:
            message = format % values
            if "/record?" not in message:
                print(f"bridge: {message}", flush=True)

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"bridge listening on http://127.0.0.1:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
