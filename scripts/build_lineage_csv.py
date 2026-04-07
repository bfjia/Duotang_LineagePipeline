#!/usr/bin/env python3
import csv
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 4:
        print(
            "Usage: build_lineage_csv.py <input_fasta> <raw_pangolin_csv> <final_csv>",
            file=sys.stderr,
        )
        return 1

    fasta_path = Path(sys.argv[1])
    raw_report_path = Path(sys.argv[2])
    final_report_path = Path(sys.argv[3])

    headers = []
    with fasta_path.open() as handle:
        for line in handle:
            if line.startswith(">"):
                headers.append(line[1:].strip())

    if not headers:
        print("No FASTA headers found in input.", file=sys.stderr)
        return 1

    rows_by_taxon = {}
    with raw_report_path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            taxon = row.get("taxon", "")
            if taxon:
                rows_by_taxon[taxon] = row

    final_columns = [
        "fasta_header",
        "lineage",
        "status",
        "note",
        "conflict",
        "ambiguity_score",
        "scorpio_call",
        "scorpio_support",
        "scorpio_conflict",
        "version",
        "pangolin_version",
        "pangoLEARN_version",
        "pango_version",
    ]

    with final_report_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=final_columns)
        writer.writeheader()
        for fasta_header in headers:
            source = rows_by_taxon.get(fasta_header, {})
            writer.writerow(
                {
                    "fasta_header": fasta_header,
                    "lineage": source.get("lineage", ""),
                    "status": source.get("status", ""),
                    "note": source.get("note", ""),
                    "conflict": source.get("conflict", ""),
                    "ambiguity_score": source.get("ambiguity_score", ""),
                    "scorpio_call": source.get("scorpio_call", ""),
                    "scorpio_support": source.get("scorpio_support", ""),
                    "scorpio_conflict": source.get("scorpio_conflict", ""),
                    "version": source.get("version", ""),
                    "pangolin_version": source.get("pangolin_version", ""),
                    "pangoLEARN_version": source.get("pangoLEARN_version", ""),
                    "pango_version": source.get("pango_version", ""),
                }
            )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
