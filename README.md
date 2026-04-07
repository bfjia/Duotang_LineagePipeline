# SARS-CoV-2 Lineage Workflow (Pangolin UShER Mode)

This repository contains a workflow to assign SARS-CoV-2 lineages from an `.xz` compressed multi-FASTA file taken from VirusSeq Data Portal using `pangolin` in UShER (`accurate`) mode, using a conda environment.

## Input

- Required input argument: `<input_xz_fasta>`
- Example input: `data/100SeqTest.fasta.xz`

## Output

Each run creates a timestamped directory:

- `results/pangolin/run_YYYYMMDD_HHMMSS/lineage_report.raw.csv` (native pangolin output)
- `results/pangolin/run_YYYYMMDD_HHMMSS/lineage_assignments.csv` (final curated output)
- `results/pangolin/latest_lineage_assignments.csv` (copy of the latest curated output)

The curated output includes:

1. `fasta_header` (column 1)
2. `lineage` (column 2)
3. Additional context columns from pangolin where available:
   - `status`, `note`, `conflict`, `ambiguity_score`
   - `scorpio_call`, `scorpio_support`, `scorpio_conflict`
   - `version`, `pangolin_version`, `pangoLEARN_version`, `pango_version`

## Prerequisites

- Conda (Miniconda/Anaconda) installed and available in `PATH`

## Environment

- Default conda env name: `Duotang_LineagePipeline`, can specify environment to use via `-e My_Environment_Name`
- The workflow checks first this env exists.
- The workflow then checks if `pangolin` exists in the env, the workflow will installs it into this env automatically via conda if it does not.

## Run

From repository root:

```bash
chmod +x run_pangolin_workflow.sh
./run_pangolin_workflow.sh <input_xz_fasta>
```


Optional arguments (with defaults):
```bash
./run_pangolin_workflow.sh <input_xz_fasta> \
  --env-name Duotang_LineagePipeline \
  --output-root results/pangolin \
  --threads 4
```

Example:

```bash
./run_pangolin_workflow.sh data/100SeqTest.fasta.xz
./run_pangolin_workflow.sh data/100SeqTest.fasta.xz --threads 8
./run_pangolin_workflow.sh data/100SeqTest.fasta.xz --output-root results/custom --env-name Duotang_LineagePipeline
```

If you need to create the environment first:

```bash
conda create -c conda-forge -c bioconda -c nodefaults -n Duotang_LineagePipeline -y pangolin
```

## Notes

- The script explicitly uses `--analysis-mode accurate` to force UShER mode.
- FASTA headers are parsed from the decompressed input and used as column 1 in the final CSV.
- If a header is missing in pangolin output, lineage-related fields are left blank for that row.
- CSV post-processing logic is in `scripts/build_lineage_csv.py`.

## Pangolin Reference

- Pangolin usage docs: [cov-lineages.org pangolin usage](https://cov-lineages.org/resources/pangolin/usage.html)

## Download CanCOGeN Metadata from GCS

You can download files from:

- Bucket: `dnastack-covid-19-data`
- Folder: `CanCOGeN/metadata/`

Using:

```bash
./scripts/download_gcs_metadata.sh
```

Optional destination directory:

```bash
./scripts/download_gcs_metadata.sh data/metadata_snapshot
```

Requirements:

- `gsutil` installed (Google Cloud SDK)
- Authenticated session (for example: `gcloud auth login`)
