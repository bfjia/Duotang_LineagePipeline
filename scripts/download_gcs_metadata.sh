#!/usr/bin/env bash
set -euo pipefail

GS_BUCKET_NAME="${GS_BUCKET_NAME:-dnastack-covid-19-data}"
GS_FOLDER="${GS_FOLDER:-CanCOGeN/metadata/}"
DEST_DIR="${1:-data/viralai}"

usage() {
  cat <<'EOF'
Usage:
  download_gcs_metadata.sh [local_destination_dir]

Environment variables (optional):
  GS_BUCKET_NAME   Default: dnastack-covid-19-data
  GS_FOLDER        Default: CanCOGeN/metadata/

Examples:
  ./scripts/download_gcs_metadata.sh
  ./scripts/download_gcs_metadata.sh data/metadata_snapshot
  GS_BUCKET_NAME=my-bucket GS_FOLDER=path/to/folder/ ./scripts/download_gcs_metadata.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v gsutil >/dev/null 2>&1; then
  echo "Error: gsutil is not installed or not in PATH." >&2
  echo "Install Google Cloud SDK and run: gcloud auth login" >&2
  exit 1
fi

if [[ -z "${GS_BUCKET_NAME}" || -z "${GS_FOLDER}" ]]; then
  echo "Error: GS_BUCKET_NAME and GS_FOLDER must not be empty." >&2
  exit 1
fi

# Normalize folder prefix to avoid malformed URLs.
GS_FOLDER="${GS_FOLDER#/}"
if [[ "${GS_FOLDER}" != */ ]]; then
  GS_FOLDER="${GS_FOLDER}/"
fi

SRC_URI="gs://${GS_BUCKET_NAME}/${GS_FOLDER}"

echo "Checking source: ${SRC_URI}"
if ! gsutil ls "${SRC_URI}" >/dev/null 2>&1; then
  echo "Error: Cannot access ${SRC_URI}" >&2
  echo "Verify bucket/path and authentication (gcloud auth login)." >&2
  exit 1
fi

mkdir -p "${DEST_DIR}"
echo "Downloading from ${SRC_URI} to ${DEST_DIR}"
gsutil -m cp -r "${SRC_URI}*" "${DEST_DIR}/"

echo "Download complete."
