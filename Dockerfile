# Pangolin lineage workflow (run_pangolin_workflow.sh).
# Build: docker build -t duotang-lineage .
#
# ENTRYPOINT already passes: -e Duotang_LineagePipeline (conda env inside the image).
# Default CMD is: -o /output — mount a host dir at /output to keep results.
# Any args you pass after the image name replace CMD entirely; include -o /output again if you need it.
#
# Workflow flags (see run_pangolin_workflow.sh --help):
#   -i, --input-fasta PATH     Uncompressed FASTA. Omit to download VirusSeq archive into -d.
#   -m, --metadata-input PATH  Metadata TSV for enrichment; auto-filled when using download mode.
#   -d, --download-dest-dir    Download/extract dir (default: data/virusseq_archive under WORKDIR).
#   -e, --env-name NAME        Conda env (default Duotang_LineagePipeline); fixed by ENTRYPOINT here.
#   -o, --output-root PATH     All run outputs (default in container: /output via CMD).
#   -t, --threads N            Pangolin threads (default 1).
#   -h, --help                 Print script usage.
#
# Examples:
#   Most relevant — typical local run: -i (FASTA), -m (metadata TSV), -t (pangolin threads); use -o for outputs:
#     docker run --rm -v "$PWD/output:/output" \
#       -v /path/to/seq.fasta:/data/seq.fasta:ro -v /path/to/meta.tsv:/data/meta.tsv:ro \
#       duotang-lineage -i /data/seq.fasta -m /data/meta.tsv -t 8 -o /output
#   Download VirusSeq, pangolin, enrich (default threads):
#     docker run --rm -v "$PWD/output:/output" [-v "$PWD/data:/workflow/data"] duotang-lineage
#   Persist download cache on host (uses -d relative to /workflow):
#     docker run --rm -v "$PWD/output:/output" -v "$PWD/data:/workflow/data" \
#       duotang-lineage -o /output -d data/virusseq_archive
#   Help:
#     docker run --rm duotang-lineage -h

FROM condaforge/miniforge3:26.1.1-3

WORKDIR /workflow

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    findutils \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

COPY environment.yml /workflow/environment.yml
RUN conda env create -f /workflow/environment.yml -n Duotang_LineagePipeline && \
    conda clean -afy

COPY scripts/ /workflow/scripts/
COPY run_pangolin_workflow.sh /workflow/run_pangolin_workflow.sh
RUN chmod +x /workflow/run_pangolin_workflow.sh /workflow/scripts/*.sh

ENV PATH="/opt/conda/bin:/opt/conda/envs/Duotang_LineagePipeline/bin:${PATH}"

ENTRYPOINT ["/workflow/run_pangolin_workflow.sh", "-e", "Duotang_LineagePipeline"]
CMD ["-o", "/output"]
