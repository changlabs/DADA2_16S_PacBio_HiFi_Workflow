# DADA2 Workflow for PacBio HiFi Full-Length 16S rRNA Amplicon Sequencing

[![R Version](https://img.shields.io/badge/R-%3E%3D4.1-blue)](https://www.r-project.org/) [![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE) [![DADA2](https://img.shields.io/badge/DADA2-Bioconductor-orange)](https://benjjneb.github.io/dada2/) [![PacBio HiFi](https://img.shields.io/badge/PacBio-HiFi-0099A8)](https://www.pacb.com/technology/hifi-sequencing/) [![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey)](#4-install-external-tools)

A reproducible R-based pipeline for processing **PacBio HiFi full-length 16S rRNA amplicon sequencing data** using the [DADA2](https://benjjneb.github.io/dada2/) algorithm. The pipeline is organized as executable R Markdown notebooks covering delivery validation, sample mapping, Q20 filtering, primer trimming and orientation, data-driven `maxEE` selection, ASV inference, taxonomy assignment, phylogenetic tree construction, 16S copy-number correction, microbial-load correction, and phyloseq object generation.

When more than one sequencing pool is present, Step 5 creates matching result bundles under `separate_pools/`. Steps 6–9 detect those folders automatically and apply the same analysis to the combined dataset and to each pool separately.

------------------------------------------------------------------------

## Table of Contents

- [Key Features](#key-features)
- [Pipeline Overview](#pipeline-overview)
- [Setup](#setup)
- [Running the Pipeline](#running-the-pipeline)
- [Pool-Specific Processing](#pool-specific-processing)
- [Column Dictionaries](#column-dictionaries)
- [Project Structure](#project-structure)
- [References](#references)
- [License](#license)
- [Acknowledgments](#acknowledgments)

------------------------------------------------------------------------

## Key Features

- **PacBio HiFi-aware quality control** — Calculates per-read length, GC content, and mean read quality directly in R and retains reads with **Q ≥ 20**.
- **Full-length read preservation** — No `truncLen` step is used; target-length, ambiguous-base, and expected-error filters are applied later in DADA2.
- **Data-driven maxEE selection** — A PacBio-specific Shiny app displays pooled and per-sample expected-error retention and validates the selected threshold with real DADA2 processing.
- **Demultiplexed delivery mapping** — Maps Lima barcode-pair filenames to stable sample identities through [data/sample_sheet.xlsx](data/sample_sheet.xlsx).
- **Primer orientation and trimming** — Uses [Cutadapt](https://cutadapt.readthedocs.io/) with linked F27–R1492 primers and reverse-complements reads when required.
- **PacBio DADA2 inference** — Uses the single-end PacBio HiFi workflow for filtering, error learning, denoising, chimera removal, ASV generation, and taxonomy assignment.
- **Pool-aware outputs** — Produces combined results and, when applicable, self-contained results for every pool under `separate_pools/`.
- **Dual taxonomy databases** — Supports [SILVA](https://www.arb-silva.de/), [GTDB](https://gtdb.ecogenomic.org/), or both.
- **16S copy-number correction** — Uses [PICRUSt2](https://github.com/picrust/picrust2/wiki) placement and hidden-state prediction.
- **Optional microbial-load correction** — Generates cell-count-scaled Quantitative Microbiome Profiles following [Vandeputte et al. (2017)](https://doi.org/10.1038/nature24460).
- **Multi-object phyloseq generation** — Builds one object per taxonomy database and available abundance source for the combined dataset and each pool.
- **Self-documenting outputs** — Excel workbooks end with a `Column_Dictionary` sheet, and notebook reports contain clickable links to referenced inputs and outputs.
- **Reproducible paths and checkpoints** — All notebooks use project-relative paths and preserve validated intermediate checkpoints where appropriate.

------------------------------------------------------------------------

## Pipeline Overview

```text
  PacBio HiFi FASTQ archives + sample sheet
                     │
                     ▼
        ┌──────────────────────────┐
        │ Step 1                   │
        │ Integrity + sample map   │
        └────────────┬─────────────┘
                     ▼
        ┌──────────────────────────┐
        │ Step 2                   │
        │ Read QC + Q ≥ 20 filter  │
        └────────────┬─────────────┘
                     ▼
        ┌──────────────────────────┐
        │ Step 3                   │
        │ Trim + orient primers    │
        └────────────┬─────────────┘
                     ▼
        ┌──────────────────────────┐
        │ Step 4                   │
        │ Select + validate maxEE  │
        └────────────┬─────────────┘
                     ▼
        ┌──────────────────────────┐
        │ Step 5                   │
        │ PacBio DADA2 + taxonomy  │
        └────────────┬─────────────┘
                     │
          ┌──────────┴───────────┐
          ▼                      ▼
 ┌──────────────────┐   ┌──────────────────┐
 │ Step 6 optional  │   │ Step 7 optional  │
 │ Phylogenetic tree│   │ Copy-number corr.│
 └────────┬─────────┘   └────────┬─────────┘
          │                      ▼
          │             ┌──────────────────┐
          │             │ Step 8 optional  │
          │             │ Microbial load   │
          │             └────────┬─────────┘
          └──────────┬───────────┘
                     ▼
        ┌──────────────────────────┐
        │ Step 9 optional          │
        │ Phyloseq object assembly │
        └────────────┬─────────────┘
                     ▼
             Analysis-ready data
```

Steps 6 and 7 are independent branches from Step 5. Step 8 requires Step 7 because microbial-load correction is applied to copy-number-corrected abundances. Step 9 automatically detects the available raw, copy-number-corrected, and microbial-load-corrected inputs and builds every valid taxonomy-database × abundance-source combination.

------------------------------------------------------------------------

## Setup

### 1. Clone the Repository

Download the repository ZIP from GitHub or clone it from the terminal:

```bash
git clone https://github.com/changlabs/DADA2_16S_PacBio_HiFi_Workflow.git
```

### 2. Open the R Project in RStudio

Open [DADA2_16S_PacBio_HiFi_Workflow.Rproj](DADA2_16S_PacBio_HiFi_Workflow.Rproj) in [RStudio](https://posit.co/products/open-source/rstudio/). All notebook paths use `here::here()` and resolve relative to this project root.

### 3. Install R Dependencies

Open [setup/install_R_dependencies.R](setup/install_R_dependencies.R) and run it with **Source**. It installs the CRAN and [Bioconductor](https://bioconductor.org/) packages used across the workflow, including DADA2, DECIPHER, phyloseq, Biostrings, ShortRead, ape, data.table, openxlsx, DT, and the reporting packages.

### 4. Install External Tools

The project-local installer requires Python 3.9 or newer and a C compiler (`gcc`, `cc`, or `clang`). Run:

```bash
Rscript setup/install_required_tools.R
```

This installs:

| Tool | Location | Purpose |
|:--|:--|:--|
| [Cutadapt](https://cutadapt.readthedocs.io/) | `tools/cutadapt/venv/` | Primer trimming and read orientation |
| [FastTree](https://morgannprice.github.io/fasttree/) | `tools/fasttree/FastTree` | Phylogenetic tree construction |

FastTree is compiled for the current computer. The installer tries an OpenMP build first and falls back to a single-threaded build when OpenMP is unavailable, which is normal with Apple clang on macOS.

### 5. Install PICRUSt2 *(optional — for Step 7)*

Skip this installation if copy-number and microbial-load correction are not needed. The supplied installer creates a conda environment named `picrust2`:

```bash
bash setup/install_picrust2.sh
```

The supplied installation script targets Linux. Step 7 itself can also use an existing compatible `picrust2` conda environment on macOS. It checks multiple common conda installations and selects one that can successfully execute the environment.

### 6. Download Reference Databases

Run [setup/download_reference_databases.R](setup/download_reference_databases.R) to download DADA2-formatted SILVA and GTDB training sets into [tools/trainsets/](tools/trainsets/). Each database folder receives a download manifest recording its provenance and validation.

### 7. Add PacBio FASTQ Archives and the Sample Sheet

Place one `.fastq.zip` archive per supplied pool under a lowercase folder:

```text
data/fastq/pool1/<delivery>.fastq.zip
data/fastq/pool2/<delivery>.fastq.zip
```

Edit [data/sample_sheet.xlsx](data/sample_sheet.xlsx) so every active barcode pair maps to a unique `SampleID` and numeric `PoolNumber`. `SampleID` must not include the pool number. Step 1 extracts only mapped archive members and retains unmatched sample-sheet rows for review.

See [data/README.md](data/README.md) for the complete format and consistency checks.

### 8. Add Cell Counts and Metadata *(optional)*

- Replace the demonstration measurements in [data/cell_count/cell_count.tsv](data/cell_count/cell_count.tsv) before running Step 8.
- Replace the demonstration annotations in [data/metadata.tsv](data/metadata.tsv) before interpreting metadata-based Step 9 results.
- Keep `PoolNumber` as the first column and ensure `SampleID` matches the sample sheet exactly.

------------------------------------------------------------------------

## Running the Pipeline

Run the numbered notebooks in order from the project root. In RStudio, use **Knit** and select the HTML output to execute the analysis and create the full report/tutorial. The GitHub Markdown output is a non-executing, portable view intended for repository browsing. Read each notebook's prerequisites before starting, review its diagnostic tables and plots after completion, and follow the linked next-step guidance only after its final validation checks pass.

### Step 1 — [Data Integrity and Sample Mapping](R/notebooks/1_data_integrity_and_sample_mapping.md) *(required)*

Validates the supplied pool archives and FASTQ members, checks the sample sheet, maps Lima barcode pairs to biological sample identifiers, and extracts only matched reads to `results/1_data_integrity_and_sample_mapping/mapped_fastq/`.

### Step 2 — [Quality Filtering](R/notebooks/2_quality_filtering.md) *(required)*

Calculates per-sample PacBio read-quality, read-length, GC, and size statistics in R. Reads with mean **Q ≥ 20** are written uncompressed to `results/2_quality_filtered_reads/Q20_filtered_fastq/`. No read-length filter or `truncLen` is applied in this step.

### Step 3 — [Primer Trimming](R/notebooks/3_primer_trimming.md) *(required)*

Uses linked F27–R1492 primers with Cutadapt to retain full primer-to-primer amplicons, remove both primers, and orient every retained HiFi read consistently. Review the configured primer sequences before running a different assay.

### Step 4 — [DADA2 maxEE Parameter Selection](R/notebooks/4_dada2_parameter_selection.md) *(recommended)*

Launches the [PacBio maxEE Shiny app](R/shiny/dada2_parameter_selection_app.R), calculates expected errors for complete primer-trimmed reads, shows pooled and per-sample retention across candidate thresholds, and optionally validates the selected value with real DADA2 filtering, PacBio error learning, and sample inference. The exported workbook is loaded automatically by Step 5.

### Step 5 — [DADA2 Pipeline](R/notebooks/5_dada2_pipeline.md) *(required)*

Applies target-length, ambiguous-base, and expected-error filtering; learns the PacBio error model; infers ASVs; removes chimeras; and assigns taxonomy with the available SILVA and/or GTDB references. It exports CSV ASV/taxonomy tables, an Excel processing summary, plots, logs, and checkpoints.

If more than one pool is represented, Step 5 also creates self-contained pool-specific ASV sequence, count, taxonomy, and processing-summary files under [results/5_dada2_pipeline/separate_pools/](results/5_dada2_pipeline/separate_pools/).

### Step 6 — [Phylogenetic Tree](R/notebooks/6_phylogenetic_tree.md) *(optional)*

Aligns ASV sequences with DECIPHER and constructs maximum-likelihood trees with FastTree. Taxonomy-labelled Newick files and static tree PDFs are created for available databases.

### Step 7 — [16S Copy Number Correction](R/notebooks/7_copy_number_correction.md) *(optional)*

Uses PICRUSt2 `place_seqs.py` and `hsp.py` to predict ASV-level 16S rRNA gene copy number and produce a copy-number-corrected ASV abundance table. A compatible conda environment named `picrust2` is required.

### Step 8 — [Microbial Load Correction](R/notebooks/8_microbial_load_correction.md) *(optional)*

Requires Step 7 and positive cell-count measurements. It rarefies samples to a common sampling depth per cell and rescales by measured cell count to generate a Quantitative Microbiome Profile.

### Step 9 — [Phyloseq Object](R/notebooks/9_phyloseq_object.md) *(optional)*

Combines taxonomy, sample metadata, the optional tree, and every validated abundance source into analysis-ready phyloseq objects. Outputs are separated by taxonomy database and abundance source, with interactive genus-level composition plots and summary workbooks.

------------------------------------------------------------------------

## Pool-Specific Processing

Step 5 performs DADA2 inference globally so identical biological sequences retain the same `ASV_ID` across pools. It then subsets counts, representative sequences, taxonomy, and processing summaries into `separate_pools/pool<number>/`.

Steps 6–9 behave as follows:

1. Process the combined upstream output normally.
2. Check whether the required upstream `separate_pools` directory exists.
3. Discover valid pool folders automatically.
4. Rerun the same notebook calculations in a clean R session for each pool.
5. Write corresponding results to `results/<step_name>/separate_pools/<pool_name>/`.

If no `separate_pools` directory exists, only the combined dataset is processed.

------------------------------------------------------------------------

## Column Dictionaries

Every Excel workbook ends with a `Column_Dictionary` sheet documenting each exported column in plain language. It is generated with [R/functions/build_column_dictionary_function.R](R/functions/build_column_dictionary_function.R). If an exported column is added or renamed, update its description so the workbook remains self-documenting.

------------------------------------------------------------------------

## Project Structure

```text
DADA2_16S_PacBio_HiFi_Workflow/
├── DADA2_16S_PacBio_HiFi_Workflow.Rproj
├── README.md
├── pages/
│   └── index.html
├── .github/workflows/
│   └── pages.yml
├── setup/
│   ├── install_R_dependencies.R
│   ├── install_required_tools.R
│   ├── install_picrust2.sh
│   └── download_reference_databases.R
├── R/
│   ├── notebooks/
│   │   ├── 1_data_integrity_and_sample_mapping.Rmd
│   │   ├── 2_quality_filtering.Rmd
│   │   ├── 3_primer_trimming.Rmd
│   │   ├── 4_dada2_parameter_selection.Rmd
│   │   ├── 5_dada2_pipeline.Rmd
│   │   ├── 6_phylogenetic_tree.Rmd
│   │   ├── 7_copy_number_correction.Rmd
│   │   ├── 8_microbial_load_correction.Rmd
│   │   ├── 9_phyloseq_object.Rmd
│   │   ├── *.md
│   │   └── *.html
│   ├── shiny/
│   │   └── dada2_parameter_selection_app.R
│   └── functions/
│       ├── add_sheet_to_excel_function.R
│       ├── build_column_dictionary_function.R
│       ├── render_output_links_function.R
│       └── render_output_tree_function.R
├── data/
│   ├── README.md
│   ├── sample_sheet.xlsx
│   ├── metadata.tsv
│   ├── cell_count/cell_count.tsv
│   └── fastq/pool<number>/*.fastq.zip
├── results/
│   └── <step_name>/separate_pools/<pool_name>/
└── tools/
    ├── cutadapt/
    ├── fasttree/
    └── trainsets/{SILVA,GTDB}/
```

------------------------------------------------------------------------

## References

### Core Methods

- Callahan BJ, et al. (2016). DADA2: High-resolution sample inference from Illumina amplicon data. *Nature Methods* 13:581–583. [DOI:10.1038/nmeth.3869](https://doi.org/10.1038/nmeth.3869)
- Callahan BJ, et al. (2019). High-throughput amplicon sequencing of the full-length 16S rRNA gene with single-nucleotide resolution. *Nucleic Acids Research* 47:e103. [DOI:10.1093/nar/gkz569](https://doi.org/10.1093/nar/gkz569)
- [PacBio HiFi 16S workflow](https://github.com/PacificBiosciences/HiFi-16S-workflow)
- Price MN, et al. (2010). FastTree 2. *PLoS ONE* 5:e9490. [DOI:10.1371/journal.pone.0009490](https://doi.org/10.1371/journal.pone.0009490)
- McMurdie PJ, Holmes S (2013). phyloseq. *PLoS ONE* 8:e61217. [DOI:10.1371/journal.pone.0061217](https://doi.org/10.1371/journal.pone.0061217)

### Copy Number and Microbial Load Correction

- Douglas GM, et al. (2020). PICRUSt2 for prediction of metagenome functions. *Nature Biotechnology* 38:685–688. [DOI:10.1038/s41587-020-0548-6](https://doi.org/10.1038/s41587-020-0548-6)
- Vandeputte D, et al. (2017). Quantitative microbiome profiling links gut community variation to microbial load. *Nature* 551:507–511. [DOI:10.1038/nature24460](https://doi.org/10.1038/nature24460)
- [raeslab/QMP](https://github.com/raeslab/QMP)

### Taxonomy Databases

- Quast C, et al. (2013). The SILVA ribosomal RNA gene database project. *Nucleic Acids Research* 41:D590–D596.
- Parks DH, et al. (2022). GTDB: an ongoing census of bacterial and archaeal diversity. *Nucleic Acids Research* 50:D785–D794.

------------------------------------------------------------------------

## License

This project is released under the [MIT License](LICENSE).

------------------------------------------------------------------------

## Acknowledgments

- [DADA2](https://benjjneb.github.io/dada2/) developers for the core ASV inference framework
- [Pacific Biosciences](https://www.pacb.com/) for the public HiFi 16S workflow guidance
- [PICRUSt2](https://github.com/picrust/picrust2) developers for phylogenetic placement and hidden-state prediction
- [raeslab/QMP](https://github.com/raeslab/QMP) authors for the Quantitative Microbiome Profiling reference implementation
- [Bioconductor](https://bioconductor.org/) and [CRAN](https://cran.r-project.org/) communities

------------------------------------------------------------------------

**Author**: Amro Abbas - Generated with Claude AI assistance\
**Last Updated**: August 2026
