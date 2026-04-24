#!/usr/bin/env bash
set -euo pipefail

ENV_NAME_DEFAULT="Duotang_LineagePipeline"
OUTPUT_ROOT_DEFAULT="output"
THREADS_DEFAULT="1"
METADATA_INPUT_DEFAULT=""
DOWNLOAD_DEST_DIR_DEFAULT="data/virusseq_archive"

ENV_NAME="${ENV_NAME_DEFAULT}"
OUTPUT_ROOT="${OUTPUT_ROOT_DEFAULT}"
THREADS="${THREADS_DEFAULT}"
METADATA_INPUT="${METADATA_INPUT_DEFAULT}"
DOWNLOAD_DEST_DIR="${DOWNLOAD_DEST_DIR_DEFAULT}"
INPUT_FASTA=""

usage() {
  cat <<'EOF'
Usage:
  run_pangolin_workflow.sh [--input-fasta <input_fasta>] [options]

Options:
  -i, --input-fasta <input_fasta>    Uncompressed FASTA text file.
                                     If omitted, script downloads VirusSeq archive
                                     and auto-detects FASTA/TSV outputs.
  -m, --metadata-input <metadata_tsv>
                                     VirusSeq metadata TSV input for enrichment.
                                     If omitted and auto-download is used, the TSV
                                     from download output is used automatically.
  -d, --download-dest-dir <dir>      Destination dir for archive download
                                     (default: data/virusseq_archive)
  -e, --env-name <conda_env>         Conda env name (default: Duotang_LineagePipeline)
  -o, --output-root <output_dir>     Output root dir (default: output)
  -t, --threads <num_threads>        Pangolin threads (default: 1)
  -h, --help                         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input-fasta)
      INPUT_FASTA="$2"
      shift 2
      ;;
    -e|--env-name)
      ENV_NAME="$2"
      shift 2
      ;;
    -o|--output-root)
      OUTPUT_ROOT="$2"
      shift 2
      ;;
    -t|--threads)
      THREADS="$2"
      shift 2
      ;;
    -m|--metadata-input)
      METADATA_INPUT="$2"
      shift 2
      ;;
    -d|--download-dest-dir)
      DOWNLOAD_DEST_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      echo "Error: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

#check if conda is available
if ! command -v conda >/dev/null 2>&1; then
  echo "Error: conda is not available in PATH." >&2
  exit 1
fi

mkdir -p "${OUTPUT_ROOT}"

#check if the output directory exists
if [[ ! -d "${OUTPUT_ROOT}" ]]; then
  echo "Error: output directory does not exist: ${OUTPUT_ROOT}" >&2
  exit 1
fi

#check if the conda environment exists
if ! conda env list | awk -v env="${ENV_NAME}" '$1==env {found=1} END {exit(found?0:1)}'; then
  echo "Error: conda environment not found: ${ENV_NAME}" >&2
  echo "Please create it first, then rerun this workflow." >&2
  exit 1
fi

#check if pangolin is available in the conda environment, if not install it.
if ! conda run -n "${ENV_NAME}" pangolin --version >/dev/null 2>&1; then
  echo "pangolin not found in ${ENV_NAME}; installing with conda."
  conda install -n "${ENV_NAME}" -y -c conda-forge -c bioconda pangolin
fi

RUN_ID="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="${OUTPUT_ROOT}/run_${RUN_ID}"
LATEST_DIR="latest"
mkdir -p "${RUN_DIR}"

WORK_FASTA="${RUN_DIR}/input.fasta"
RAW_REPORT="${RUN_DIR}/lineage_report.raw.csv"
FINAL_REPORT="${RUN_DIR}/lineage_assignments.csv"
LATEST_REPORT="${OUTPUT_ROOT}/latest_lineage_assignments.csv"
CSV_BUILDER="scripts/build_lineage_csv.py"
ENRICH_METADATA="scripts/enrich_virusseq_metadata.py"
DOWNLOAD_SCRIPT="./scripts/download_virusseq_archive.sh"


if [[ ! -f "${CSV_BUILDER}" ]]; then
  echo "Error: CSV builder script not found: ${CSV_BUILDER}" >&2
  exit 1
fi

if [[ ! -f "${ENRICH_METADATA}" ]]; then
  echo "Error: metadata enrichment script not found: ${ENRICH_METADATA}" >&2
  exit 1
fi

if [[ -z "${INPUT_FASTA}" ]]; then
  if [[ ! -f "${DOWNLOAD_SCRIPT}" ]]; then
    echo "Error: download script not found: ${DOWNLOAD_SCRIPT}" >&2
    exit 1
  fi
  echo "No input FASTA specified. Downloading VirusSeq archive..."
  if ! bash "${DOWNLOAD_SCRIPT}" "${DOWNLOAD_DEST_DIR}"; then
    echo "Error: downloader exited non-zero." >&2
    exit 1
  fi

  AUTO_FASTA=""
  AUTO_METADATA=""
  if [[ -f "${DOWNLOAD_DEST_DIR}/latest_sequences.fasta" ]]; then
    AUTO_FASTA="${DOWNLOAD_DEST_DIR}/latest_sequences.fasta"
  fi

  if [[ -f "${DOWNLOAD_DEST_DIR}/latest_metadata.tsv" ]]; then
    AUTO_METADATA="${DOWNLOAD_DEST_DIR}/latest_metadata.tsv"
  fi

  if [[ -z "${AUTO_FASTA}" || ! -f "${AUTO_FASTA}" ]]; then
    echo "Error: required symlink not found: ${DOWNLOAD_DEST_DIR}/latest_sequences.fasta" >&2
    exit 1
  fi

  if [[ -z "${AUTO_METADATA}" || ! -f "${AUTO_METADATA}" ]]; then
    echo "Error: required symlink not found: ${DOWNLOAD_DEST_DIR}/latest_metadata.tsv" >&2
    exit 1
  fi
  INPUT_FASTA="${AUTO_FASTA}"

  if [[ -z "${METADATA_INPUT}" && -n "${AUTO_METADATA}" && -f "${AUTO_METADATA}" ]]; then
    METADATA_INPUT="${AUTO_METADATA}"
  fi
fi

if [[ ! -f "${INPUT_FASTA}" ]]; then
  echo "Error: input FASTA not found: ${INPUT_FASTA}" >&2
  exit 1
fi

case "${INPUT_FASTA}" in
  *.xz|*.gz)
    echo "Error: compressed FASTA is not supported. Please provide uncompressed .fasta input." >&2
    exit 1
    ;;
esac

echo "Preparing FASTA input symlink: ${WORK_FASTA} -> ${INPUT_FASTA}"
rm -f "${WORK_FASTA}"
ln -s "$(readlink -f "${INPUT_FASTA}")" "${WORK_FASTA}"

echo "Running pangolin in UShER (accurate) mode"
PANGOLIN_START_TS="$(date +%s)"
conda run -n "${ENV_NAME}" pangolin \
  "${WORK_FASTA}" \
  --analysis-mode accurate \
  --outfile "$(basename "${RAW_REPORT}")" \
  --outdir "${RUN_DIR}" \
  --threads "${THREADS}"
PANGOLIN_END_TS="$(date +%s)"
PANGOLIN_RUNTIME_SEC="$((PANGOLIN_END_TS - PANGOLIN_START_TS))"

format_duration() {
  local total_seconds="$1"
  local hours="$((total_seconds / 3600))"
  local minutes="$(((total_seconds % 3600) / 60))"
  local seconds="$((total_seconds % 60))"
  printf "%02dh:%02dm:%02ds" "${hours}" "${minutes}" "${seconds}"
}

echo "Building final CSV: ${FINAL_REPORT}"
conda run -n "${ENV_NAME}" python "${CSV_BUILDER}" \
  "${WORK_FASTA}" "${RAW_REPORT}" "${FINAL_REPORT}"

echo "Linking latest lineage report: ${LATEST_REPORT} -> ${FINAL_REPORT}"
rm -f "${LATEST_REPORT}"
ln -s "$(readlink -f "${FINAL_REPORT}")" "${LATEST_REPORT}"

if ! command -v xz >/dev/null 2>&1; then
  echo "Error: xz is not available in PATH (required for ${LATEST_DIR}/ archives)." >&2
  exit 1
fi
mkdir -p "${LATEST_DIR}"
XZ_LATEST_REPORT="${LATEST_DIR}/lineage_assignments.csv.xz"
echo "Writing XZ archive: ${XZ_LATEST_REPORT}"
rm -f "${XZ_LATEST_REPORT}"
xz -c -T0 "${FINAL_REPORT}" >"${XZ_LATEST_REPORT}"


# Here we merge the lineage assignments with the metadata
if [[ -n "${METADATA_INPUT}" && -f "${METADATA_INPUT}" ]]; then
  echo "Enriching VirusSeq metadata: ${METADATA_INPUT}"
  ALL_VERSIONS="$(conda run -n "${ENV_NAME}" pangolin --all-versions 2>/dev/null || true)"
  PANGOLIN_SOFTWARE_VERSION="$(printf '%s\n' "${ALL_VERSIONS}" | sed -n 's/^pangolin: *//p' | head -n1)"
  PANGOLIN_DATA_VERSION="$(printf '%s\n' "${ALL_VERSIONS}" | sed -n 's/^pangolin-data: *//p' | head -n1)"
  SCORPIO_SOFTWARE_VERSION="$(printf '%s\n' "${ALL_VERSIONS}" | sed -n 's/^scorpio: *//p' | head -n1)"
  if [[ -z "${PANGOLIN_SOFTWARE_VERSION}" || -z "${PANGOLIN_DATA_VERSION}" || -z "${SCORPIO_SOFTWARE_VERSION}" ]]; then
    echo "Warning: could not parse pangolin --all-versions; skipping metadata enrichment." >&2
    echo "Raw output was:" >&2
    printf '%s\n' "${ALL_VERSIONS}" >&2
  else
    ENRICHED_METADATA="${RUN_DIR}/virusseq.metadata.enriched.tsv"
    LATEST_ENRICHED="${OUTPUT_ROOT}/latest_virusseq_metadata.tsv"
    conda run -n "${ENV_NAME}" python "${ENRICH_METADATA}" \
      "${METADATA_INPUT}" \
      "${LATEST_REPORT}" \
      "${ENRICHED_METADATA}" \
      --pangolin-version "${PANGOLIN_SOFTWARE_VERSION}" \
      --pangolin-data-version "${PANGOLIN_DATA_VERSION}" \
      --scorpio-version "${SCORPIO_SOFTWARE_VERSION}"
    echo "Linking latest enriched metadata: ${LATEST_ENRICHED} -> ${ENRICHED_METADATA}"
    ln -sfn "$(readlink -f "${ENRICHED_METADATA}")" "${LATEST_ENRICHED}"
    XZ_LATEST_ENRICHED="${LATEST_DIR}/virusseq_metadata.tsv.xz"
    echo "Writing XZ archive: ${XZ_LATEST_ENRICHED}"
    rm -f "${XZ_LATEST_ENRICHED}"
    xz -c -T0 "${ENRICHED_METADATA}" >"${XZ_LATEST_ENRICHED}"
    echo "Enriched metadata: ${ENRICHED_METADATA}"
    echo "Latest enriched copy: ${LATEST_ENRICHED}"
  fi
else
  if [[ -z "${METADATA_INPUT}" ]]; then
    echo "Skipping VirusSeq metadata enrichment (no metadata input provided)."
  else
    echo "Skipping VirusSeq metadata enrichment (file not found: ${METADATA_INPUT})."
  fi
fi

echo
echo "Workflow complete."
echo "Raw pangolin report: ${RAW_REPORT}"
echo "Final merged report: ${FINAL_REPORT}"
echo "Latest report copy:  ${LATEST_REPORT}"
echo "Latest report (xz):  ${LATEST_DIR}/lineage_assignments.csv.xz"
echo "Pangolin runtime:    $(format_duration "${PANGOLIN_RUNTIME_SEC}") (${PANGOLIN_RUNTIME_SEC} seconds)"
