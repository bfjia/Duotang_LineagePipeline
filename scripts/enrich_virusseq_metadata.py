#!/usr/bin/env python3
"""Populate VirusSeq metadata lineage columns from latest_lineage_assignments.csv."""

from __future__ import annotations

import argparse
import csv
import gzip
import sys
from pathlib import Path


JOIN_KEY_CANDIDATES = (
    "fasta_header_name",
    "fasta_header",
    "fasta header name",
)

CANONICAL_TARGETS = (
    "lineage name",
    "lineage analysis software name",
    "lineage analysis software version",
    "lineage analysis software data version",
    "scorpio call",
    "scorpio version",
)


def _open_text(path: Path):
    p = str(path)
    if p.endswith(".gz"):
        return gzip.open(path, "rt", encoding="utf-8", errors="replace", newline="")
    return path.open("r", encoding="utf-8", errors="replace", newline="")


def _sniff_delimiter(first_line: str) -> str:
    try:
        dialect = csv.Sniffer().sniff(first_line, delimiters=",\t")
        return dialect.delimiter
    except csv.Error:
        if "\t" in first_line:
            return "\t"
        return ","


def _find_join_key(fieldnames: list[str]) -> str | None:
    if not fieldnames:
        return None
    lower_map = {f.strip().lower(): f for f in fieldnames}
    for cand in JOIN_KEY_CANDIDATES:
        if cand.lower() in lower_map:
            return lower_map[cand.lower()]
    for f in fieldnames:
        fl = f.strip().lower()
        if "fasta" in fl and "header" in fl:
            return f
    return None


def _resolve_header(fieldnames: list[str], canonical: str) -> str:
    c = canonical.strip().lower()
    for f in fieldnames:
        if f.strip().lower() == c:
            return f
    return canonical


def _load_lineage(path: Path) -> dict[str, dict[str, str]]:
    out: dict[str, dict[str, str]] = {}
    with path.open(newline="", encoding="utf-8", errors="replace") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            key = (row.get("fasta_header") or "").strip()
            if key:
                out[key] = row
    return out


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Merge pangolin lineage fields into VirusSeq metadata."
    )
    ap.add_argument("metadata_gz", type=Path, help="Path to virusseq.metadata.csv.gz")
    ap.add_argument("lineage_csv", type=Path, help="Path to latest_lineage_assignments.csv")
    ap.add_argument("output_gz", type=Path, help="Output path (.csv.gz supported)")
    ap.add_argument(
        "--pangolin-version",
        required=True,
        help="From `pangolin --all-versions` (pangolin line)",
    )
    ap.add_argument(
        "--pangolin-data-version",
        required=True,
        help="From `pangolin --all-versions` (pangolin-data line)",
    )
    ap.add_argument(
        "--scorpio-version",
        required=True,
        help="From `pangolin --all-versions` (scorpio line)",
    )
    args = ap.parse_args()

    if not args.metadata_gz.is_file():
        print(f"Error: metadata file not found: {args.metadata_gz}", file=sys.stderr)
        return 1
    if not args.lineage_csv.is_file():
        print(f"Error: lineage CSV not found: {args.lineage_csv}", file=sys.stderr)
        return 1

    lineage_by_header = _load_lineage(args.lineage_csv)

    with _open_text(args.metadata_gz) as handle:
        first = handle.readline()
        if not first:
            print("Error: empty metadata file.", file=sys.stderr)
            return 1
        delim = _sniff_delimiter(first)
        handle.seek(0)
        reader = csv.DictReader(handle, delimiter=delim)

        if not reader.fieldnames:
            print("Error: metadata has no header row.", file=sys.stderr)
            return 1

        join_key = _find_join_key(list(reader.fieldnames))
        if not join_key:
            print(
                "Error: could not find a FASTA header column "
                f"(tried {JOIN_KEY_CANDIDATES}).",
                file=sys.stderr,
            )
            return 1

        fieldnames = list(reader.fieldnames)
        missing_targets = []
        for canon in CANONICAL_TARGETS:
            resolved = _resolve_header(fieldnames, canon)
            if resolved not in fieldnames:
                missing_targets.append(canon)
        if missing_targets:
            print(
                "Error: metadata is missing required target columns: "
                + ", ".join(missing_targets),
                file=sys.stderr,
            )
            return 1

        col_lineage_name = _resolve_header(fieldnames, "lineage name")
        col_soft_name = _resolve_header(fieldnames, "lineage analysis software name")
        col_soft_ver = _resolve_header(fieldnames, "lineage analysis software version")
        col_data_ver = _resolve_header(fieldnames, "lineage analysis software data version")
        col_scorpio_call = _resolve_header(fieldnames, "scorpio call")
        col_scorpio_ver = _resolve_header(fieldnames, "scorpio version")

        out_path = args.output_gz
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_open = (
            gzip.open(out_path, "wt", encoding="utf-8", newline="", compresslevel=6)
            if str(out_path).endswith(".gz")
            else out_path.open("w", encoding="utf-8", newline="")
        )

        with out_open as out_handle:
            writer = csv.DictWriter(out_handle, fieldnames=fieldnames, delimiter=delim)
            writer.writeheader()
            for row in reader:
                key = (row.get(join_key) or "").strip()
                src = lineage_by_header.get(key)
                if src:
                    row[col_lineage_name] = (src.get("lineage") or "").strip()
                    row[col_scorpio_call] = (src.get("scorpio_call") or "").strip()
                    row[col_soft_name] = "pangolin"
                    row[col_soft_ver] = args.pangolin_version.strip()
                    row[col_data_ver] = args.pangolin_data_version.strip()
                    row[col_scorpio_ver] = args.scorpio_version.strip()
                writer.writerow(row)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
