#!/usr/bin/env python3
import argparse
import csv
from pathlib import Path


def _first_present(row: dict, candidates: list[str]) -> str:
    for key in candidates:
        if key in row:
            return (row.get(key) or "").strip()
    return ""


def _load_tsv(tsv_path: Path) -> dict[str, str]:
    mapping: dict[str, str] = {}
    with tsv_path.open(newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        for row in reader:
            fasta_header = _first_present(row, ["fasta_header", "fasta_header_name"])
            if not fasta_header:
                continue
            lineage = (row.get("lineage") or "").strip()
            mapping[fasta_header] = lineage
    return mapping


def _load_csv(csv_path: Path) -> dict[str, str]:
    mapping: dict[str, str] = {}
    with csv_path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            fasta_header = (row.get("fasta_header") or "").strip()
            if not fasta_header:
                continue
            lineage = (row.get("lineage") or "").strip()
            mapping[fasta_header] = lineage
    return mapping


def _write_matches(common_keys: set[str], tsv_map: dict[str, str], csv_map: dict[str, str], output_path: Path) -> int:
    count = 0
    with output_path.open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle, fieldnames=["fasta_header", "lineage_tsv", "lineage_csv"]
        )
        writer.writeheader()
        for key in sorted(common_keys):
            if tsv_map[key] == csv_map[key]:
                writer.writerow(
                    {
                        "fasta_header": key,
                        "lineage_tsv": tsv_map[key],
                        "lineage_csv": csv_map[key],
                    }
                )
                count += 1
    return count


def _write_mismatches(common_keys: set[str], tsv_map: dict[str, str], csv_map: dict[str, str], output_path: Path) -> int:
    count = 0
    with output_path.open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle, fieldnames=["fasta_header", "lineage_tsv", "lineage_csv"]
        )
        writer.writeheader()
        for key in sorted(common_keys):
            if tsv_map[key] != csv_map[key]:
                writer.writerow(
                    {
                        "fasta_header": key,
                        "lineage_tsv": tsv_map[key],
                        "lineage_csv": csv_map[key],
                    }
                )
                count += 1
    return count


def _write_missing(tsv_map: dict[str, str], csv_map: dict[str, str], output_path: Path) -> tuple[int, int]:
    tsv_only = sorted(set(tsv_map) - set(csv_map))
    csv_only = sorted(set(csv_map) - set(tsv_map))

    with output_path.open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "fasta_header",
                "presence_label",
                "lineage_tsv",
                "lineage_csv",
            ],
        )
        writer.writeheader()
        for key in tsv_only:
            writer.writerow(
                {
                    "fasta_header": key,
                    "presence_label": "present_in_tsv_only",
                    "lineage_tsv": tsv_map[key],
                    "lineage_csv": "",
                }
            )
        for key in csv_only:
            writer.writerow(
                {
                    "fasta_header": key,
                    "presence_label": "present_in_csv_only",
                    "lineage_tsv": "",
                    "lineage_csv": csv_map[key],
                }
            )

    return len(tsv_only), len(csv_only)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Compare lineage fields between a metadata TSV and lineage CSV using fasta headers as keys."
        )
    )
    parser.add_argument("metadata_tsv", type=Path, help="Path to metadata TSV file")
    parser.add_argument("lineage_csv", type=Path, help="Path to lineage assignments CSV file")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("comparisons"),
        help="Directory to write output files (default: comparisons)",
    )
    args = parser.parse_args()

    if not args.metadata_tsv.exists():
        raise FileNotFoundError(f"Metadata TSV not found: {args.metadata_tsv}")
    if not args.lineage_csv.exists():
        raise FileNotFoundError(f"Lineage CSV not found: {args.lineage_csv}")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    matches_path = args.output_dir / "lineage_matches.csv"
    mismatches_path = args.output_dir / "lineage_mismatches.csv"
    missing_path = args.output_dir / "lineage_missing_between_files.csv"

    tsv_map = _load_tsv(args.metadata_tsv)
    csv_map = _load_csv(args.lineage_csv)
    common = set(tsv_map).intersection(csv_map)

    matching_count = _write_matches(common, tsv_map, csv_map, matches_path)
    mismatch_count = _write_mismatches(common, tsv_map, csv_map, mismatches_path)
    tsv_only_count, csv_only_count = _write_missing(tsv_map, csv_map, missing_path)

    print(f"Wrote: {matches_path}")
    print(f"Wrote: {mismatches_path}")
    print(f"Wrote: {missing_path}")
    print("Counts:")
    print(f"  tsv_keys = {len(tsv_map)}")
    print(f"  csv_keys = {len(csv_map)}")
    print(f"  common_keys = {len(common)}")
    print(f"  matching_lineage = {matching_count}")
    print(f"  nonmatching_lineage = {mismatch_count}")
    print(f"  only_in_tsv = {tsv_only_count}")
    print(f"  only_in_csv = {csv_only_count}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
