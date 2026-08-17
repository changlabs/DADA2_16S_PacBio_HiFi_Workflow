Step 5: DADA2 Pipeline (Filtering, Denoising, Chimera Removal & Taxonomy
Assignment)
================

- [Introduction](#introduction)
  - [Purpose](#purpose)
  - [Prerequisites](#prerequisites)
  - [What This Notebook Does](#what-this-notebook-does)
  - [Expected Input](#expected-input)
  - [Expected Output](#expected-output)
- [Environment Setup](#environment-setup)
  - [Load Required Packages](#load-packages)
- [Configuration](#configuration)
  - [Define Path Parameters](#define-paths)
  - [Configure DADA2 Parameters](#configure-dada2)
  - [Define Processing Parameters](#define-processing-parameters)
  - [Define Taxonomy Database Selection](#define-taxonomy)
- [Discover Input Files](#discover-input-files)
  - [Read FASTQ Files](#read-fastq-files)
  - [Define Checkpoint Signature](#checkpoint-signature)
- [Quality Filtering](#quality-filtering)
  - [Inspect Read Quality Profiles Before Filtering](#qc-before)
  - [Execute Filtering](#filter-trim)
  - [Quality Profiles After Filtering](#qc-after)
- [Learning Error Rates](#learning-error-rates)
  - [Learn the PacBio Error Model](#error-rates)
- [Sample Inference (Denoising)](#sample-inference-denoising)
  - [Dereplicate and Denoise Reads](#denoise)
- [Construct Sequence Table](#construct-sequence-table)
  - [Construct and Inspect the Sequence Table](#sequence-table)
- [Removing Chimeras](#removing-chimeras)
  - [Remove Chimeric Sequences](#remove-chimeras)
- [Track Reads Through Pipeline](#track-reads-through-pipeline)
- [Creating ASV Tables](#creating-asv-tables)
- [Assigning Taxonomy](#assigning-taxonomy)
  - [Taxonomic Classification](#assign-taxonomy)
  - [Taxonomy Comparison (if both databases used)](#taxonomy-comparison)
- [Export Results](#export-results)
  - [Build Processing Summary Workbook](#build-results-workbook)
  - [Document and Export Column Dictionary](#column-dictionary)
  - [Export Pool-Specific Result Bundles](#export-pool-results)
  - [Save Final Checkpoint](#save-results)
- [Output File Summary](#output-file-summary)
- [Recommended Next Step](#recommended-next-step)
- [Session Information](#session-information)
- [References](#references)
  - [Methods](#methods)
  - [Related](#related)
- [Appendix: Troubleshooting Guide](#appendix-troubleshooting-guide)
  - [No Reads Pass Filtering](#no-reads-pass-filtering)
  - [Error Learning Is Slow](#error-learning-is-slow)
  - [No Taxonomy Tables Are Produced](#no-taxonomy-tables-are-produced)
  - [High Chimera Rate](#high-chimera-rate)

<style type="text/css">
/* Custom styling shared across the workflow reports. */
body { font-size: 16px; line-height: 1.6; }
h1, h2, h3 { color: #2c3e50; margin-top: 1.5em; }
code {
  background-color: #F2F2F2;
  color: #2c3e50;
  padding: 2px 6px;
  border-radius: 3px;
  font-size: 14px;
}
pre, pre code { font-size: 14px; }
.alert-info {
  background-color: #2c3e50;
  color: #ffffff;
  border-left: 4px solid #f39c12;
  padding: 12px;
  margin: 15px 0;
}
.alert-warning {
  background-color: #2c3e50;
  color: #ffffff;
  border-left: 4px solid #e74c3c;
  padding: 12px;
  margin: 15px 0;
}
.alert-success {
  background-color: #d4edda;
  color: #155724;
  border-left: 4px solid #28a745;
  padding: 12px;
  margin: 15px 0;
}
table { width: 100%; }
th, td { text-align: left !important; white-space: nowrap !important; }
div.dataTables_scrollBody { overflow-x: auto !important; }
.param-box {
  font-family: monospace;
  background-color: #f0f0f0;
  padding: 2px 6px;
  border-radius: 3px;
  font-size: 14px;
}
</style>

# Introduction

## Purpose

This notebook is **Step 5** of the PacBio HiFi full-length 16S rRNA
sequencing data processing pipeline. It implements the complete
[DADA2](https://benjjneb.github.io/dada2/) workflow for single-end,
full-length PacBio HiFi reads, with integrated reporting, checkpoints,
taxonomy assignment, and portable exports.

## Prerequisites

Before running this notebook, ensure that:

1.  **[Step 3 (Primer Trimming and Orientation)](3_primer_trimming.md)**
    has completed successfully.
2.  Primer-trimmed FASTQ files are present in
    [results/3_primer_trimming/primer_trimmed_reads/](../../results/3_primer_trimming/primer_trimmed_reads/).
3.  The Step 3 workbook
    [primer_trimming_summary.xlsx](../../results/3_primer_trimming/primer_trimming_summary.xlsx)
    is present and contains the sample-to-pool mapping.
4.  **Recommended**: select and export `maxEE` with the [Step 4 PacBio
    maxEE Parameter Explorer](4_dada2_parameter_selection.md). If its
    workbook is absent, this notebook uses the documented fallback
    `maxEE = 2`.
5.  Taxonomy training sets are available in
    [tools/trainsets/](../../tools/trainsets/) if taxonomy assignment is
    required. ASV inference still runs when those optional references
    are absent.

## What This Notebook Does

The workflow accomplishes the following tasks:

1.  **Read filtering**: Sequential removal of reads outside the expected
    full-length range, reads containing ambiguous bases (`N`), and reads
    exceeding the expected-error threshold, with losses tracked at each
    stage.
2.  **Dereplication and learning error rates**: Consolidating identical
    sequences into unique reads and learning the PacBio HiFi error model
    with `PacBioErrfun`.
3.  **Sample inference (denoising)**: Distinguishing true biological
    sequences from sequencing noise independently for each sample using
    `BAND_SIZE = 32`.
4.  **Constructing the sequence table**: Combining the inferred
    full-length sequences directly; paired-read merging is neither
    required nor appropriate.
5.  **Removing chimeras**: Identifying and discarding artificial
    recombinant sequences that can distort findings.
6.  **Creating ASV tables**: Generating representative sequences and a
    sample-by-ASV count table.
7.  **Assigning taxonomy**: Classifying ASVs with SILVA and/or GTDB when
    compatible reference files are installed.

## Expected Input

- **Location**:
  [results/3_primer_trimming/primer_trimmed_reads/](../../results/3_primer_trimming/primer_trimmed_reads/)
- **Naming convention**: `{SampleID}_primer_trimmed.fastq`
- **Format**: One uncompressed, single-end FASTQ file per sample
- **Sample identifiers**: `SampleID` does not contain `PoolNumber`; pool
  provenance is read from the Step 3 workbook.

## Expected Output

- Filtered reads in
  [results/5_dada2_pipeline/filtered_reads/](../../results/5_dada2_pipeline/filtered_reads/)
- DADA2 console logs in
  [results/5_dada2_pipeline/console_output/](../../results/5_dada2_pipeline/console_output/)
- Stage-specific checkpoints in
  [results/5_dada2_pipeline/checkpoints/](../../results/5_dada2_pipeline/checkpoints/)
- Read-quality profiles before and after filtering
- PacBio error-rate plot
  [error_rates.pdf](../../results/5_dada2_pipeline/error_rates.pdf)
- Amplicon-length plot
  [amplicon_sequence_lengths.pdf](../../results/5_dada2_pipeline/amplicon_sequence_lengths.pdf)
- Read tracking and workbook documentation in
  [processing_summary.xlsx](../../results/5_dada2_pipeline/processing_summary.xlsx)
- ASV representative sequences in
  [asv_sequences.csv](../../results/5_dada2_pipeline/asv_sequences.csv)
- Sample-by-ASV counts in
  [asv_count_table.csv](../../results/5_dada2_pipeline/asv_count_table.csv)
- Taxonomy tables in
  [silva_taxonomy_table.csv](../../results/5_dada2_pipeline/silva_taxonomy_table.csv)
  and/or
  [gtdb_taxonomy_table.csv](../../results/5_dada2_pipeline/gtdb_taxonomy_table.csv),
  according to the selected references
- When more than one pool is present, matching per-pool tables are split
  into separate folders under
  [results/5_dada2_pipeline/separate_pools/](../../results/5_dada2_pipeline/separate_pools/)

------------------------------------------------------------------------

# Environment Setup

## Load Required Packages

The chunk below loads every R package this notebook depends on, plus the
shared helper functions used throughout the workflow for Excel writing,
column documentation, and output links.

``` r
# dada2: Core package for amplicon sequence variant inference.
library(dada2)

# Biostrings: Biological string manipulation used for ASV sequences.
library(Biostrings)

# data.table: High-performance data manipulation for summaries and exports.
library(data.table)

# DT: Interactive, horizontally scrollable tables in the HTML report.
library(DT)

# fs: Cross-platform filesystem operations.
library(fs)

# ggplot2: Publication-quality visualization of sequence lengths.
library(ggplot2)

# here: Reproducible paths relative to the project root.
library(here)

# openxlsx: Reading and writing Excel workbooks without Java.
library(openxlsx)

# parallel: CPU detection for multithreaded DADA2 operations.
library(parallel)

# ShortRead: Complete FASTQ record counting.
library(ShortRead)

# Source the workflow's shared Excel and reporting helpers.
source(here("R", "functions", "add_sheet_to_excel_function.R"))
source(here("R", "functions", "build_column_dictionary_function.R"))
source(here("R", "functions", "render_output_links_function.R"))
source(here("R", "functions", "render_output_tree_function.R"))

# Every HTML table uses the same fixed-height, horizontally scrollable layout.
# Sorting, searching, pagination, and the information footer are deliberately
# disabled so the report presents static audit tables without extra controls.
default_datatable_options <- list(
  scrollX = TRUE,
  scrollY = "400px",
  scrollCollapse = TRUE,
  paging = FALSE,
  searching = FALSE,
  ordering = FALSE,
  info = FALSE,
  dom = "t",
  autoWidth = TRUE,
  columnDefs = list(list(className = "dt-left", targets = "_all"))
)

safe_datatable <- function(data, options = list(), ...) {
  merged_options <- modifyList(default_datatable_options, options)
  tryCatch(
    DT::datatable(data, options = merged_options, rownames = FALSE, ...),
    error = function(e) {
      message("Interactive table display failed; showing a static table.")
      print(data)
    }
  )
}
```

------------------------------------------------------------------------

# Configuration

## Define Path Parameters

Set up all the input and output paths for this step of the workflow.

``` r
# Input folder containing the Q20-filtered, primer-trimmed, consistently
# oriented FASTQ files written by Step 3.
input_folder <- here("results", "3_primer_trimming", "primer_trimmed_reads")

# Step 3 workbook containing authoritative SampleID and PoolNumber metadata.
step3_workbook <- here(
  "results", "3_primer_trimming", "primer_trimming_summary.xlsx"
)

# Earlier workflow workbooks provide the raw-read and Q20-filtered counts used
# in the complete Reads_Tracking table.
step1_workbook <- here(
  "results", "1_data_integrity_and_sample_mapping",
  "data_integrity_and_sample_mapping.xlsx"
)
step2_workbook <- here(
  "results", "2_quality_filtered_reads",
  "quality_and_read_length_summary.xlsx"
)

# This notebook owns all files under results/5_dada2_pipeline/.
results_folder <- here("results")
output_folder <- here(results_folder, "5_dada2_pipeline")
filtered_reads_folder <- here(output_folder, "filtered_reads")
checkpoints_folder <- here(output_folder, "checkpoints")
console_output_folder <- here(output_folder, "console_output")

# Principal output files.
output_excel_path <- here(output_folder, "processing_summary.xlsx")

dir_create(output_folder, recurse = TRUE)
dir_create(filtered_reads_folder, recurse = TRUE)
dir_create(checkpoints_folder, recurse = TRUE)
dir_create(console_output_folder, recurse = TRUE)

cat("Input folder:", input_folder, "\n",
    "Output folder:", output_folder, "\n")
```

## Configure DADA2 Parameters

PacBio HiFi reads are full-length, so `truncLen` is intentionally
absent. The 1,000–1,600 bp interval follows the current PacBio HiFi-16S
workflow default. This notebook loads `maxEE` from the [Step 4 parameter
workbook](../../results/4_dada2_parameter_selection/dada2_filter_parameters.xlsx)
when available; otherwise it uses the clearly documented fallback
`maxEE = 2`.

``` r
# Retain primer-trimmed reads only when their full length falls within this
# interval. Unlike paired-end Illumina reads, PacBio HiFi reads already span
# the complete amplicon, so these values define a biological target-length
# filter rather than positions at which reads should be truncated.
minimum_read_length <- 1000L
maximum_read_length <- 1600L

# Use maxEE = 2 only as a fallback when Step 4 has not exported a selection.
# The active value and its source are resolved and validated immediately below.
fallback_maximum_expected_errors <- 2
step4_parameter_workbook <- here(
  "results", "4_dada2_parameter_selection", "dada2_filter_parameters.xlsx"
)

# "maxEE" means maximum expected errors. For each base, its quality score Q is
# converted to an error probability P using P = 10^(-Q/10); DADA2 then sums
# those probabilities across the complete read. A read is discarded when that
# sum exceeds maxEE. Values below 1 are very stringent, values around 1--2 are
# moderate, and values above 2 are progressively less stringent. This filter
# complements Step 2's mean-Q20 filter because it accounts for the accumulated
# error probability across each full-length read.
maximum_expected_errors <- fallback_maximum_expected_errors
maximum_expected_errors_source <- "Step 5 fallback"

# Load exactly one numeric max_expected_errors row from the Step 4 workbook.
# Failing clearly on a malformed workbook prevents a stale or ambiguous value
# from being applied silently.
if (file_exists(step4_parameter_workbook)) {
  workbook_sheets <- openxlsx::getSheetNames(step4_parameter_workbook)
  if (!("Parameters" %in% workbook_sheets)) {
    stop("The Step 4 parameter workbook has no Parameters sheet: ",
         step4_parameter_workbook)
  }
  step4_parameters <- openxlsx::read.xlsx(
    step4_parameter_workbook,
    sheet = "Parameters"
  )
  if (!all(c("Parameter", "Value") %in% names(step4_parameters))) {
    stop("The Step 4 Parameters sheet must contain Parameter and Value columns: ",
         step4_parameter_workbook)
  }
  selected_row <- which(
    trimws(as.character(step4_parameters$Parameter)) == "max_expected_errors"
  )
  if (length(selected_row) != 1L) {
    stop("The Step 4 Parameters sheet must contain exactly one max_expected_errors row: ",
         step4_parameter_workbook)
  }
  selected_value <- suppressWarnings(as.numeric(step4_parameters$Value[[selected_row]]))
  if (length(selected_value) != 1L || !is.finite(selected_value) || selected_value <= 0) {
    stop("Step 4 max_expected_errors must be one finite numeric value greater than zero: ",
         step4_parameter_workbook)
  }
  maximum_expected_errors <- selected_value
  maximum_expected_errors_source <- "Step 4 parameter workbook"
}

# Full-length reads must not be truncated by position or base quality.
# `minQ = 0` disables rejection based on the lowest individual base quality,
# while `truncQ = 0` prevents truncation at low-quality bases. `maxN = 0`
# rejects every read containing an ambiguous nucleotide (N), as required for
# downstream DADA2 sample inference.
minimum_base_quality <- 0L
truncation_quality <- 0L
maximum_ambiguous_bases <- 0L

# `BAND_SIZE` controls the width of the band used by DADA2's sequence
# alignment. The wider value of 32 is appropriate for PacBio HiFi reads and is
# retained from the original dada2_PacBio.R implementation.
band_size <- 32L

# `MAX_CONSIST` is the maximum number of self-consistency iterations used while
# learning the error model. If convergence is not reached within this number,
# DADA2 returns the error rates estimated in the final iteration.
maximum_consistency_iterations <- 25L

# `nbases` is the minimum number of bases DADA2 attempts to use for error-rate
# learning. Samples are read until this total is reached or all supplied reads
# have been used.
error_learning_bases <- 1e10

# `pool = FALSE` infers ASVs independently in every sample. For extremely
# diverse communities, `pool = TRUE` can increase sensitivity to rare ASVs by
# processing all samples together, while `pool = "pseudo"` performs an initial
# independent pass and then shares detected variants across samples. This
# workflow retains the Illumina workflow's independent-sample setting.
pooling_method <- FALSE

# With `method = "consensus"`, each sample is checked independently for
# bimeras and the sample-level evidence is combined into a consensus decision
# for each ASV in the sequence table.
chimera_method <- "consensus"

# A candidate chimera's parent sequences must be at least this many times more
# abundant than the candidate before it can be removed. The PacBio workflow
# uses 3.5, retained from the original dada2_PacBio.R implementation.
minimum_parent_fold <- 3.5

parameter_table <- data.frame(
  Parameter = c(
    "minimum_read_length", "maximum_read_length", "maximum_expected_errors",
    "minimum_base_quality", "truncation_quality", "maximum_ambiguous_bases",
    "band_size", "maximum_consistency_iterations", "error_learning_bases",
    "pooling_method", "chimera_method", "minimum_parent_fold"
  ),
  NumericValue = c(
    minimum_read_length, maximum_read_length, maximum_expected_errors,
    minimum_base_quality, truncation_quality, maximum_ambiguous_bases,
    band_size, maximum_consistency_iterations, error_learning_bases,
    NA_real_, NA_real_, minimum_parent_fold
  ),
  TextValue = c(
    rep(NA_character_, 9), pooling_method, chimera_method, NA_character_
  ),
  Source = c(
    "Step 5 fixed", "Step 5 fixed", maximum_expected_errors_source,
    rep("Step 5 fixed", 9)
  ),
  stringsAsFactors = FALSE
)
```

Review the active values below before filtering. In particular, confirm
the target-length interval and whether `maxEE` came from Step 4 or the
documented fallback.

## Define Processing Parameters

Configure parallel processing and reproducibility while reserving two
CPU cores for normal system activity.

``` r
detected_cores <- suppressWarnings(detectCores())
available_cores <- if (
  length(detected_cores) == 1L && is.finite(detected_cores) && detected_cores >= 1
) as.integer(detected_cores) else 1L
nr_threads <- max(1L, available_cores - 2L)

set.seed(42)

cat("Available CPU cores:", available_cores, "\n",
    "Threads for DADA2:", nr_threads, "\n",
    "Random seed: 42\n")
```

## Define Taxonomy Database Selection

Use the workflow’s SILVA/GTDB reference-database layout. Both databases
are selected when both complete reference pairs are installed; one is
selected when only one is complete; taxonomy is skipped when neither is
available.

``` r
trainsets_folder <- here("tools", "trainsets")

find_reference <- function(folder, pattern) {
  matches <- list.files(folder, pattern = pattern, ignore.case = TRUE, full.names = TRUE)
  if (length(matches)) matches[[1L]] else NA_character_
}

database_config <- list(
  SILVA = list(
    trainset = find_reference(here(trainsets_folder, "SILVA"), "genus.*\\.fa(\\.gz)?$"),
    species = find_reference(here(trainsets_folder, "SILVA"), "species.*\\.fa(\\.gz)?$")
  ),
  GTDB = list(
    trainset = find_reference(here(trainsets_folder, "GTDB"), "genus.*\\.fa(\\.gz)?$"),
    species = find_reference(here(trainsets_folder, "GTDB"), "species.*\\.fa(\\.gz)?$")
  )
)

database_ready <- vapply(database_config, function(x) {
  all(vapply(x, function(path) length(path) == 1L && !is.na(path) && file_exists(path), logical(1)))
}, logical(1))
databases_to_use <- names(database_ready)[database_ready]
taxonomy_database <- if (length(databases_to_use) == 2L) {
  "BOTH"
} else if (length(databases_to_use) == 1L) {
  databases_to_use
} else {
  "NONE"
}

cat("Taxonomy database mode:", taxonomy_database, "\n")
```

If no complete reference pair is available, the report explains why
taxonomy is being skipped while allowing ASV inference to continue.

------------------------------------------------------------------------

# Discover Input Files

## Read FASTQ Files

Scan the Step 3 folder for one single-end full-length FASTQ per sample
and validate the identifiers against Step 3’s `Sample_Summary` sheet.

``` r
if (!dir_exists(input_folder)) {
  stop("Primer-trimmed input folder not found: ", input_folder, "\nRun Step 3 first.")
}
if (!file_exists(step3_workbook)) {
  stop("Step 3 workbook not found: ", step3_workbook)
}
if (!file_exists(step1_workbook)) {
  stop("Step 1 workbook not found: ", step1_workbook)
}
if (!file_exists(step2_workbook)) {
  stop("Step 2 workbook not found: ", step2_workbook)
}

input_pattern <- "(?i)_primer_trimmed\\.(fastq|fq)$"
input_paths <- sort(dir_ls(input_folder, regexp = input_pattern, type = "file"))
sample_names <- sub(input_pattern, "", path_file(input_paths), perl = TRUE)

if (length(input_paths) == 0L) stop("No primer-trimmed FASTQ files were found.")
if (anyDuplicated(sample_names)) stop("Primer-trimmed FASTQs produce duplicate SampleIDs.")
if (any(file_size(input_paths) == 0)) stop("One or more primer-trimmed FASTQs are empty.")

step3_samples <- as.data.table(read.xlsx(step3_workbook, sheet = "Sample_Summary"))
required_step3_columns <- c("PoolNumber", "SampleID")
if (!all(required_step3_columns %in% names(step3_samples))) {
  stop("Step 3 Sample_Summary must contain PoolNumber and SampleID.")
}
step3_samples <- unique(step3_samples[, .(
  PoolNumber = as.integer(PoolNumber),
  SampleID = as.character(SampleID)
)])
if (anyDuplicated(step3_samples$SampleID)) stop("Step 3 contains duplicate SampleIDs.")
if (!setequal(sample_names, step3_samples$SampleID)) {
  stop("Step 3 FASTQ filenames and Sample_Summary identifiers do not match exactly.")
}
step3_samples <- step3_samples[match(sample_names, SampleID)]

# Read counts from Steps 1-3 are joined by SampleID rather than by row order.
# This preserves explicit sample-alignment checks across all upstream stages,
# including the PacBio-specific Q20 stage.
step1_samples <- as.data.table(read.xlsx(step1_workbook, sheet = "Sample_Manifest"))
step2_samples <- as.data.table(read.xlsx(step2_workbook, sheet = "Sample_QC"))
step3_tracking <- as.data.table(read.xlsx(step3_workbook, sheet = "Sample_Summary"))

required_step1_columns <- c("SampleID", "InputReads")
required_step2_columns <- c("SampleID", "PassingReads")
required_step3_tracking_columns <- c("SampleID", "RetainedReads")

if (!all(required_step1_columns %in% names(step1_samples))) {
  stop("Step 1 Sample_Manifest must contain SampleID and InputReads.")
}
if (!all(required_step2_columns %in% names(step2_samples))) {
  stop("Step 2 Sample_QC must contain SampleID and PassingReads.")
}
if (!all(required_step3_tracking_columns %in% names(step3_tracking))) {
  stop("Step 3 Sample_Summary must contain SampleID and RetainedReads.")
}
if (!setequal(sample_names, step1_samples$SampleID) ||
    !setequal(sample_names, step2_samples$SampleID) ||
    !setequal(sample_names, step3_tracking$SampleID)) {
  stop("Sample identifiers are inconsistent across the Step 1, Step 2, and Step 3 workbooks.")
}

step1_samples <- step1_samples[match(sample_names, SampleID)]
step2_samples <- step2_samples[match(sample_names, SampleID)]
step3_tracking <- step3_tracking[match(sample_names, SampleID)]

sample_table <- data.frame(
  PoolNumber = step3_samples$PoolNumber,
  SampleID = sample_names,
  InputFASTQ = path_file(input_paths),
  InputSizeMB = round(as.numeric(file_size(input_paths)) / 1024^2, 3),
  stringsAsFactors = FALSE
)

cat("Samples found:", length(sample_names), "\n")
```

The validated sample inventory below confirms the stable `SampleID`,
pool assignment, input filename, and file size entering DADA2.

## Define Checkpoint Signature

Build a strict signature from input checksums, parameters, references,
and the DADA2 version. A checkpoint is reused only when every relevant
value is identical.

``` r
selected_reference_paths <- if (length(databases_to_use)) {
  unname(unlist(database_config[databases_to_use]))
} else character()

pipeline_signature <- list(
  input_paths = path_norm(input_paths),
  input_md5 = unname(tools::md5sum(input_paths)),
  parameters = parameter_table,
  taxonomy_mode = taxonomy_database,
  reference_paths = selected_reference_paths,
  reference_md5 = if (length(selected_reference_paths)) {
    unname(tools::md5sum(selected_reference_paths))
  } else character(),
  dada2_version = as.character(packageVersion("dada2"))
)

checkpoint_path <- function(stage) {
  here(checkpoints_folder, paste0("checkpoint_", stage, ".rds"))
}

load_stage_checkpoint <- function(stage, required_objects) {
  checkpoint_file <- checkpoint_path(stage)
  if (!file_exists(checkpoint_file)) return(NULL)
  checkpoint <- tryCatch(readRDS(checkpoint_file), error = function(e) NULL)
  if (is.null(checkpoint) ||
      !identical(checkpoint$signature, pipeline_signature) ||
      !identical(checkpoint$stage, stage) ||
      !all(required_objects %in% names(checkpoint$objects))) return(NULL)
  message("Resuming from validated checkpoint: ", path_file(checkpoint_file))
  checkpoint$objects
}

save_stage_checkpoint <- function(stage, objects) {
  checkpoint_file <- checkpoint_path(stage)
  temporary_file <- paste0(checkpoint_file, ".tmp")
  saveRDS(
    list(stage = stage, signature = pipeline_signature, objects = objects),
    temporary_file,
    compress = TRUE
  )
  if (file_exists(checkpoint_file)) file_delete(checkpoint_file)
  file_move(temporary_file, checkpoint_file)
  checkpoint_file
}
```

------------------------------------------------------------------------

# Quality Filtering

## Inspect Read Quality Profiles Before Filtering

The quality profile shows the distribution of base qualities as a
function of sequence position. There is one full-length read stream per
PacBio sample. The PDF contains the aggregated overview first, followed
by one plot per sample.

``` r
quality_before_path <- here(output_folder, "QC_before_filtering.pdf")
quality_before_plots <- list()

# Write the aggregated quality-profile overview first.
aggregated_before_plot <- tryCatch(
  plotQualityProfile(input_paths, aggregate = TRUE),
  error = function(e) {
    warning("Could not create the aggregated pre-filter quality profile: ",
            conditionMessage(e), call. = FALSE)
    NULL
  }
)
if (!is.null(aggregated_before_plot)) {
  quality_before_plots[["aggregated"]] <- aggregated_before_plot
}

# Generate the individual sample plots after the aggregate overview.
for (i in seq_along(input_paths)) {
  plot_object <- tryCatch(
    plotQualityProfile(input_paths[[i]]) + ggtitle(sample_names[[i]]),
    error = function(e) NULL
  )
  if (!is.null(plot_object)) quality_before_plots[[sample_names[[i]]]] <- plot_object
}

pdf(quality_before_path, width = 11, height = 8.5, onefile = TRUE)
for (plot_object in quality_before_plots) print(plot_object)
dev.off()
```

The complete quality-profile PDF is linked below; it begins with the
aggregated view and then shows every sample separately.

## Execute Filtering

Apply three explicit single-end filtering stages so losses from length,
ambiguous bases, and expected errors remain separately auditable. No
positional truncation is performed and every output FASTQ remains
uncompressed.

``` r
# Clear only the managed final FASTQs before rebuilding this run. Temporary
# stage folders are isolated below and removed after the final filter succeeds.
stale_filtered <- dir_ls(
  filtered_reads_folder,
  regexp = "\\.(fastq|fq)$",
  type = "file",
  fail = FALSE
)
if (length(stale_filtered)) file_delete(stale_filtered)

filter_staging <- here(output_folder, ".filter_staging")
if (dir_exists(filter_staging)) dir_delete(filter_staging)
length_stage_folder <- here(filter_staging, "length")
n_stage_folder <- here(filter_staging, "no_N")
dir_create(length_stage_folder, recurse = TRUE)
dir_create(n_stage_folder, recurse = TRUE)

length_stage_paths <- here(length_stage_folder, paste0(sample_names, ".fastq"))
n_stage_paths <- here(n_stage_folder, paste0(sample_names, ".fastq"))
filtered_paths <- here(filtered_reads_folder, paste0(sample_names, "_filtered.fastq"))

# Stage 1 retains only the expected full-length interval. maxN and maxEE are
# unrestricted here so this row measures length loss alone.
length_counts <- filterAndTrim(
  fwd = input_paths,
  filt = length_stage_paths,
  truncLen = 0,
  minLen = minimum_read_length,
  maxLen = maximum_read_length,
  maxN = Inf,
  maxEE = Inf,
  truncQ = 0,
  minQ = 0,
  rm.phix = FALSE,
  compress = FALSE,
  multithread = nr_threads,
  verbose = TRUE
)

# Stage 2 rejects ambiguous bases without imposing additional quality or
# length thresholds.
n_counts <- filterAndTrim(
  fwd = length_stage_paths,
  filt = n_stage_paths,
  truncLen = 0,
  minLen = 1,
  maxLen = Inf,
  maxN = maximum_ambiguous_bases,
  maxEE = Inf,
  truncQ = 0,
  minQ = 0,
  rm.phix = FALSE,
  compress = FALSE,
  multithread = nr_threads,
  verbose = TRUE
)

# Stage 3 applies the expected-error threshold and PhiX removal. truncLen,
# truncQ, and minQ remain disabled to preserve the complete PacBio amplicon.
quality_counts <- filterAndTrim(
  fwd = n_stage_paths,
  filt = filtered_paths,
  truncLen = 0,
  minLen = 1,
  maxLen = Inf,
  maxN = maximum_ambiguous_bases,
  maxEE = maximum_expected_errors,
  truncQ = truncation_quality,
  minQ = minimum_base_quality,
  rm.phix = TRUE,
  compress = FALSE,
  multithread = nr_threads,
  verbose = TRUE
)

rownames(length_counts) <- sample_names
rownames(n_counts) <- sample_names
rownames(quality_counts) <- sample_names

filtering_summary <- data.frame(
  PoolNumber = step3_samples$PoolNumber,
  SampleID = sample_names,
  InputReads = as.numeric(length_counts[, "reads.in"]),
  AfterLengthFilter = as.numeric(length_counts[, "reads.out"]),
  AfterNFilter = as.numeric(n_counts[, "reads.out"]),
  AfterExpectedErrorFilter = as.numeric(quality_counts[, "reads.out"]),
  PercentRetained = round(
    100 * as.numeric(quality_counts[, "reads.out"]) /
      as.numeric(length_counts[, "reads.in"]),
    2
  ),
  stringsAsFactors = FALSE
)

if (any(filtering_summary$AfterExpectedErrorFilter == 0L)) {
  stop("At least one sample retained no reads after DADA2 filtering.")
}
if (dir_exists(filter_staging)) dir_delete(filter_staging)
```

The table below makes losses at the target-length, ambiguous-base, and
expected-error stages visible separately for every sample.

## Quality Profiles After Filtering

Generate the same quality diagnostic for the reads entering PacBio error
learning and denoising.

``` r
names(filtered_paths) <- sample_names
quality_after_path <- here(output_folder, "QC_after_filtering.pdf")
quality_after_plots <- list()

# Write the aggregated quality-profile overview first.
aggregated_after_plot <- tryCatch(
  plotQualityProfile(filtered_paths, aggregate = TRUE),
  error = function(e) {
    warning("Could not create the aggregated post-filter quality profile: ",
            conditionMessage(e), call. = FALSE)
    NULL
  }
)
if (!is.null(aggregated_after_plot)) {
  quality_after_plots[["aggregated"]] <- aggregated_after_plot
}

# Generate the individual sample plots after the aggregate overview.
for (i in seq_along(filtered_paths)) {
  plot_object <- tryCatch(
    plotQualityProfile(filtered_paths[[i]]) + ggtitle(sample_names[[i]]),
    error = function(e) NULL
  )
  if (!is.null(plot_object)) quality_after_plots[[sample_names[[i]]]] <- plot_object
}

pdf(quality_after_path, width = 11, height = 8.5, onefile = TRUE)
for (plot_object in quality_after_plots) print(plot_object)
dev.off()
```

Open the linked PDF to inspect the quality distributions of the reads
that actually enter error learning and denoising.

------------------------------------------------------------------------

# Learning Error Rates

## Learn the PacBio Error Model

Learn one error model for the consistently oriented full-length reads.
`PacBioErrfun`, `BAND_SIZE = 32`, and `MAX_CONSIST = 25` configure error
learning for PacBio HiFi reads.

``` r
error_log <- here(console_output_folder, "dada2_error_model.log")
error_log_connection <- file(error_log, open = "wt")
sink(error_log_connection, split = TRUE)

tryCatch({
  cat("Learning error rates for PacBio HiFi reads...\n",
      "This step may take several minutes.\n\n")
  error_rates <- withCallingHandlers({
    learnErrors(
      # Paths to the quality-filtered, full-length PacBio FASTQ files.
      filtered_paths,
      # Use DADA2's PacBio-specific error-estimation function instead of the
      # default Illumina error model.
      errorEstimationFunction = PacBioErrfun,
      # Read samples until at least this many bases have been examined, or all
      # supplied reads have been used.
      nbases = error_learning_bases,
      # Randomize sample/read selection rather than always learning from files
      # in their supplied order.
      randomize = TRUE,
      # Use the wider PacBio alignment band configured above.
      BAND_SIZE = band_size,
      # Use the configured CPU threads for error learning.
      multithread = nr_threads,
      # Print the self-consistency progress to the console log.
      verbose = TRUE,
      # Stop after this many self-consistency iterations if the model has not
      # converged earlier.
      MAX_CONSIST = maximum_consistency_iterations
    )
  }, message = function(m) {
    cat(conditionMessage(m), "\n", sep = "")
    invokeRestart("muffleMessage")
  })
  cat("\nPacBio error model learned.\n")
}, finally = {
  sink()
  close(error_log_connection)
})
```

The learned substitution-error rates are plotted against nominal quality
scores so departures from the fitted model can be reviewed visually.

The validated error model and its filtering context are saved as a
reusable checkpoint for an identical input-and-parameter signature.

The following links provide the error-model plot, full console log, and
signature-validated checkpoint generated by this stage.

------------------------------------------------------------------------

# Sample Inference (Denoising)

## Dereplicate and Denoise Reads

Dereplicate identical reads, then infer ASVs independently for each
sample with the learned PacBio error model. The `pool = FALSE` setting
keeps sample inference independent rather than pooled or pseudo-pooled.

``` r
dereplicated_sequences <- derepFastq(filtered_paths, verbose = TRUE)

names(dereplicated_sequences) <- sample_names

denoise_log <- here(console_output_folder, "dada2_denoise.log")
denoise_log_connection <- file(denoise_log, open = "wt")
sink(denoise_log_connection, split = TRUE)

tryCatch({
  cat(">> Denoising PacBio HiFi reads\n")
  cat("   Using", nr_threads, "threads for parallel processing\n\n")
  denoised_sequences <- withCallingHandlers({
    dada(
      # Dereplicated full-length reads for every sample.
      dereplicated_sequences,
      # PacBio error rates learned from this dataset in the preceding stage.
      err = error_rates,
      # Use the PacBio alignment-band width configured above.
      BAND_SIZE = band_size,
      # Use the configured CPU threads for sample inference.
      multithread = nr_threads,
      # FALSE processes samples independently; TRUE pools all samples and
      # "pseudo" performs pseudo-pooling.
      pool = pooling_method,
      # Print sample-inference progress to the console log.
      verbose = TRUE
    )
  }, message = function(m) {
    cat(conditionMessage(m), "\n", sep = "")
    invokeRestart("muffleMessage")
  })
  cat("\nDenoising summary:\n")
  print(denoised_sequences)
  cat("\nSample inference complete.\n")
}, finally = {
  sink()
  close(denoise_log_connection)
})
```

After denoising completes, the inferred sample objects and their
provenance are checkpointed and linked with the complete console log.

------------------------------------------------------------------------

# Construct Sequence Table

## Construct and Inspect the Sequence Table

Construct the sample-by-sequence table directly from the denoised
full-length reads. There is no paired-read merge stage for PacBio HiFi.

``` r
sequence_table <- makeSequenceTable(denoised_sequences)

# Confirm that the full-length filter remains satisfied after ASV inference.
sequence_lengths <- nchar(colnames(sequence_table))
target_length_mask <- sequence_lengths >= minimum_read_length &
  sequence_lengths <= maximum_read_length
target_length_sequence_table <- sequence_table[, target_length_mask, drop = FALSE]
target_length_filtered_reads_per_sample <- rowSums(target_length_sequence_table)

# Get sequence length distribution
sequence_length_df <- as.data.frame(table(sequence_lengths))
colnames(sequence_length_df) <- c("Length", "Count")
sequence_length_df$Length <- as.integer(as.character(sequence_length_df$Length))

# Total number of amplicon sequence variants (ASVs) represented in the
# histogram below, i.e. the number of unique sequences in sequence_table
# before the length filter further down this notebook is applied
total_sequence_variants <- sum(sequence_length_df$Count)

# Number (and percentage) of those ASVs whose length falls inside the target
# amplicon range, i.e. the ASVs the length filter will retain
sequence_variants_in_target_range <- sum(
  sequence_length_df$Count[
    sequence_length_df$Length >= minimum_read_length &
      sequence_length_df$Length <= maximum_read_length
  ]
)
pct_sequence_variants_in_target_range <- round(
  100 * sequence_variants_in_target_range / total_sequence_variants, 1
)

# Headroom above the tallest bar so the summary annotation below is not
# clipped by the plot panel
histogram_y_max <- max(sequence_length_df$Count)

# Visualize the amplicon length distribution with a histogram, built from
# the full (pre-filter) sequence table so off-target lengths remain visible.
# Publication-ready styling: white panel with light horizontal gridlines only
# (theme_classic base), bold serif-free axis titles, and the two target-length
# threshold lines identified directly via their own x-axis tick labels (in the
# same firebrick red as the lines) rather than separate floating text
# annotations, so the coordinates read unambiguously as axis values.
length_plot <- ggplot(sequence_length_df, aes(x = Length, y = Count)) +
  geom_bar(stat = "identity", fill = "#123C69", width = 0.9) +
  # Vertical reference lines marking the minimum and maximum target
  # amplicon lengths
  geom_vline(xintercept = minimum_read_length, linetype = "dashed", colour = "firebrick3", linewidth = 0.6) +
  geom_vline(xintercept = maximum_read_length, linetype = "dashed", colour = "firebrick3", linewidth = 0.6) +
  # Summary annotation reporting the total number of ASVs represented in
  # the histogram and how many of them fall inside the target amplicon
  # length range.
  annotate("label", x = Inf, y = Inf,
           label = paste0(
             "Total sequences: ", total_sequence_variants, "\n",
             "Within ", minimum_read_length, "-", maximum_read_length, " bp: ",
             sequence_variants_in_target_range,
             " (", pct_sequence_variants_in_target_range, "%)"
           ),
           hjust = 1, vjust = 1, size = 3.2, colour = "black",
           fill = "white", label.size = 0.3) +
  scale_x_continuous(
    breaks = c(minimum_read_length, maximum_read_length),
    labels = paste0(c(minimum_read_length, maximum_read_length), " bp")
  ) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.05))) +
  labs(x = "Sequence Length (bp)", y = "Frequency",
       title = "Amplicon Length Distribution") +
  coord_cartesian(ylim = c(0, histogram_y_max * 1.18)) +
  theme_classic(base_size = 12) +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 13),
    axis.title = element_text(face = "bold", size = 11),
    axis.text.x = element_text(colour = "firebrick3", face = "bold", size = 10),
    axis.text.y = element_text(colour = "black", size = 10),
    axis.line = element_line(colour = "black", linewidth = 0.4),
    axis.ticks = element_line(colour = "black", linewidth = 0.4),
    panel.grid.major.y = element_line(colour = "grey85", linewidth = 0.3),
    panel.grid.minor = element_blank()
  )
```

The amplicon-length histogram is saved as a PDF and displayed below,
followed by the exact sequence-length counts used to construct it.

------------------------------------------------------------------------

# Removing Chimeras

## Remove Chimeric Sequences

Remove chimeras from the length-confirmed sequence table with the
consensus method. The abundance requirement from the original PacBio
script is retained.

``` r
chimera_log <- here(console_output_folder, "dada2_remove_chimeras.log")
chimera_log_connection <- file(chimera_log, open = "wt")
sink(chimera_log_connection, split = TRUE)

tryCatch({
  cat("Removing chimeric sequences...\n\n")
  non_chimeric_table <- withCallingHandlers({
    removeBimeraDenovo(
      # Sequence table after the target-length filter.
      target_length_sequence_table,
      # Check samples independently and combine their calls into a consensus
      # chimera decision for every ASV.
      method = chimera_method,
      # Require potential parents to exceed the candidate's abundance by this
      # factor before identifying the candidate as a chimera.
      minFoldParentOverAbundance = minimum_parent_fold,
      # Use the configured CPU threads for chimera detection.
      multithread = nr_threads,
      # Print chimera-removal progress to the console log.
      verbose = TRUE
    )
  }, message = function(m) {
    cat(conditionMessage(m), "\n", sep = "")
    invokeRestart("muffleMessage")
  })

  chimera_sequences_removed <- ncol(target_length_sequence_table) - ncol(non_chimeric_table)
  chimera_sequences_pct <- round(
    100 * chimera_sequences_removed / ncol(target_length_sequence_table), 1
  )
  non_chimeric_reads_pct <- round(
    100 * sum(non_chimeric_table) / sum(target_length_sequence_table), 1
  )
  cat("\nChimera Removal Summary:\n",
      "  Sequences before:", ncol(target_length_sequence_table), "\n",
      "  Sequences after:", ncol(non_chimeric_table), "\n",
      "  Chimeric sequences:", chimera_sequences_removed,
      "(", chimera_sequences_pct, "%)\n",
      "  Non-chimeric reads:", non_chimeric_reads_pct, "%\n")
}, finally = {
  sink()
  close(chimera_log_connection)
})
```

This reporting chunk verifies that at least one ASV remains, saves the
non-chimeric checkpoint, and links the chimera-removal log and
checkpoint.

------------------------------------------------------------------------

# Track Reads Through Pipeline

The chunk below consolidates read counts at every pipeline stage (raw,
Q20 filtering, primer trimming, target-length filtering, N filtering,
expected-error filtering, denoising, and chimera removal) into one
per-sample table, so overall read survival can be assessed at a glance;
the table is also exported to the `Reads_Tracking` sheet of the
processing [summary
workbook](../../results/5_dada2_pipeline/processing_summary.xlsx).

``` r
get_unique_count <- function(x) sum(getUniques(x))

if (!setequal(names(denoised_sequences), sample_names) ||
    !setequal(rownames(non_chimeric_table), sample_names)) {
  stop("Sample names are inconsistent across DADA2 objects.")
}

reads_tracking <- data.frame(
  PoolNumber = step3_samples$PoolNumber,
  SampleID = sample_names,
  Raw_Reads = as.integer(step1_samples$InputReads),
  After_Q20_Filter = as.integer(step2_samples$PassingReads),
  After_Primer_Trim = as.integer(step3_tracking$RetainedReads),
  After_Length_Filter = as.integer(filtering_summary$AfterLengthFilter),
  After_N_Filter = as.integer(filtering_summary$AfterNFilter),
  After_QualityFilter = as.integer(filtering_summary$AfterExpectedErrorFilter),
  Denoised = vapply(denoised_sequences[sample_names], get_unique_count, numeric(1)),
  After_Amplicon_Length_Filter = as.integer(
    target_length_filtered_reads_per_sample[sample_names]
  ),
  Non_Chimeric = rowSums(non_chimeric_table[sample_names, , drop = FALSE]),
  stringsAsFactors = FALSE
)
reads_tracking$Survival_Percent <- round(
  100 * reads_tracking$Non_Chimeric / reads_tracking$Raw_Reads,
  1
)

cat("\nReads Tracking Summary:\n",
    "  Total raw reads:", format(sum(reads_tracking$Raw_Reads), big.mark = ","), "\n",
    "  Total output reads:", format(sum(reads_tracking$Non_Chimeric), big.mark = ","), "\n",
    "  Overall survival:", round(sum(reads_tracking$Non_Chimeric) /
                                  sum(reads_tracking$Raw_Reads) * 100, 1), "%\n")
```

The full per-sample tracking table below follows the biological
processing order from raw reads through non-chimeric ASVs.

------------------------------------------------------------------------

# Creating ASV Tables

Assign short, human-readable ASV IDs to every representative sequence
and replace the sequence-string columns of the abundance table with
those identifiers.

``` r
asv_sequences <- data.frame(
  ASV_ID = paste0("ASV", seq_len(ncol(non_chimeric_table))),
  Sequence = colnames(non_chimeric_table),
  stringsAsFactors = FALSE
)

# Export ASV sequences
write.csv(
  asv_sequences,
  file = here(output_folder, "asv_sequences.csv"),
  row.names = FALSE
)

asv_count_matrix <- non_chimeric_table
colnames(asv_count_matrix) <- asv_sequences$ASV_ID
asv_count_table <- cbind(
  SampleID = rownames(asv_count_matrix),
  as.data.frame(asv_count_matrix, check.names = FALSE)
)
rownames(asv_count_table) <- NULL

# Export ASV count table
write.csv(
  asv_count_table,
  file = here(output_folder, "asv_count_table.csv"),
  row.names = FALSE
)

render_output_links(
  c(here(output_folder, "asv_sequences.csv"), here(output_folder, "asv_count_table.csv")),
  labels = c("ASV representative sequences (CSV)", "ASV count table (CSV)")
)
```

This concise summary reports the number of samples and non-chimeric ASVs
represented in the two primary CSV exports.

------------------------------------------------------------------------

# Assigning Taxonomy

## Taxonomic Classification

When complete reference pairs are installed, classify every non-chimeric
ASV with DADA2’s naive Bayesian classifier and exact-match species
assignment. When references are absent, preserve the ASV outputs and
record the skipped taxonomy stage in the run summary.

``` r
taxonomy_results <- list()
formatted_taxonomy_tables <- list()
taxonomy_log <- here(console_output_folder, "dada2_taxonomy_assignment.log")

if (length(databases_to_use)) {
  taxonomy_log_connection <- file(taxonomy_log, open = "wt")
  sink(taxonomy_log_connection, split = TRUE)
  tryCatch({
    for (database_name in databases_to_use) {
      cat("\nProcessing taxonomy with", database_name, "database\n\n")
      cat("Assigning taxonomy using", database_name, "...\n")
      cat("This step may take considerable time depending on dataset size.\n\n")
      taxonomy_assignments <- withCallingHandlers({
        assignTaxonomy(
          # Non-chimeric ASV sequences to classify.
          seqs = non_chimeric_table,
          # Database-specific genus-level training FASTA selected above.
          refFasta = database_config[[database_name]]$trainset,
          # Use the configured CPU threads for classification.
          multithread = nr_threads,
          # Print classification progress to the console log.
          verbose = TRUE,
          # Also test reverse-complemented ASVs and retain the better match.
          tryRC = TRUE,
          # Minimum bootstrap confidence required to assign a taxonomic rank;
          # DADA2's default is 50, while this workflow uses 80.
          minBoot = 80
        )
      }, message = function(m) {
        cat(conditionMessage(m), "\n", sep = "")
        invokeRestart("muffleMessage")
      })
      cat("\n", database_name, "taxonomy assignment complete.\n")

      cat("\nAssigning species using", database_name, "database...\n\n")
      taxonomy_with_species <- withCallingHandlers({
        addSpecies(
          # Genus-level taxonomy assignments produced immediately above.
          taxtab = taxonomy_assignments,
          # Database-specific species reference FASTA selected above.
          refFasta = database_config[[database_name]]$species,
          # Print species-assignment progress to the console log.
          verbose = TRUE,
          # Retain all equally valid exact species matches rather than forcing
          # a single arbitrary species name.
          allowMultiple = TRUE,
          # Also test reverse-complemented ASVs for an exact species match.
          tryRC = TRUE
        )
      }, message = function(m) {
        cat(conditionMessage(m), "\n", sep = "")
        invokeRestart("muffleMessage")
      })
      cat("\n", database_name, "species assignment complete.\n")
      taxonomy_results[[database_name]] <- taxonomy_with_species

      taxonomy_table <- as.data.frame(taxonomy_with_species, stringsAsFactors = FALSE)
      taxonomy_table <- cbind(
        ASV_ID = asv_sequences$ASV_ID[match(rownames(taxonomy_table), asv_sequences$Sequence)],
        taxonomy_table
      )
      rownames(taxonomy_table) <- NULL

      # Preserve the original Species assignments and add concise derived
      # display labels used throughout this workflow.
      taxonomy_ranks <- setdiff(names(taxonomy_table), "ASV_ID")
      taxonomy_table$Corrected_Species <- apply(
        taxonomy_table[, taxonomy_ranks, drop = FALSE], 1, function(x) {
          if (is.na(x["Species"]) && is.na(x["Genus"])) {
            available <- x[!is.na(x) & nzchar(x)]
            if (length(available)) paste("unclassified", tail(available, 1)) else "unclassified"
          } else if (is.na(x["Species"])) {
            paste(x["Genus"], "sp.")
          } else {
            paste(x["Genus"], x["Species"])
          }
        }
      )
      taxonomy_table$Unique_Tax <- vapply(seq_len(nrow(taxonomy_table)), function(i) {
        species_name <- taxonomy_table$Corrected_Species[[i]]
        duplicate_count <- sum(taxonomy_table$Corrected_Species == species_name, na.rm = TRUE)
        if (duplicate_count > 1L) paste(species_name, taxonomy_table$ASV_ID[[i]]) else species_name
      }, character(1))

      # Export taxonomy tables as reusable CSV files.
      taxonomy_output_path <- here(
        output_folder, paste0(tolower(database_name), "_taxonomy_table.csv")
      )
      write.csv(taxonomy_table, taxonomy_output_path, row.names = FALSE)
      formatted_taxonomy_tables[[database_name]] <- taxonomy_table
    }
    cat("\nAll taxonomy assignments complete.\n")
  }, finally = {
    sink()
    close(taxonomy_log_connection)
  })
} else {
  writeLines(
    c(
      "Taxonomy assignment skipped.",
      "No complete SILVA or GTDB trainset/species reference pair was found.",
      "Run setup/download_reference_databases.R and rerun Step 5 to add taxonomy."
    ),
    taxonomy_log
  )
}
```

## Taxonomy Comparison (if both databases used)

When both taxonomy databases are selected, compare how many ASVs each
database classified at every taxonomic rank and include the comparison
in the processing summary workbook.

``` r
comparison_stats <- NULL
if (all(c("SILVA", "GTDB") %in% names(taxonomy_results))) {
  silva_tax <- as.data.frame(taxonomy_results[["SILVA"]], stringsAsFactors = FALSE)
  gtdb_tax <- as.data.frame(taxonomy_results[["GTDB"]], stringsAsFactors = FALSE)
  taxonomy_levels <- intersect(
    c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species"),
    intersect(names(silva_tax), names(gtdb_tax))
  )
  comparison_stats <- data.frame(
    Level = taxonomy_levels,
    SILVA_Classified = vapply(taxonomy_levels, function(level) {
      sum(!is.na(silva_tax[[level]]) & nzchar(silva_tax[[level]]))
    }, integer(1)),
    GTDB_Classified = vapply(taxonomy_levels, function(level) {
      sum(!is.na(gtdb_tax[[level]]) & nzchar(gtdb_tax[[level]]))
    }, integer(1)),
    stringsAsFactors = FALSE
  )
  comparison_stats$SILVA_Percent <- round(
    100 * comparison_stats$SILVA_Classified / nrow(silva_tax), 1
  )
  comparison_stats$GTDB_Percent <- round(
    100 * comparison_stats$GTDB_Classified / nrow(gtdb_tax), 1
  )
}
```

The following section writes the taxonomy CSV files, displays the full
classifications as scrollable tables, and reports when taxonomy was
intentionally skipped.

------------------------------------------------------------------------

# Export Results

## Build Processing Summary Workbook

Export read tracking and any taxonomy-comparison summaries to the Excel
workbook. The ASV sequence and count tables are exported separately as
reusable CSV files.

``` r
workbook_sheets <- list(
  Reads_Tracking = reads_tracking
)
if (!is.null(comparison_stats)) {
  workbook_sheets$Database_Comparison <- comparison_stats
}

if (file_exists(output_excel_path)) file_delete(output_excel_path)
for (sheet_name in names(workbook_sheets)) {
  add_sheet_to_excel(
    workbook_path = output_excel_path,
    sheet_name = sheet_name,
    data = workbook_sheets[[sheet_name]],
    rownames = FALSE,
    overwrite = FALSE
  )
}
```

The report lists the processing-summary sheets written before the column
dictionary is appended.

## Document and Export Column Dictionary

Build a trailing `Column_Dictionary` sheet from the actual exported
tables so documentation cannot drift away from the workbook.

The generated dictionary is appended as the last workbook sheet and is
intentionally hidden from the HTML report to avoid duplicating a large
documentation table.

## Export Pool-Specific Result Bundles

When the sequencing sheet contains more than one pool, create a
self-contained result bundle for each pool. DADA2 inference, chimera
removal, ASV naming, and taxonomy assignment remain global so that the
same biological sequence keeps the same `ASV_ID` across pools. Each
pool-specific count table contains only that pool’s samples, and ASVs
with zero total reads in that pool are removed from its count, sequence,
and taxonomy tables.

``` r
pool_numbers <- sort(unique(step3_samples$PoolNumber))
pools_folder <- here(output_folder, "separate_pools")
pool_output_paths <- character()

# Remove a prior pool export before rebuilding it so obsolete pools or files
# cannot survive when the sample sheet changes between runs.
if (dir_exists(pools_folder)) dir_delete(pools_folder)

if (length(pool_numbers) > 1L) {
  dir_create(pools_folder, recurse = TRUE)

  for (pool_number in pool_numbers) {
    pool_name <- paste0("pool", pool_number)
    pool_folder <- here(pools_folder, pool_name)
    dir_create(pool_folder, recurse = TRUE)

    # Identify this pool's samples from the authoritative Step 3 mapping.
    pool_sample_ids <- step3_samples[
      PoolNumber == pool_number, SampleID
    ]

    # Retain only this pool's sample rows, preserving the global SampleID and
    # ASV identifiers established above.
    pool_asv_count_table <- asv_count_table[
      asv_count_table$SampleID %in% pool_sample_ids, , drop = FALSE
    ]
    pool_asv_count_table <- pool_asv_count_table[
      match(pool_sample_ids, pool_asv_count_table$SampleID), , drop = FALSE
    ]

    # Remove ASVs absent from every sample in this pool. The remaining ASV IDs
    # are then used to subset the sequence and taxonomy tables exactly.
    pool_asv_columns <- setdiff(names(pool_asv_count_table), "SampleID")
    pool_asv_totals <- colSums(pool_asv_count_table[, pool_asv_columns, drop = FALSE])
    pool_asv_ids <- pool_asv_columns[pool_asv_totals > 0]
    pool_asv_count_table <- pool_asv_count_table[
      , c("SampleID", pool_asv_ids), drop = FALSE
    ]
    pool_asv_sequences <- asv_sequences[
      match(pool_asv_ids, asv_sequences$ASV_ID), , drop = FALSE
    ]

    write.csv(
      pool_asv_count_table,
      here(pool_folder, "asv_count_table.csv"),
      row.names = FALSE
    )
    write.csv(
      pool_asv_sequences,
      here(pool_folder, "asv_sequences.csv"),
      row.names = FALSE
    )

    # Write one matching taxonomy CSV per database generated by this run.
    for (database_name in names(formatted_taxonomy_tables)) {
      pool_taxonomy_table <- formatted_taxonomy_tables[[database_name]][
        match(pool_asv_ids, formatted_taxonomy_tables[[database_name]]$ASV_ID),
        , drop = FALSE
      ]
      write.csv(
        pool_taxonomy_table,
        here(pool_folder, paste0(tolower(database_name), "_taxonomy_table.csv")),
        row.names = FALSE
      )
    }

    # Split the read-tracking summary by pool. Do not add the global database
    # comparison because it describes the combined ASV set, not one pool.
    pool_reads_tracking <- reads_tracking[
      reads_tracking$PoolNumber == pool_number, , drop = FALSE
    ]
    pool_workbook_path <- here(pool_folder, "processing_summary.xlsx")
    add_sheet_to_excel(
      workbook_path = pool_workbook_path,
      sheet_name = "Reads_Tracking",
      data = pool_reads_tracking,
      rownames = FALSE,
      overwrite = FALSE
    )
    pool_column_dictionary <- build_column_dictionary(
      sheet_name = "Reads_Tracking",
      data = pool_reads_tracking,
      descriptions = column_descriptions,
      workbook_path = pool_workbook_path,
      rownames = FALSE
    )
    add_sheet_to_excel(
      workbook_path = pool_workbook_path,
      sheet_name = "Column_Dictionary",
      data = pool_column_dictionary,
      rownames = FALSE,
      overwrite = FALSE
    )

    pool_output_paths <- c(pool_output_paths, pool_folder)
  }
}
```

When more than one pool is present, the links below open each
self-contained pool-specific result bundle; otherwise the report states
that only the combined dataset was produced.

## Save Final Checkpoint

Save a narrow final checkpoint containing the validated objects needed
to resume the workflow.

The primary deliverables from the combined analysis are linked below for
direct review and downstream use.

------------------------------------------------------------------------

# Output File Summary

The tree below lists every file written to
\[results/5_dada2_pipeline/\].

------------------------------------------------------------------------

# Recommended Next Step

The [ASV count
table](../../results/5_dada2_pipeline/asv_count_table.csv) and [ASV
representative
sequences](../../results/5_dada2_pipeline/asv_sequences.csv), together
with the taxonomy CSV files generated for the selected databases, are
the required inputs for downstream phylogenetic tree construction [(Step
6)](6_phylogenetic_tree.md), 16S-copy number correction [(Step
7)](7_copy_number_correction.md) or [(Step 9)](9_phyloseq_object.md),
which are all **optional** steps.

------------------------------------------------------------------------

# Session Information

Record the R environment for reproducibility.

------------------------------------------------------------------------

# References

## Methods

- Callahan BJ, McMurdie PJ, Rosen MJ, Han AW, Johnson AJA, Holmes SP
  (2016). DADA2: High-resolution sample inference from Illumina amplicon
  data. *Nature Methods* 13, 581-583.
  <https://doi.org/10.1038/nmeth.3869>
- [DADA2 R package documentation](https://benjjneb.github.io/dada2/)
- [DADA2 pipeline
  tutorial](https://benjjneb.github.io/dada2/tutorial.html)
- [Pooling samples for sample
  inference](https://benjjneb.github.io/dada2/pool.html#pooling-for-sample-inference)
- [PacBio HiFi full-length 16S
  workflow](https://github.com/PacificBiosciences/HiFi-16S-workflow)
- [SILVA trainsets for
  DADA2](https://benjjneb.github.io/dada2/training.html)
- [Genome Taxonomy Database](https://gtdb.ecogenomic.org/)

## Related

- [Step 1 — Data Integrity and Sample
  Mapping](1_data_integrity_and_sample_mapping.md)
- [Step 2 — Quality Filtering](2_quality_filtering.md)
- [Step 3 — Primer Trimming and Orientation](3_primer_trimming.md)
- [Step 5 results
  workbook](../../results/5_dada2_pipeline/processing_summary.xlsx)

------------------------------------------------------------------------

# Appendix: Troubleshooting Guide

## No Reads Pass Filtering

If all reads are filtered out, inspect `Reads_Tracking` in the workbook
to determine whether losses occurred at the length, ambiguous-base, or
expected-error stage. Confirm the amplified target length before
changing the 1,000–1,600 bp defaults; increase `maximum_expected_errors`
only after reviewing the learned-quality characteristics.

## Error Learning Is Slow

PacBio full-length reads contain substantially more bases per read than
short Illumina amplicons. Error learning can therefore be the most
computationally intensive stage. The checkpoint system prevents later
stages from losing a completed error model, and `error_learning_bases`
can be reduced for exploratory runs if necessary.

## No Taxonomy Tables Are Produced

Taxonomy is intentionally skipped when neither
[tools/trainsets/SILVA/](../../tools/trainsets/SILVA/) nor
[tools/trainsets/GTDB/](../../tools/trainsets/GTDB/) contains both a
genus training FASTA and species assignment FASTA. Run
[setup/download_reference_databases.R](../../setup/download_reference_databases.R),
then rerun this notebook.

## High Chimera Rate

Confirm that [Step 3](3_primer_trimming.md) retained the expected linked
primer-pair structure and that the configured length interval matches
the amplified locus. Excessive PCR cycling, off-target amplification,
and incomplete primer removal can all increase apparent chimera loss.
