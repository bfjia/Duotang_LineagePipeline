# Duotang Lineage Pipeline

Pipeline for assigning **SARS-CoV-2 lineages** with [Pangolin](https://github.com/cov-lineages/pangolin) in **UShER mode** (`--analysis-mode accurate`), then optionally merging those assignments into **VirusSeq-style metadata**. It can run on a local Conda environment or in Docker.

## What it does

1. **Input sequences** — You supply an **uncompressed** multi-FASTA, or omit input to download the latest **VirusSeq Data Portal** full archive (sequences + metadata TSV).
2. **Lineage calling** — Runs `pangolin` and writes a per-run directory under your output root, plus a curated CSV aligned to FASTA header order.
3. **Metadata enrichment** — If a metadata file is available (your path or the one from the archive download), the workflow fills lineage-related columns from the pangolin results and records software/data versions from `pangolin --all-versions`.

Supporting scripts download optional **CanCOGeN metadata from GCS** and **compare** lineage columns between a metadata TSV and a lineage CSV for QA.

## Repository layout

| Path | Role |
|------|------|
| `run_pangolin_workflow.sh` | Main workflow (Conda or Docker entrypoint) |
| `environment.yml` | Conda env definition (`python=3.11`, `pangolin`) |
| `Dockerfile` | Image with Miniforge + env + workflow |
| `scripts/build_lineage_csv.py` | Builds `lineage_assignments.csv` from FASTA + raw pangolin CSV |
| `scripts/enrich_virusseq_metadata.py` | Joins lineage CSV into metadata (TSV or `.gz`) |
| `scripts/download_virusseq_archive.sh` | Downloads and extracts VirusSeq “archive/all” tarball |
| `scripts/download_gcs_metadata.sh` | Syncs `gs://dnastack-covid-19-data/CanCOGeN/metadata/` (or overrides) |
| `scripts/compare_lineage_tsv_csv.py` | Writes match/mismatch/missing reports under `comparisons/` |
| `test/` | Small FASTA + metadata and **reference outputs** for CI |

## Prerequisites

- **Local runs:** [Conda](https://docs.conda.io/) (Miniconda/Miniforge) on `PATH`.
- **Docker runs:** Docker only (image creates the Conda env for you).
- **Optional:** `gsutil` + `gcloud auth login` for `download_gcs_metadata.sh`.
- **Optional:** `curl` or `wget` for `download_virusseq_archive.sh` (also installed in the Docker image).

## Conda environment

Create the environment **before** the first local run (the workflow exits if the env name does not exist):

```bash
conda env create -f environment.yml -n Duotang_LineagePipeline
```

If the env exists but `pangolin` is missing, `run_pangolin_workflow.sh` will try to install it with `conda install -n Duotang_LineagePipeline -c conda-forge -c bioconda pangolin`.

## Running the workflow (local)

From the repository root:

```bash
chmod +x run_pangolin_workflow.sh
./run_pangolin_workflow.sh --help
```

### Options

| Flag | Description |
|------|-------------|
| `-i`, `--input-fasta` | Uncompressed FASTA. If omitted, the script runs `scripts/download_virusseq_archive.sh` and uses `latest_sequences.fasta` / `latest_metadata.tsv` under the download directory. |
| `-m`, `--metadata-input` | Metadata file for enrichment (TSV/CSV; gzip supported where the enricher opens text). With auto-download, this defaults to the downloaded TSV. |
| `-d`, `--download-dest-dir` | Where to download/extract the VirusSeq archive (default: `data/virusseq_archive`). |
| `-e`, `--env-name` | Conda environment name (default: `Duotang_LineagePipeline`). |
| `-o`, `--output-root` | All run outputs (default: `output`). |
| `-t`, `--threads` | Pangolin thread count (default: `1`). |

**Compressed FASTA (`.xz` / `.gz`) is not supported** — decompress first.

### Examples

```bash
# Your FASTA + metadata; 8 threads
./run_pangolin_workflow.sh -i path/to/sequences.fasta -m path/to/metadata.tsv -t 8

# Custom output directory
./run_pangolin_workflow.sh -i sequences.fasta -m metadata.tsv -o results/run1

# Download latest VirusSeq archive, run pangolin, enrich with downloaded metadata
./run_pangolin_workflow.sh -o output -d data/virusseq_archive
```

## Outputs

Each run creates a timestamped directory: `<output-root>/run_YYYYMMDD_HHMMSS/`.

| Artifact | Description |
|----------|-------------|
| `input.fasta` | Symlink to the FASTA used for this run |
| `lineage_report.raw.csv` | Pangolin’s native CSV |
| `lineage_assignments.csv` | Curated CSV: FASTA order, columns from `scripts/build_lineage_csv.py` |
| `virusseq.metadata.enriched.tsv` | Present when metadata enrichment runs: metadata rows with lineage fields filled |

Convenience symlinks under `<output-root>/`:

- `latest_lineage_assignments.csv` → latest run’s `lineage_assignments.csv`
- `latest_virusseq_metadata.tsv` → latest run’s enriched metadata (when enrichment ran)

Curated lineage columns include `fasta_header`, `lineage`, and pangolin context fields (`status`, `note`, `conflict`, `ambiguity_score`, scorpio fields, version fields). Details are in `scripts/build_lineage_csv.py`.

## Docker

Build and run (mount a host directory on `/output` to keep results):

```bash
docker build -t duotang-lineage .
docker run --rm -v "$PWD/output:/output" \
  -v /path/to/seq.fasta:/data/seq.fasta:ro \
  -v /path/to/meta.tsv:/data/meta.tsv:ro \
  duotang-lineage \
  -i /data/seq.fasta -m /data/meta.tsv -t 8 -o /output
```

The image **ENTRYPOINT** already passes `-e Duotang_LineagePipeline`. Default **CMD** is `-o /output`; if you override arguments after the image name, include `-o /output` again when you want container output under `/output`.

Download mode inside the container (persist cache on the host):

```bash
docker run --rm -v "$PWD/output:/output" -v "$PWD/data:/workflow/data" \
  duotang-lineage -o /output -d data/virusseq_archive
```

## Continuous integration

On pushes and pull requests to `main`, [`.github/workflows/docker-test.yml`](.github/workflows/docker-test.yml) builds the image, runs the workflow on `test/test.fasta` and `test/metadata.csv`, and `diff`s the run directory against pinned files in `test/output/`. If Pangolin’s outputs change legitimately, refresh the references by copying from the new `run_*` directory into `test/output/` as described in the workflow comments.

## Optional utilities

### CanCOGeN metadata from Google Cloud Storage

```bash
./scripts/download_gcs_metadata.sh
./scripts/download_gcs_metadata.sh data/metadata_snapshot
```

Requires `gsutil` and authentication. Defaults: bucket `dnastack-covid-19-data`, prefix `CanCOGeN/metadata/`. Override with `GS_BUCKET_NAME` and `GS_FOLDER`.

### Compare lineage in metadata TSV vs assignments CSV

```bash
conda run -n Duotang_LineagePipeline python scripts/compare_lineage_tsv_csv.py \
  metadata.tsv lineage_assignments.csv --output-dir comparisons
```

Writes `lineage_matches.csv`, `lineage_mismatches.csv`, and `lineage_missing_between_files.csv`.

## References

- Pangolin usage: [cov-lineages.org — Pangolin usage](https://cov-lineages.org/resources/pangolin/usage.html)
- VirusSeq archive endpoint (overridable via `ARCHIVE_URL` in `download_virusseq_archive.sh`): `https://singularity.virusseq-dataportal.ca/download/archive/all`
