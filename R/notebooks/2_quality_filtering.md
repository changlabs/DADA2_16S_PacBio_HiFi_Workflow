Step 2: PacBio HiFi Quality Filtering
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
  - [Define Input and Output Paths](#define-paths)
  - [Define QC Parameters](#define-qc-parameters)
  - [Validate Configuration](#validate-configuration)
- [Functions](#functions)
  - [Define Table and FASTQ Helpers](#helper-functions)
- [Step 1 Manifest](#step-1-manifest)
  - [Read and Validate the Sample Manifest](#read-manifest)
- [FASTQ Quality Assessment](#fastq-quality-assessment)
  - [Stream and Summarize FASTQ Files](#summarize-fastq)
  - [Sample QC Summary](#sample-qc-summary)
  - [Paginated Distribution Plots](#distribution-plots)
    - [Read-Length Distribution](#read-length-distribution)
    - [Read-QV Distribution](#read-qv-distribution)
- [Export Results](#export-results)
  - [Save QC Tables to Excel](#save-excel)
  - [Final QC Decision](#final-decision)
- [Output Files](#output-files)
- [Output File Summary](#output-file-summary)
- [Recommended Next Step](#recommended-next-step)
- [Session Information](#session-information)
- [References](#references)
  - [Methods and Software](#methods-and-software)
  - [Documentation](#documentation)
  - [Related Project Files](#related-project-files)
- [Appendix: Troubleshooting Guide](#appendix-troubleshooting-guide)
  - [Step 1 Workbook or FASTQs Are
    Missing](#step-1-workbook-or-fastqs-are-missing)
  - [Mean Quality Values Look
    Unexpected](#mean-quality-values-look-unexpected)
  - [Read Lengths Fall Outside the Expected
    Range](#read-lengths-fall-outside-the-expected-range)
  - [Per-Read Audit for Large Runs](#per-read-audit-for-large-runs)
  - [Large Runs and Memory Use](#large-runs-and-memory-use)

<style type="text/css">
body {
  font-size: 16px;
  line-height: 1.6;
}
&#10;h1, h2, h3 {
  color: #2c3e50;
  margin-top: 1.5em;
}
&#10;code {
  background-color: #F2F2F2;
  color: #2c3e50;
  padding: 2px 6px;
  border-radius: 3px;
  font-size: 14px;
}
&#10;pre, pre code {
  font-size: 14px;
}
&#10;.alert-info {
  background-color: #2c3e50;
  color: #ffffff;
  border-left: 4px solid #f39c12;
  padding: 12px;
  margin: 15px 0;
}
&#10;.alert-warning {
  background-color: #2c3e50;
  color: #ffffff;
  border-left: 4px solid #e74c3c;
  padding: 12px;
  margin: 15px 0;
}
&#10;.alert-success {
  background-color: #d4edda;
  color: #155724;
  border-left: 4px solid #28a745;
  padding: 12px;
  margin: 15px 0;
}
&#10;table,
th,
td {
  text-align: left !important;
}
&#10;th, td {
  white-space: normal;
  word-wrap: break-word;
  overflow-wrap: anywhere;
  word-break: break-word;
  vertical-align: top;
}
&#10;/* Keep column names on one line; the DataTables viewport supplies horizontal
   scrolling when the resulting table is wider than the report body. */
th,
.dataTables_wrapper table.dataTable th {
  white-space: nowrap !important;
  word-break: normal !important;
  overflow-wrap: normal !important;
}
&#10;.dataTables_wrapper table.dataTable td,
.dataTables_wrapper .dt-left,
.dataTables_wrapper .dt-right,
.dataTables_wrapper .dt-center {
  text-align: left !important;
  white-space: normal !important;
  overflow-wrap: anywhere;
  word-break: break-word;
}
&#10;.dataTables_wrapper table.dataTable thead th {
  white-space: nowrap !important;
  word-break: normal !important;
  overflow-wrap: normal !important;
}
&#10;.dataTables_scrollBody,
.dataTables_scrollHead {
  overflow-x: auto !important;
}
</style>

# Introduction

## Purpose

This notebook is **Step 2** of the PacBio HiFi full-length 16S rRNA
workflow. It reads the validated original FASTQ paths mapped by [Step
1](1_data_integrity_and_sample_mapping.md), implements PacBio-style read
statistics and Q20 filtering in R, and creates an auditable QC report
before [Step 3 (Primer Trimming with Cutadapt)](3_primer_trimming.md).
After primer trimming, [Step 4](4_dada2_parameter_selection.md) supports
`maxEE` selection and [Step 5](5_dada2_pipeline.md) performs the
complete DADA2 analysis.

PacBio HiFi reads already span the full amplified 16S region. This
notebook therefore assesses complete-read length, GC content, and
quality value (QV) and does not choose a positional truncation length.
Reads below the configurable Q20 threshold are excluded from the
filtered FASTQs used by subsequent steps.

## Prerequisites

Before running this notebook:

- Complete [Step 1](1_data_integrity_and_sample_mapping.md)
  successfully.
- Keep the original FASTQs at the project-relative paths recorded in the
  Step 1 manifest.
- Confirm that
  [data_integrity_and_sample_mapping.xlsx](../../results/1_data_integrity_and_sample_mapping/data_integrity_and_sample_mapping.xlsx)
  contains the `Sample_Manifest` worksheet.
- Install the R dependencies used by the workflow.

## What This Notebook Does

1.  **Reads the Step 1 manifest** and reconstructs portable paths to the
    validated FASTQ files.
2.  **Streams every FASTQ** in fixed-size chunks.
3.  **Calculates read statistics**, including read length, GC
    percentage, and quality value (QV) derived from mean base-error
    probability.
4.  **Applies a quality threshold of Q20**, writing passing records to
    gzip-compressed filtered FASTQ files
5.  **Streams the complete per-read audit table to a compressed TSV
    file** and accumulates compact histogram frequencies from every
    read.
6.  **Creates pre-filter read-length and QV distributions** as inline
    figures and standalone PDFs.
7.  **Exports a documented Excel workbook** with run settings,
    pre/post-filter sample QC, and a Column Dictionary.

## Expected Input

- [results/1_data_integrity_and_sample_mapping/data_integrity_and_sample_mapping.xlsx](../../results/1_data_integrity_and_sample_mapping/data_integrity_and_sample_mapping.xlsx)
- Original FASTQs referenced by `SourceFASTQPath` in the Step 1
  manifest.

## Expected Output

- [results/2_quality_filtered_reads/quality_and_read_length_summary.xlsx](../../results/2_quality_filtered_reads/quality_and_read_length_summary.xlsx)
- [results/2_quality_filtered_reads/per_read_statistics.tsv.gz](../../results/2_quality_filtered_reads/per_read_statistics.tsv.gz)
- [results/2_quality_filtered_reads/Q20_filtered_fastq/](../../results/2_quality_filtered_reads/Q20_filtered_fastq/)
- [results/2_quality_filtered_reads/read_length_distribution.pdf](../../results/2_quality_filtered_reads/read_length_distribution.pdf)
- [results/2_quality_filtered_reads/read_quality_distribution.pdf](../../results/2_quality_filtered_reads/read_quality_distribution.pdf)

------------------------------------------------------------------------

# Environment Setup

## Load Required Packages

Load the packages used for streaming FASTQ files, building plots and
tables, reading the [Step 1](1_data_integrity_and_sample_mapping.md)
manifest, and writing documented Excel results. The shared helper
functions are sourced from [R/functions/](../functions/).

``` r
# Declare dependencies in one place so the notebook fails before reading or
# writing files when the environment is incomplete.
required_packages <- c(
  "data.table", "DT", "fs", "ggplot2", "here", "knitr",
  "openxlsx", "readxl", "ShortRead"
)

missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))
]

if (length(missing_packages) > 0L) {
  stop(
    "Missing required package(s): ", paste(missing_packages, collapse = ", "),
    ". Install them before running Notebook 2."
  )
}

# Attach packages used repeatedly; less frequent calls remain namespace-qualified.
library(data.table)
library(fs)
library(ggplot2)
library(here)

# Reuse the same workbook and portable-link behavior as Notebook 1.
source(here("R", "functions", "add_sheet_to_excel_function.R"))
source(here("R", "functions", "build_column_dictionary_function.R"))
source(here("R", "functions", "render_output_links_function.R"))
source(here("R", "functions", "render_output_tree_function.R"))
source(here("R", "functions", "workflow_paths_function.R"))
```

------------------------------------------------------------------------

# Configuration

## Define Input and Output Paths

Define all paths relative to the project root. The [Step
1](1_data_integrity_and_sample_mapping.md) workbook supplies sample
identities, while the full project-relative source paths are resolved
inside the current project so copied projects remain portable.

``` r
# Step 1 inputs used by this notebook.
step1_folder <- workflow_results_dir("1_data_integrity_and_sample_mapping")
step1_workbook <- here(step1_folder, "data_integrity_and_sample_mapping.xlsx")
project_root <- here::here()

# Step 2 owns this complete output subtree.
results_folder <- workflow_results_dir("2_quality_filtered_reads")
filtered_fastq_folder <- here(results_folder, "Q20_filtered_fastq")
# Persist every read in a compressed TSV without Excel row limits or a full-table
# import into memory. Excel contains only the compact summary tables.
read_statistics_path <- here(results_folder, "per_read_statistics.tsv.gz")
workbook_path <- here(results_folder, "quality_and_read_length_summary.xlsx")
length_plot_path <- here(results_folder, "read_length_distribution.pdf")
quality_plot_path <- here(results_folder, "read_quality_distribution.pdf")
```

## Define QC Parameters

Set transparent review thresholds and streaming limits. The expected
length range should match the primer pair and biological target; it is
used only for visualization and does not filter reads!

``` r
# Full-length bacterial 16S amplicons are commonly near 1.5 kb. These broad
# review bounds can be adjusted for another primer pair or target region.
expected_length_min <- 1200L
expected_length_max <- 1800L

# Match the user-adjustable QV filter in PacBio's HiFi-16S workflow. QV is
# calculated from the mean base-error probability, as documented by SeqKit.
read_qv_cutoff <- 20

# Count every read in bounded FASTQ chunks; retain frequencies, not read vectors.
stream_yield_size <- 10000L
samples_per_plot_page <- 6L
length_histogram_bin_width <- 20L
qv_histogram_bin_width <- 0.5
annotation_length_min <- 1800L
annotation_length_max <- 2000L

# Phred+33 is the standard FASTQ quality encoding used for these files.
quality_ascii_offset <- 33L
```

## Validate Configuration

Validate inputs and parameter relationships before creating or replacing
any Step 2 output.

``` r
# Fail early when Step 1 artifacts are missing.
if (!file_exists(step1_workbook)) {
  stop("Step 1 workbook does not exist: ", step1_workbook)
}

# Prevent invalid thresholds or non-positive streaming limits.
if (expected_length_min < 1L || expected_length_max <= expected_length_min) {
  stop("Expected read-length bounds must satisfy 1 <= minimum < maximum.")
}
if (stream_yield_size < 1L || samples_per_plot_page != 6L ||
    length_histogram_bin_width <= 0 || qv_histogram_bin_width <= 0 ||
    annotation_length_max < annotation_length_min) {
  stop("Invalid streaming, histogram, annotation, or six-facet page configuration.")
}

# Create only this notebook's managed output folders.
dir_create(results_folder, recurse = TRUE)
dir_create(filtered_fastq_folder, recurse = TRUE)
```

The resolved inputs, managed result folder, quality threshold, and
streaming settings are printed below so this report records the exact
run configuration.

------------------------------------------------------------------------

# Functions

## Define Table and FASTQ Helpers

Define the shared presentation behavior and a streaming FASTQ
summarizer. Comments describe the memory bounds, quality conversion, and
all-read frequency aggregation and paginated plotting.

``` r
render_table <- function(x, caption = NULL, column_widths = NULL) {
  # Use one normalized data.frame for both HTML and GitHub renderers.
  table_data <- as.data.frame(x)

  if (knitr::is_html_output()) {
    # Force every column left and optionally widen selected columns. DataTables
    # uses zero-based targets, so subtract one from R column positions.
    column_definitions <- list(list(className = "dt-left", targets = "_all"))
    if (!is.null(column_widths)) {
      width_columns <- which(!is.na(column_widths) & nzchar(column_widths))
      column_definitions <- c(
        column_definitions,
        lapply(width_columns, function(column_index) {
          list(targets = column_index - 1L, width = column_widths[[column_index]])
        })
      )
    }

    # These are inspection tables: retain scrolling but remove sorting, search,
    # pagination, and entry-count controls.
    DT::datatable(
      table_data,
      caption = caption,
      rownames = FALSE,
      class = "display compact",
      options = list(
        scrollX = TRUE,
        scrollY = "400px",
        scrollCollapse = TRUE,
        paging = FALSE,
        searching = FALSE,
        ordering = FALSE,
        info = FALSE,
        dom = "t",
        autoWidth = !is.null(column_widths),
        columnDefs = column_definitions
      )
    )
  } else {
    # GitHub receives a portable, fully left-aligned Markdown table.
    knitr::kable(
      table_data,
      caption = caption,
      row.names = FALSE,
      align = rep("l", ncol(table_data))
    )
  }
}

calculate_read_qv <- function(quality_strings) {
  # SeqKit defines average read quality by converting every base Q score to an
  # error probability, averaging those probabilities, and converting the mean
  # error probability back to Phred scale. This is deliberately not the
  # arithmetic mean of the base Q scores.
  vapply(
    quality_strings,
    function(quality_string) {
      base_q <- utf8ToInt(quality_string) - quality_ascii_offset
      -10 * log10(mean(10^(-base_q / 10)))
    },
    numeric(1)
  )
}

# Merge chunk frequencies without retaining individual read observations.
add_frequencies <- function(existing, values) {
  chunk <- data.table(Value = values)[, .(Count = as.numeric(.N)), by = Value]
  rbindlist(list(existing, chunk))[, .(Count = sum(Count)), by = Value]
}

frequency_quantiles <- function(frequencies, probs) {
  frequencies <- copy(frequencies)
  setorder(frequencies, Value)
  cumulative <- cumsum(frequencies$Count)
  n <- sum(frequencies$Count)
  # Exact type-7 quantiles from ranks in the frequency table.
  at_rank <- function(rank) frequencies$Value[which(cumulative >= rank)[1L]]
  vapply(probs, function(p) {
    rank <- 1 + (n - 1) * p
    low <- floor(rank)
    fraction <- rank - low
    at_rank(low) * (1 - fraction) + at_rank(ceiling(rank)) * fraction
  }, numeric(1))
}

summarize_fastq <- function(path, sample_id, filtered_path, statistics_connection) {
  # Stream a fixed number of records per yield so memory use is independent of
  # total FASTQ size. The streamer is always closed, including after an error.
  streamer <- ShortRead::FastqStreamer(path, n = stream_yield_size)
  on.exit(close(streamer), add = TRUE)

  total_reads <- 0
  total_bases <- 0
  total_length_squared <- 0
  minimum_length <- Inf
  maximum_length <- -Inf
  reads_in_expected_range <- 0
  reads_in_annotation_range <- 0
  total_read_qv <- 0
  total_read_qv_squared <- 0
  minimum_read_qv <- Inf
  maximum_read_qv <- -Inf
  total_gc_percent <- 0
  reads_with_defined_gc <- 0
  passing_reads <- 0
  passing_bases <- 0

  # Exact integer length frequencies support quantiles; QV is binned while
  # streaming. Only the current sample's compact counts stay in memory.
  length_frequencies <- data.table(Value = numeric(), Count = numeric())
  qv_frequencies <- data.table(Value = numeric(), Count = numeric())

  # Remove a prior filtered file before the first append. Step 1 inputs remain
  # read-only and can therefore always be used to reproduce the filtering.
  if (file_exists(filtered_path)) file_delete(filtered_path)

  repeat {
    fastq_chunk <- ShortRead::yield(streamer)
    if (length(fastq_chunk) == 0L) break

    sequences <- ShortRead::sread(fastq_chunk)
    read_lengths <- as.numeric(Biostrings::width(sequences))
    # ShortRead stores qualities as a FastqQuality wrapper around a BStringSet.
    # Access the documented S4 slots directly because quality() is a generic
    # attached by ShortRead but is not exported for namespace-qualified use.
    quality_strings <- as.character(slot(slot(fastq_chunk, "quality"), "quality"))
    read_qv <- calculate_read_qv(quality_strings)

    # SeqKit reports GC as (G+C)/(A+C+G+T), excluding ambiguous characters
    # from the denominator. Reads without canonical bases receive NA.
    base_counts <- Biostrings::letterFrequency(sequences, letters = c("A", "C", "G", "T"))
    canonical_bases <- rowSums(base_counts)
    gc_percent <- fifelse(
      canonical_bases > 0,
      100 * (base_counts[, "C"] + base_counts[, "G"]) / canonical_bases,
      NA_real_
    )
    pass_qv <- read_qv >= read_qv_cutoff

    chunk_reads <- length(read_lengths)
    total_reads <- total_reads + chunk_reads
    total_bases <- total_bases + sum(read_lengths)
    total_length_squared <- total_length_squared + sum(read_lengths^2)
    minimum_length <- min(minimum_length, min(read_lengths))
    maximum_length <- max(maximum_length, max(read_lengths))
    reads_in_expected_range <- reads_in_expected_range + sum(
      read_lengths >= expected_length_min & read_lengths <= expected_length_max
    )

    total_read_qv <- total_read_qv + sum(read_qv)
    total_read_qv_squared <- total_read_qv_squared + sum(read_qv^2)
    minimum_read_qv <- min(minimum_read_qv, min(read_qv))
    maximum_read_qv <- max(maximum_read_qv, max(read_qv))
    total_gc_percent <- total_gc_percent + sum(gc_percent, na.rm = TRUE)
    reads_with_defined_gc <- reads_with_defined_gc + sum(!is.na(gc_percent))
    passing_reads <- passing_reads + sum(pass_qv)
    passing_bases <- passing_bases + sum(read_lengths[pass_qv])

    # Write every per-read statistic to the compressed audit table. The table
    # mirrors the SeqKit fx2tab fields used by PacBio while remaining R-native.
    read_statistics <- data.table(
      SampleID = sample_id,
      ReadID = as.character(ShortRead::id(fastq_chunk)),
      ReadLength = read_lengths,
      GCPercent = round(gc_percent, 4),
      ReadQV = round(read_qv, 4),
      PassQVFilter = pass_qv
    )
    writeLines(
      apply(read_statistics, 1L, paste, collapse = "\t"),
      con = statistics_connection
    )

    # Append only QV-passing records to a new gzip-compressed FASTQ. An empty output is
    # still created below when no read passes, preserving one output per input.
    if (any(pass_qv)) {
      ShortRead::writeFastq(
        fastq_chunk[pass_qv],
        filtered_path,
        mode = "a",
        compress = TRUE
      )
    }

    reads_in_annotation_range <- reads_in_annotation_range + sum(
      read_lengths >= annotation_length_min & read_lengths <= annotation_length_max
    )
    length_frequencies <- add_frequencies(length_frequencies, read_lengths)
    qv_frequencies <- add_frequencies(qv_frequencies, floor(read_qv / qv_histogram_bin_width))
  }

  if (total_reads == 0L) stop("FASTQ contains no reads: ", path)

  # Preserve a one-output-per-input contract even when no read reaches Q20.
  if (!file_exists(filtered_path)) {
    empty_filtered_connection <- gzfile(filtered_path, open = "wb")
    close(empty_filtered_connection)
  }

  # Compute full-dataset means and sample standard deviations from accumulated
  # sums, avoiding storage of every observation.
  mean_length <- total_bases / total_reads
  length_variance <- if (total_reads > 1L) {
    (total_length_squared - total_reads * mean_length^2) / (total_reads - 1L)
  } else {
    0
  }
  mean_read_qv <- total_read_qv / total_reads
  quality_variance <- if (total_reads > 1L) {
    (total_read_qv_squared - total_reads * mean_read_qv^2) / (total_reads - 1L)
  } else {
    0
  }

  length_quantiles <- frequency_quantiles(
    length_frequencies, c(0.05, 0.25, 0.50, 0.75, 0.95)
  )
  # Cache only aggregate counts on disk. Plotting loads six samples per page,
  # never all reads, all sample histograms, or the potentially huge audit TSV.
  histogram_path <- tempfile(pattern = "step2_histogram_", fileext = ".rds")
  length_histogram <- length_frequencies[, .(Count = sum(Count)),
    by = .(Value = floor(Value / length_histogram_bin_width))]
  saveRDS(list(length = length_histogram, quality = qv_frequencies), histogram_path)

  list(
    summary = data.table(
      SampleID = sample_id,
      FASTQ = as.character(path),
      TotalReads = as.numeric(total_reads),
      TotalBases = as.numeric(total_bases),
      MinimumLength = as.numeric(minimum_length),
      MeanLength = round(mean_length, 1),
      LengthSD = round(sqrt(max(length_variance, 0)), 1),
      MaximumLength = as.numeric(maximum_length),
      LengthP05 = round(length_quantiles[[1]], 1),
      LengthP25 = round(length_quantiles[[2]], 1),
      MedianLength = round(length_quantiles[[3]], 1),
      LengthP75 = round(length_quantiles[[4]], 1),
      LengthP95 = round(length_quantiles[[5]], 1),
      ReadsInAnnotationRange = as.numeric(reads_in_annotation_range),
      ReadsInExpectedLengthRange = as.numeric(reads_in_expected_range),
      PercentInExpectedLengthRange = round(100 * reads_in_expected_range / total_reads, 2),
      MeanGCPercent = if (reads_with_defined_gc > 0L) {
        round(total_gc_percent / reads_with_defined_gc, 2)
      } else {
        NA_real_
      },
      MinimumReadQV = round(minimum_read_qv, 2),
      MeanReadQV = round(mean_read_qv, 2),
      ReadQVSD = round(sqrt(max(quality_variance, 0)), 2),
      MaximumReadQV = round(maximum_read_qv, 2),
      QVCutoff = as.numeric(read_qv_cutoff),
      PassingReads = as.numeric(passing_reads),
      FilteredReads = as.numeric(total_reads - passing_reads),
      PercentPassingQV = round(100 * passing_reads / total_reads, 2),
      PassingBases = as.numeric(passing_bases),
      FilteredFASTQ = as.character(filtered_path),
      PlotReads = as.numeric(total_reads),
      HistogramPath = histogram_path
    )
  )
}
```

------------------------------------------------------------------------

# Step 1 Manifest

## Read and Validate the Sample Manifest

Read sample identities from the [Step 1 audit
workbook](../../results/1_data_integrity_and_sample_mapping/data_integrity_and_sample_mapping.xlsx)
rather than inferring them again from filenames. Reconstruct each FASTQ
path inside the current project and validate the one-row-per-sample
relationship.

``` r
# Read only the fields required for QC and path reconstruction.
manifest_raw <- readxl::read_excel(
  step1_workbook,
  sheet = "Sample_Manifest",
  col_types = "text"
)
manifest_raw <- as.data.table(manifest_raw)

required_manifest_columns <- c("PoolNumber", "SampleID", "SourceFASTQPath", "IntegrityStatus")
missing_manifest_columns <- setdiff(required_manifest_columns, names(manifest_raw))
if (length(missing_manifest_columns) > 0L) {
  stop("Step 1 Sample_Manifest is missing: ", paste(missing_manifest_columns, collapse = ", "),
       ". Rerun Notebook 1 to create the original-source mapping.")
}

# Refuse QC input from a Step 1 row that did not pass integrity validation.
if (any(manifest_raw$IntegrityStatus != "PASS")) {
  stop("Every Step 1 Sample_Manifest row must have IntegrityStatus = PASS.")
}

if (anyNA(manifest_raw$SourceFASTQPath) || any(!nzchar(manifest_raw$SourceFASTQPath)) ||
    any(is_absolute_path(manifest_raw$SourceFASTQPath))) {
  stop("Step 1 SourceFASTQPath must contain non-empty project-relative original FASTQ paths.")
}

sample_manifest <- manifest_raw[, .(
  PoolNumber = as.integer(PoolNumber),
  SampleID = as.character(SampleID),
  FASTQ = as.character(path_abs(SourceFASTQPath, start = project_root))
)]
setorder(sample_manifest, PoolNumber, SampleID)

if (nrow(sample_manifest) == 0L) stop("Step 1 Sample_Manifest contains no samples.")
if (anyDuplicated(sample_manifest$SampleID)) stop("Step 1 Sample_Manifest contains duplicate SampleIDs.")
if (any(!file_exists(sample_manifest$FASTQ))) {
  stop(
    "Original FASTQ file(s) from the Step 1 manifest are missing: ",
    paste(sample_manifest[!file_exists(FASTQ), FASTQ], collapse = ", ")
  )
}

render_table(
  sample_manifest,
  "Validated Step 1 inputs for PacBio QC",
  column_widths = c("120px", "190px", "520px")
)
```

This status line confirms how many Step 1 samples have valid, uniquely
resolved FASTQ inputs for quality assessment.

------------------------------------------------------------------------

# FASTQ Quality Assessment

## Stream and Summarize FASTQ Files

Stream every validated FASTQ, calculate full-dataset statistics, and
write reads meeting the configured QV threshold to new FASTQ files.

``` r
# Rebuild the compressed per-read audit table on every run and write the header
# once. A single open connection permits memory-bounded chunk-by-chunk output.
if (file_exists(read_statistics_path)) file_delete(read_statistics_path)

# This notebook owns Q20_filtered_fastq/. Remove FASTQs from an earlier sample
# naming scheme before writing the current dataset so obsolete identifiers
# cannot coexist with the newly generated workflow inputs.
stale_filtered_fastq <- dir_ls(
  filtered_fastq_folder,
  regexp = "\\.(fastq|fq)(\\.gz)?$",
  type = "file",
  recurse = FALSE
)
if (length(stale_filtered_fastq) > 0L) file_delete(stale_filtered_fastq)

statistics_connection <- gzfile(read_statistics_path, open = "wt")
writeLines(
  paste(c("SampleID", "ReadID", "ReadLength", "GCPercent", "ReadQV", "PassQVFilter"), collapse = "\t"),
  statistics_connection
)

# Keep the connection safe on errors and close it normally after all samples.
qc_results <- tryCatch(
  lapply(seq_len(nrow(sample_manifest)), function(i) {
    filtered_path <- path(
      filtered_fastq_folder,
      paste0(sample_manifest$SampleID[[i]], "_filtered_Q", read_qv_cutoff, ".fastq.gz")
    )
    summarize_fastq(
      path = sample_manifest$FASTQ[[i]],
      sample_id = sample_manifest$SampleID[[i]],
      filtered_path = filtered_path,
      statistics_connection = statistics_connection
    )
  }),
  finally = close(statistics_connection)
)

sample_qc <- rbindlist(lapply(qc_results, `[[`, "summary"), use.names = TRUE)

# Restore pool metadata and deterministic sample order after streaming.
sample_qc <- merge(
  sample_manifest[, .(PoolNumber, SampleID)],
  sample_qc,
  by = "SampleID",
  all.x = TRUE,
  sort = FALSE
)
setorder(sample_qc, PoolNumber, SampleID)

# Confirm that each sample retained reads at Q20 and assess the broad expected
# length interval independently. Filtering is per read, not based on a sample's
# mean QV.
sample_qc[, QualityStatus := fifelse(
  PassingReads > 0,
  "PASS",
  "REVIEW: no reads passed the configured QV cutoff"
)]
sample_qc[, LengthStatus := fifelse(
  PercentInExpectedLengthRange >= 50,
  "PASS",
  "REVIEW: fewer than 50% of reads inside expected range"
)]
sample_qc[, OverallQCStatus := fifelse(
  QualityStatus == "PASS" & LengthStatus == "PASS",
  "PASS",
  "REVIEW"
)]
```

The report now confirms how many FASTQs were processed and how many
reads contribute to the complete distribution plots.

## Sample QC Summary

Display the primary per-sample QC metrics.

``` r
render_table(
  sample_qc[, .(
    PoolNumber,
    SampleID,
    TotalReads,
    MeanLength,
    MedianLength,
    MeanGCPercent,
    PercentInExpectedLengthRange,
    MeanReadQV,
    PassingReads,
    FilteredReads,
    PercentPassingQV,
    QualityStatus,
    LengthStatus,
    OverallQCStatus
  )],
  "PacBio HiFi sample quality summary",
  column_widths = c("80px", "140px", rep(NA_character_, 12))
)
```

## Paginated Distribution Plots

Both distributions count **all input reads before filtering**, with six
sample facets per PDF page (two columns by three rows). Each read-length
facet reports total reads and reads with length **1,800–2,000 bp
inclusive**. Each QV facet reports total reads and reads passing the QV
cutoff. Length bins are 20 bp wide; QV bins are 0.5 units wide.
Histograms use streamed frequency counts rather than raw observations or
a reread of the audit TSV. The 1,800–2,000 bp annotation is independent
of the configured length-review bounds and does not filter reads.

``` r
make_distribution_page <- function(page_rows, metric, page_number, page_count) {
  width <- if (metric == "length") length_histogram_bin_width else qv_histogram_bin_width
  page_data <- rbindlist(lapply(seq_len(nrow(page_rows)), function(i) {
    counts <- readRDS(page_rows$HistogramPath[[i]])[[metric]]
    counts[, SampleID := page_rows$SampleID[[i]]]
    counts[, Centre := (Value + 0.5) * width]
    counts
  }))
  page_data[, SampleID := factor(SampleID, levels = page_rows$SampleID)]
  labels <- copy(page_rows)
  labels[, SampleID := factor(SampleID, levels = page_rows$SampleID)]
  labels[, Annotation := if (metric == "length") paste0(
    "Total reads: ", format(TotalReads, big.mark = ",", scientific = FALSE, trim = TRUE),
    "\n", annotation_length_min, "-", annotation_length_max, " bp: ",
    format(ReadsInAnnotationRange, big.mark = ",", scientific = FALSE, trim = TRUE)
  ) else paste0(
    "Total reads: ", format(TotalReads, big.mark = ",", scientific = FALSE, trim = TRUE),
    "\nReads with Q >= ", read_qv_cutoff, ": ",
    format(PassingReads, big.mark = ",", scientific = FALSE, trim = TRUE)
  )]
  boundaries <- if (metric == "length") c(annotation_length_min, annotation_length_max) else read_qv_cutoff
  plot <- ggplot(page_data, aes(x = Centre, y = Count)) +
    geom_col(width = width, fill = "#2C7FB8", color = "white", linewidth = 0.1) +
    geom_vline(xintercept = boundaries, linetype = "dashed", color = "#C0392B") +
    geom_label(data = labels, fill = "white", linewidth = 0,
      aes(x = Inf, y = Inf, label = Annotation),
      inherit.aes = FALSE, hjust = 1.05, vjust = 1.2, size = 3.2) +
    facet_wrap(~ SampleID, ncol = 2, nrow = 3, scales = "free") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.25))) +
    labs(title = if (metric == "length") "PacBio HiFi read-length distributions" else "PacBio HiFi read-QV distributions",
      subtitle = paste0("All input reads - page ", page_number, " of ", page_count),
      x = if (metric == "length") "Read length (bp)" else "Read quality (QV)",
      y = "Number of reads") +
    theme_minimal(base_size = 11) + theme(strip.text = element_text(face = "bold"))
  plot
}

write_distribution_pdf <- function(metric, output_path) {
  page_count <- ceiling(nrow(sample_qc) / samples_per_plot_page)
  grDevices::pdf(output_path, width = 11, height = 11, onefile = TRUE, useDingbats = FALSE)
  on.exit(grDevices::dev.off(), add = TRUE)
  for (page_number in seq_len(page_count)) {
    rows <- seq.int((page_number - 1L) * samples_per_plot_page + 1L,
                   min(page_number * samples_per_plot_page, nrow(sample_qc)))
    print(make_distribution_page(sample_qc[rows], metric, page_number, page_count))
  }
  invisible(page_count)
}

show_distribution_pages <- function(metric) {
  page_count <- ceiling(nrow(sample_qc) / samples_per_plot_page)
  for (page_number in seq_len(page_count)) {
    rows <- seq.int((page_number - 1L) * samples_per_plot_page + 1L,
                   min(page_number * samples_per_plot_page, nrow(sample_qc)))
    print(make_distribution_page(sample_qc[rows], metric, page_number, page_count))
  }
}
```

### Read-Length Distribution

Dashed lines mark 1,800 and 2,000 bp. The final page can contain fewer
than six samples.

``` r
write_distribution_pdf("length", length_plot_path)
show_distribution_pages("length")
```

### Read-QV Distribution

The dashed line marks the QV filtering cutoff. Each QV facet shows total
reads and reads passing the QV cutoff. Length-range counts appear only
on the read-length plots.

``` r
write_distribution_pdf("quality", quality_plot_path)
show_distribution_pages("quality")
# Aggregate caches are no longer needed after both PDFs and inline figures exist.
unlink(sample_qc$HistogramPath)
```

------------------------------------------------------------------------

# Export Results

## Save QC Tables to Excel

Keep the complete per-read audit in `per_read_statistics.tsv.gz`. Create
a typed run summary and a complete per-sample QC table, write both with
the shared
[add_sheet_to_excel_function.R](../functions/add_sheet_to_excel_function.R)
helper, and document every exported column with
[build_column_dictionary_function.R](../functions/build_column_dictionary_function.R).

The report prints the completed workbook and compressed audit paths
after all result sheets, column definitions, and header comments have
been written.

## Final QC Decision

Confirm that every input produced a complete summary and every required
output file exists. A `REVIEW` status is not a processing failure
because the thresholds are descriptive review rules rather than filters.

``` r
# Structural completion is required even when one or more biological samples
# are flagged for review.
qc_complete <-
  nrow(sample_qc) == nrow(sample_manifest) &&
  all(sample_qc$TotalReads > 0) &&
  all(file_exists(sample_qc$FilteredFASTQ)) &&
  file_exists(workbook_path) &&
  file_exists(read_statistics_path) &&
  file_exists(length_plot_path) &&
  file_exists(quality_plot_path)

if (!qc_complete) {
  stop("Step 2 QC outputs are incomplete. Review the preceding diagnostics.")
}
```

After structural validation succeeds, this final status summarizes the
number of samples, reads passing Q ≥ 20, and samples flagged for
length-distribution review.

------------------------------------------------------------------------

# Output Files

The links below open the generated workbook, compressed per-read audit,
and standalone PDF plots.

# Output File Summary

The live tree below lists the actual contents of
[results/2_quality_filtered_reads/](../../results/2_quality_filtered_reads/)
so the report cannot drift from files on disk.

# Recommended Next Step

Review samples marked `REVIEW`, confirm that the expected length
interval and QV cutoff are appropriate, and use the Q20-filtered FASTQs
for the planned primer-removal notebook. The original input FASTQs
remain unchanged. Proceed to [Step 3 (Primer Trimming with
Cutadapt)](3_primer_trimming.md).

# Session Information

Record the exact R, platform, and package environment used to produce
the report.

# References

## Methods and Software

- Callahan BJ et al. (2019). High-throughput amplicon sequencing of the
  full-length 16S rRNA gene with single-nucleotide resolution. *Nucleic
  Acids Research*, 47(18):e103. [Full-length 16S
  method](https://doi.org/10.1093/nar/gkz569)
- Morgan M et al. (2009). ShortRead: a Bioconductor package for input,
  quality assessment and exploration of high-throughput sequence data.
  *Bioinformatics*, 25(19):2607–2608. [ShortRead
  publication](https://doi.org/10.1093/bioinformatics/btp450)
- Wickham H (2016). *ggplot2: Elegant Graphics for Data Analysis*.
  Springer-Verlag New York. [ggplot2
  documentation](https://ggplot2.tidyverse.org/)

## Documentation

- [Bioconductor ShortRead
  package](https://bioconductor.org/packages/release/bioc/html/ShortRead.html)
- [DADA2 full-length PacBio
  example](https://benjjneb.github.io/LRASManuscript/LRASms_fecal.html)
- [PacBio HiFi full-length 16S
  workflow](https://github.com/PacificBiosciences/HiFi-16S-workflow)
- [PacBio HiFi-16S pipeline
  overview](https://github.com/PacificBiosciences/HiFi-16S-workflow/blob/main/pipeline_overview.md)
- [SeqKit quality-statistics
  documentation](https://bioinf.shenwei.me/seqkit/usage/)
- [DT documentation](https://rstudio.github.io/DT/)
- [here package documentation](https://here.r-lib.org/)

## Related Project Files

- [Notebook 1 source](1_data_integrity_and_sample_mapping.Rmd)
- Original input FASTQs referenced by the Step 1 `SourceFASTQPath`
  column.
- [Step 1 audit
  workbook](../../results/1_data_integrity_and_sample_mapping/data_integrity_and_sample_mapping.xlsx)
- [Shared R functions](../functions/)

# Appendix: Troubleshooting Guide

## Step 1 Workbook or FASTQs Are Missing

Run [Step 1](1_data_integrity_and_sample_mapping.md) first and require
its final integrity decision to pass. Do not reconstruct sample
identities manually in Step 2.

## Mean Quality Values Look Unexpected

This notebook interprets FASTQ quality characters as Phred+33. It
converts each base Q score to error probability, averages those
probabilities within a read, and converts the result back to QV,
matching SeqKit’s documented method. Confirm the encoding of externally
supplied FASTQs before changing `quality_ascii_offset`.

## Read Lengths Fall Outside the Expected Range

Confirm that `expected_length_min` and `expected_length_max` match the
primer pair and target. A `REVIEW` flag does not remove reads; it
indicates that primer removal and downstream filtering choices deserve
inspection.

## Per-Read Audit for Large Runs

Every read is written to `per_read_statistics.tsv.gz` as it is
processed. The workbook contains summary tables and documents the audit
columns in `Column_Dictionary`. The audit has no Excel worksheet row
limit; opening the entire file in Excel still imposes Excel’s limit. Use
a streaming TSV reader for large audits.

## Large Runs and Memory Use

Reduce `stream_yield_size` if individual FASTQ chunks are too large for
available memory. Every read still contributes to filtering, summaries,
exact length quantiles, and both histograms. Only one sample’s frequency
counts are accumulated at a time; aggregate counts are cached on disk,
and plotting loads at most six samples per page. The per-read TSV is
written chunk by chunk and is never loaded to create plots or summaries,
even if it grows to 10 GB. Disk space for the audit and filtered FASTQs
is still required.
