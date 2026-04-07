#!/usr/bin/env bash
set -euo pipefail

ARCHIVE_URL="${ARCHIVE_URL:-https://singularity.virusseq-dataportal.ca/download/archive/all}"
DEST_DIR_DEFAULT="data/virusseq_archive"

usage() {
  cat <<'EOF'
Usage:
  download_virusseq_archive.sh [destination_dir]

Defaults:
  destination_dir          data/virusseq_archive

Behavior:
  - Downloads the archive using the server-provided filename (typically includes a date;
    curl -OJ / wget --content-disposition). The tarball is temporary.
  - Extracts into destination_dir
  - Requires exactly one .fasta and one .tsv after extraction
  - Writes compressed outputs in destination_dir:
      virusseq_<DATE>.sequences.fasta.xz
      virusseq_<DATE>.metadata.csv.gz
    <DATE> is parsed from the downloaded tarball basename (including names like
    virusseq-data-release-YYYY-MM-DDTHH:MM:SSZ.tar.gz); only YYYYMMDD is used.
    if none is found, today’s date (YYYYMMDD) is used and a warning is printed.
  - Removes the uncompressed fasta/tsv and deletes the downloaded .tar.gz

Environment variables (optional):
  ARCHIVE_URL              Default:
                           https://singularity.virusseq-dataportal.ca/download/archive/all

Examples:
  ./scripts/download_virusseq_archive.sh
  ./scripts/download_virusseq_archive.sh data/virusseq
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

DEST_DIR="${1:-${DEST_DIR_DEFAULT}}"
mkdir -p "${DEST_DIR}"

download_archive() {
  if command -v curl >/dev/null 2>&1; then
    ( cd "${DEST_DIR}" && curl -fL -OJ --retry 3 --retry-delay 2 "${ARCHIVE_URL}" )
  elif command -v wget >/dev/null 2>&1; then
    wget --content-disposition -P "${DEST_DIR}" "${ARCHIVE_URL}"
  else
    echo "Error: neither curl nor wget is installed." >&2
    exit 1
  fi
}

echo "Downloading archive from:"
echo "  ${ARCHIVE_URL}"
echo "Saving under ${DEST_DIR} with server-provided filename."

download_archive

# Newest .tar.gz in DEST_DIR (handles Content-Disposition name with date).
mapfile -t TAR_GZS < <(find "${DEST_DIR}" -maxdepth 1 -type f -name '*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2-)
if [[ "${#TAR_GZS[@]}" -eq 0 || -z "${TAR_GZS[0]:-}" ]]; then
  echo "Error: no .tar.gz found in ${DEST_DIR} after download." >&2
  exit 1
fi
ARCHIVE_PATH="${TAR_GZS[0]}"
echo "Using archive: ${ARCHIVE_PATH}"

 ARCHIVE_BASENAME="${ARCHIVE_PATH##*/}"
 DATE=""
if [[ "${ARCHIVE_BASENAME}" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
  DATE="${BASH_REMATCH[1]//-/}"
elif [[ "${ARCHIVE_BASENAME}" =~ ([0-9]{8}) ]]; then
  DATE="${BASH_REMATCH[1]}"
else
  DATE="$(date +%Y%m%d)"
  echo "Warning: could not parse a date from filename '${ARCHIVE_BASENAME}'; using ${DATE}" >&2
fi
echo "Resolved release date from archive filename: ${DATE}"

echo "Extracting archive into:"
echo "  ${DEST_DIR}"
tar -xzf "${ARCHIVE_PATH}" -C "${DEST_DIR}"

shopt -s globstar nullglob nocaseglob

FASTA_CANDIDATES=( "${DEST_DIR}"/**/*.fasta )
TSV_CANDIDATES=( "${DEST_DIR}"/**/*.tsv )

FASTA_FILES=()
for f in "${FASTA_CANDIDATES[@]}"; do
  [[ "$(basename "$f")" == "latest_sequences.fasta" ]] && continue
  FASTA_FILES+=( "$f" )
done

TSV_FILES=()
for f in "${TSV_CANDIDATES[@]}"; do
  [[ "$(basename "$f")" == "latest_metadata.tsv" ]] && continue
  TSV_FILES+=( "$f" )
done

if [[ "${#FASTA_FILES[@]}" -ne 1 ]]; then
  echo "Error: expected exactly 1 .fasta file after extraction, found ${#FASTA_FILES[@]}." >&2
  if [[ "${#FASTA_FILES[@]}" -gt 0 ]]; then
    printf 'Matched .fasta files:\n' >&2
    printf '  %s\n' "${FASTA_FILES[@]}" >&2
  fi
  exit 1
fi

if [[ "${#TSV_FILES[@]}" -ne 1 ]]; then
  echo "Error: expected exactly 1 .tsv file after extraction, found ${#TSV_FILES[@]}." >&2
  if [[ "${#TSV_FILES[@]}" -gt 0 ]]; then
    printf 'Matched .tsv files:\n' >&2
    printf '  %s\n' "${TSV_FILES[@]}" >&2
  fi
  exit 1
fi

FASTA_FILE="${FASTA_FILES[0]}"
METADATA_TSV_FILE="${TSV_FILES[0]}"

OUT_FASTA="${DEST_DIR}/virusseq_${DATE}.sequences.fasta"
OUT_METADATA="${DEST_DIR}/virusseq_${DATE}.metadata.tsv"

mv "${FASTA_FILE}" "${OUT_FASTA}"
mv "${METADATA_TSV_FILE}" "${OUT_METADATA}"

rm -f "${DEST_DIR}/latest_sequences.fasta" "${DEST_DIR}/latest_metadata.tsv"
ln -s "$(readlink -f "${OUT_FASTA}")" "${DEST_DIR}/latest_sequences.fasta"
ln -s "$(readlink -f "${OUT_METADATA}")" "${DEST_DIR}/latest_metadata.tsv"

rm -f "${ARCHIVE_PATH}"

shopt -u globstar nullglob nocaseglob

echo "Done."
echo "Extracted to: ${DEST_DIR}"
echo "Sequences: ${OUT_FASTA}"
echo "Metadata:  ${OUT_METADATA}"
echo "Removed downloaded archive: ${ARCHIVE_PATH}"
