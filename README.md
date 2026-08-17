# DADA2 Workflow for PacBio HiFi Full-Length 16S rRNA Amplicon Sequencing

[![R Version](https://img.shields.io/badge/R-%3E%3D4.1-blue)](https://www.r-project.org/) [![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE) [![DADA2](https://img.shields.io/badge/DADA2-Bioconductor-orange)](https://benjjneb.github.io/dada2/) [![PacBio HiFi](https://img.shields.io/badge/PacBio-HiFi-0099A8)](https://www.pacb.com/technology/hifi-sequencing/) [![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey)](#4-install-external-tools)

A reproducible R-based pipeline for processing **PacBio HiFi full-length 16S rRNA amplicon sequencing data** using the [DADA2](https://benjjneb.github.io/dada2/) algorithm. The pipeline is organized as executable R Markdown notebooks covering delivery validation, sample mapping, quality filtering, primer trimming, taxonomy assignment, phylogenetic tree construction, 16S copy-number correction, microbial-load correction, and phyloseq object generation.

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

## Key Features {#key-features}

- **PacBio HiFi-aware quality control** — Calculates per-read length, GC content, and mean read quality directly in R and retains reads with **Q ≥ 20**.
- **Data-driven maxEE selection** — A PacBio-specific Shiny app displays pooled and per-sample expected-error retention and validates the selected threshold with real DADA2 processing.
- **Demultiplexed delivery mapping** — Maps Lima barcode-pair filenames to stable sample identities through [data/sample_sheet.xlsx](data/sample_sheet.xlsx).
- **Primer orientation and trimming** — Uses [Cutadapt](https://cutadapt.readthedocs.io/) with linked primers and reverse-complements reads when required.
- **PacBio DADA2 inference** — Uses the single-end PacBio HiFi workflow for filtering, error learning, denoising, chimera removal, ASV generation, and taxonomy assignment.
- **Pool-aware outputs** — Produces combined results and, when applicable, self-contained results for every pool under `separate_pools/`.
- **Dual taxonomy databases** — Supports [SILVA](https://www.arb-silva.de/), [GTDB](https://gtdb.ecogenomic.org/), or both.
- **16S copy-number correction** — Uses [PICRUSt2](https://github.com/picrust/picrust2/wiki) placement and hidden-state prediction.
- **Microbial-load correction** — Generates cell-count-scaled Quantitative Microbiome Profiles following [Vandeputte et al. (2017)](https://doi.org/10.1038/nature24460).
- **Multi-object phyloseq generation** — Builds one object per taxonomy database and available abundance source for the combined dataset and each pool.
- **Self-documenting outputs** — Excel workbooks end with a `Column_Dictionary` sheet, and notebook reports contain clickable links to referenced inputs and outputs.
- **Reproducible paths and checkpoints** — All notebooks use project-relative paths and preserve validated intermediate checkpoints where appropriate.

------------------------------------------------------------------------

## Pipeline Overview {#pipeline-overview}

``` text
  PacBio HiFi FASTQ archives + sample sheet
                     │
                     ▼
        ┌──────────────────────────┐
        │    Step 1 (Required)     │
        │     Integrity Check.     │
        │      Sample Mapping      │
        └────────────┬─────────────┘
                     ▼
        ┌──────────────────────────┐
        │     Step 2 (Required)    │
        │    Quality Filtering     │
        └────────────┬─────────────┘
                     ▼
        ┌──────────────────────────┐
        │     Step 3 (Required)    │
        │     Primer Trimming      │
        └────────────┬─────────────┘
                     ▼
        ┌──────────────────────────┐
        │    Step 4 (Recommended)  │
        │ DADA2 Parameter Explorer │
        └────────────┬─────────────┘
                     ▼
        ┌──────────────────────────┐
        │    Step 5 (Required)     │
        │     DADA2 Pipeline       │
        └────────────┬─────────────┘
                     │
          ┌──────────┴─────────────┐
          ▼                        ▼
 ┌───────────────────┐   ┌──────────────────────┐
 │ Step 6 (Optional) │   │   Step 7 (Optional)  │
 │ Phylogenetic tree │   │    16S Copy-number   │
 │                   │   │     Correction       │
 └────────┬──────────┘   └────────┬─────────────┘
          │                       ▼
          │             ┌────────────────────┐
          │             │  Step 8 (Optional) │
          │             │   Microbial Load   │
          │             │    Correction      │
          │             └────────┬───────────┘
          └──────────┬───────────┘
                     ▼
        ┌──────────────────────────┐
        │     Step 9 (Optional)    │
        │     Phyloseq Object      │
        └────────────┬─────────────┘
                     ▼
             Analysis-ready data
         (phyloseq .RData, corrected
          abundance tables, & plots)
```

------------------------------------------------------------------------

## Setup {#setup}

### 1. Clone the Repository

Download the repository from GitHub or clone it from the terminal:

``` bash
git clone https://github.com/changlabs/DADA2_16S_PacBio_HiFi_Workflow.git
```

### 2. Open the R Project in RStudio

Open [DADA2_16S_PacBio_HiFi_Workflow.Rproj](DADA2_16S_PacBio_HiFi_Workflow.Rproj) by double-clicking it, or from inside [RStudio](https://posit.co/products/open-source/rstudio/) via **File → Open Project**. All notebook paths use `here::here()` and resolve relative to this project root — always work from within the `.Rproj` session.

### 3. Install R Dependencies

Open [setup/install_R_dependencies.R](setup/install_R_dependencies.R) and run it with **Source**. It installs the CRAN and [Bioconductor](https://bioconductor.org/) packages used across the workflow, including [`dada2`](https://benjjneb.github.io/dada2/), [`DECIPHER`](http://www2.decipher.codes/), [`phyloseq`](https://joey711.github.io/phyloseq/), [`Biostrings`](https://bioconductor.org/packages/release/bioc/html/Biostrings.html), [`ShortRead`](https://bioconductor.org/packages/release/bioc/html/ShortRead.html), [`ape`](https://cran.r-project.org/package=ape), [`data.table`](https://cran.r-project.org/package=data.table), [`openxlsx`](https://cran.r-project.org/package=openxlsx), [`DT`](https://cran.r-project.org/web/package=DT), and the reporting packages.\
\
This package set covers all notebooks, including optional Steps [6](6_phylogenetic_tree.md)–[9](9_phyloseq_object.md). [Step 7](7_copy_number_correction.md) additionally requires the external PICRUSt2 installation described below, but none of the optional notebooks needs a separate R-package installation step.

On Linux you may need system libraries before running the script:

``` bash
sudo apt install libcurl4-openssl-dev libssl-dev libxml2-dev libfontconfig1-dev
```

### 4. Install External Tools

Before running the installer, make sure the following system prerequisites are available:

- Python 3.9 or newer; Debian/Ubuntu also requires `python3-venv`
- A C compiler (`gcc`, `cc`, or `clang`) for FastTree

Installing these prerequisites may require administrator access. On Debian/Ubuntu, for example, use `sudo apt-get install python3-venv default-jre gcc`. On macOS, install a JRE and use `xcode-select --install` for Apple clang.

Then open [`setup/install_required_tools.R`](setup/install_required_tools.R) in RStudio and run it with **Source**. The script downloads and installs the following tools into the project-local [`tools/`](tools/) directory without requiring conda or a system-wide installation of the tools themselves:

| Tool | Location | Purpose |
|:---|:---|:---|
| [Cutadapt](https://cutadapt.readthedocs.io/) | `tools/cutadapt/venv/` | Primer trimming and read orientation |
| [FastTree](https://morgannprice.github.io/fasttree/) | `tools/fasttree/FastTree` | Phylogenetic tree construction |

FastTree is compiled for the current computer. The installer tries an OpenMP build first and falls back to a single-threaded build when OpenMP is unavailable, which is normal with Apple clang on macOS.

### 5. Install PICRUSt2 (Optional — for [Step 7](7_copy_number_correction.md))

**Skip this step if you do not plan to run the optional [Step 7](#step-7--16s-copy-number-correction-optional) notebook for 16S copy number correction.**

[PICRUSt2](https://github.com/picrust/picrust2/wiki) is a conda package with several compiled phylogenetics dependencies (HMMER, EPA-ng, gappa, SEPP) that are not practical to manage inside the plain pip virtual environments used above, so it is installed separately, into its own dedicated conda environment. This requires a working conda/miniconda installation already present on your machine.

``` bash
bash setup/install_picrust2.sh
```

This installer supports **Linux only** and exits without making changes on macOS or other operating systems. By default it creates a conda environment named `picrust2`, which is the name [Step 7 (16S Copy Number Correction)](R/notebooks/7_copy_number_correction.md) expects. Run it once per Linux machine.

### 6. Download Reference Databases

Open [`setup/download_reference_databases.R`](setup/download_reference_databases.R) in RStudio and run it with **Source**. This downloads DADA2-formatted reference databases into [`tools/trainsets/`](tools/trainsets/):

A `download_manifest.txt` file is written to each subfolder recording the source URLs, download timestamps, file sizes, exact file paths, and the exact-size/gzip-stream verification result.

[SILVA](https://www.arb-silva.de/) is appropriate for most studies. [GTDB](https://gtdb.ecogenomic.org/) uses a rank-normalized, genome-based taxonomy and is better suited for prokaryote-focused analyses where consistent genus/species nomenclature matters.

### 7. Add PacBio FASTQ Archives and the Sample Sheet

Copy your FASTQ files into the [`data/fastq/`](data/fastq/) directory. Place one `.fastq.zip` archive per supplied pool under a lowercase folder:

``` text
data/fastq/pool1/<delivery>.fastq.zip
data/fastq/pool2/<delivery>.fastq.zip
```

Edit [data/sample_sheet.xlsx](data/sample_sheet.xlsx) so every active barcode pair maps to a unique `SampleID` and numeric `PoolNumber`. `SampleID` must not include the pool number. Step 1 extracts only mapped archive members and retains unmatched sample-sheet rows for review.

See [data/README.md](data/README.md) for the complete format and consistency checks.

### 8. Copy Your Cell Count File (Optional)

Only needed for Step 8 (Microbial Load Correction) if you have independent microbial load (cell count) measurements per sample -- e.g. from flow cytometry or qPCR. Skip this if you don't; every other step works on relative abundances without it.

The cell-count template is provided at [`data/cell_count/cell_count.tsv`](data/cell_count/cell_count.tsv), which is also this pipeline's default expected input path. Replace its generic sample IDs and placeholder counts with your measurements. See [`data/README.md`](data/README.md) for the full file format.

### 9. Add Your Metadata File (Optional)

Only needed for [Step 9](9_phyloseq_object.md) if you want experimental sample information included in the generated phyloseq objects. Replace the template at [`data/metadata.tsv`](data/metadata.tsv) with metadata whose sample identifiers match your data. If no metadata file is provided, Step 9 still runs and generates the phyloseq objects without metadata. - See [`data/README.md`](data/README.md) for the full file format.

------------------------------------------------------------------------

## Running the Pipeline {#running-the-pipeline}

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

## Pool-Specific Processing {#pool-specific-processing}

Step 5 performs DADA2 inference globally so identical biological sequences retain the same `ASV_ID` across pools. It then subsets counts, representative sequences, taxonomy, and processing summaries into `separate_pools/pool<number>/`.

Steps 6–9 behave as follows:

1.  Process the combined upstream output normally.
2.  Check whether the required upstream `separate_pools` directory exists.
3.  Discover valid pool folders automatically.
4.  Rerun the same notebook calculations in a clean R session for each pool.
5.  Write corresponding results to `results/<step_name>/separate_pools/<pool_name>/`.

If no `separate_pools` directory exists, only the combined dataset is processed.

------------------------------------------------------------------------

## Column Dictionaries {#column-dictionaries}

Every Excel workbook ends with a `Column_Dictionary` sheet documenting each exported column in plain language. It is generated with [R/functions/build_column_dictionary_function.R](R/functions/build_column_dictionary_function.R). If an exported column is added or renamed, update its description so the workbook remains self-documenting.

------------------------------------------------------------------------

## Project Structure {#project-structure}

``` text
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

## References {#references}

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

## License {#license}

This project is released under the [MIT License](LICENSE).

------------------------------------------------------------------------

## Acknowledgments {#acknowledgments}

- [DADA2](https://benjjneb.github.io/dada2/) developers for the core ASV inference framework
- [Pacific Biosciences](https://www.pacb.com/) for the public HiFi 16S workflow guidance
- [PICRUSt2](https://github.com/picrust/picrust2) developers for phylogenetic placement and hidden-state prediction
- [raeslab/QMP](https://github.com/raeslab/QMP) authors for the Quantitative Microbiome Profiling reference implementation
- [Bioconductor](https://bioconductor.org/) and [CRAN](https://cran.r-project.org/) communities

------------------------------------------------------------------------

**Author**: Amro Abbas - Generated with Claude AI assistance\
**Last Updated**: August 2026
