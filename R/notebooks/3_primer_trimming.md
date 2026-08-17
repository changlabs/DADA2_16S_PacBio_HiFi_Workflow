Step 3: Primer Trimming with Cutadapt
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
  - [Define File Pattern Parameters](#define-patterns)
  - [Define Primer Sequences](#define-primers)
  - [Define Processing Parameters](#define-params)
- [Initialize Output Directories](#initialize-output-directories)
- [Define Helper Functions](#define-helper-functions)
  - [Sample ID Extraction](#func-sample-id)
  - [Primer Orientation Generator](#func-primer-orientations)
  - [Anchored Primer-Hit Counter](#func-primer-hits)
- [Discover FASTQ Files](#discover-fastq-files)
  - [List Input Files](#list-files)
  - [Validate One FASTQ per Sample](#validate-pairing)
- [Generate Primer Orientations](#generate-primer-orientations)
- [Count Primers Before Trimming](#count-before)
- [Run Cutadapt](#run-cutadapt)
  - [Verify Cutadapt Installation](#verify-cutadapt)
  - [Execute Primer Trimming](#execute-primer-trimming)
- [Count Primers After Trimming](#count-after)
  - [Build Combined Before/After Primer-Hit Table](#primer-hit-table)
- [Export Results](#export-results)
  - [Save to Excel](#save-excel)
  - [Document and Export Column Dictionary](#column-dictionary)
- [Output File Summary](#output-file-summary)
- [Recommended Next Step](#recommended-next-step)
- [Session Information](#session-information)
- [References](#references)
  - [Methods](#methods)
  - [Related](#related)
- [Appendix: Troubleshooting Guide](#appendix-troubleshooting-guide)
  - [Common Issues and Solutions](#common-issues-and-solutions)
    - [Cutadapt Not Found](#cutadapt-not-found)
    - [Primers Still Present After
      Trimming](#primers-still-present-after-trimming)
    - [Low or Zero Primer Counts Even Before
      Trimming](#low-or-zero-primer-counts-even-before-trimming)
    - [Memory Issues](#memory-issues)
  - [Understanding the Output](#understanding-the-output)
    - [Which `Primer_Hit_Counts` values
      matter](#which-primer_hit_counts-values-matter)
    - [A note on exact matching](#a-note-on-exact-matching)

<style type="text/css">
/* Custom styling for improved readability */
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
&#10;table, th, td { text-align: left !important; }
th, .dataTables_wrapper table.dataTable thead th {
  white-space: nowrap !important;
  word-break: normal !important;
}
td, .dataTables_wrapper table.dataTable td {
  white-space: normal !important;
  overflow-wrap: anywhere;
  word-break: break-word;
}
.dataTables_scrollBody, .dataTables_scrollHead { overflow-x: auto !important; }
&#10;/* Style for primer sequence display */
.primer-seq {
  font-family: monospace;
  background-color: #f0f0f0;
  padding: 2px 6px;
  border-radius: 3px;
  font-size: 14px;
}
</style>

# Introduction

## Purpose

This notebook is **Step 3** of the PacBio HiFi full-length 16S pipeline.
[Step 1](1_data_integrity_and_sample_mapping.md) mapped each
demultiplexed barcode-pair FASTQ to its stable sample identity, and
[Step 2](2_quality_filtering.md) retained reads with mean Q ≥ 20. This
step uses [Cutadapt](https://cutadapt.readthedocs.io/) to identify the
complete linked forward–reverse primer structure, remove both primers,
and orient every retained amplicon consistently. The default F27–R1492
primer pair can be changed in [Define Primer Sequences](#define-primers)
for another full-length 16S assay. The before/after primer counts and
Cutadapt logs provide an auditable record of what was recognized,
retained, reoriented, and trimmed.

Primer sequences must be removed before downstream analysis because:

- **Primers are not biological sequences**: They are synthetic
  oligonucleotides added during PCR
- **They introduce bias**: Primers can inflate sequence similarity
  scores
- **[DADA2](https://benjjneb.github.io/dada2/) requires primer-free
  reads**: its error model works best on amplicon sequences only
- **Taxonomic assignment accuracy**: Primers can interfere with database
  matching

## Prerequisites

Before running this notebook, ensure that:

1.  Q ≥ 20 FASTQ files are present in
    [results/2_quality_filtered_reads/Q20_filtered_fastq/](../../results/2_quality_filtered_reads/Q20_filtered_fastq/)
2.  **Cutadapt** is installed in the project-local
    [tools/cutadapt/](../../tools/cutadapt/) environment using the
    [setup/install_required_tools.R](../../setup/install_required_tools.R)
    script
3.  **[Step 1 (Data Integrity and Sample
    Mapping)](1_data_integrity_and_sample_mapping.md)** has completed
    successfully
4.  **[Step 2 (Quality Filtering)](2_quality_filtering.md)** has
    completed successfully

## What This Notebook Does

1.  **Discovers FASTQ Files**: Scans the [Step 2 (Quality
    Filtering)](2_quality_filtering.md) Q20-filtered directory for one
    single-end HiFi FASTQ per sample
2.  **Counts Primers Before Trimming**: Uses a custom, anchored search
    to count, for every sample, primer, and sequence orientation, how
    many reads carry a primer at a read end
3.  **Runs Cutadapt**: Requires the linked primer pair (e.g. F27–R1492),
    trims both primers, and orients every retained read consistently
4.  **Counts Primers After Trimming**: Repeats the anchored count on the
    trimmed reads, so before/after and the number removed are directly
    comparable per sample
5.  **Exports Results**: Saves the primer-hit table to an Excel workbook

## Expected Input

- **Location**:
  [results/2_quality_filtered_reads/Q20_filtered_fastq/](../../results/2_quality_filtered_reads/Q20_filtered_fastq/)
- **Naming Convention**: `{SampleID}_filtered_Q20.fastq`
- **Format**: One uncompressed, single-end FASTQ per sample, using
  standard four-line FASTQ records

## Expected Output

- Primer-trimmed, consistently oriented reads in
  [results/3_primer_trimming/primer_trimmed_reads/](../../results/3_primer_trimming/primer_trimmed_reads/)
- Cutadapt log files for each sample in
  [results/3_primer_trimming/cutadapt_logs/](../../results/3_primer_trimming/cutadapt_logs/)
- Summary Excel workbook
  [primer_trimming_summary.xlsx](../../results/3_primer_trimming/primer_trimming_summary.xlsx)

<div class="alert alert-warning">

**Downstream note**: The FASTQ files in
[primer_trimmed_reads/](../../results/3_primer_trimming/primer_trimmed_reads/)
are Q20-filtered, primer-trimmed, and consistently oriented. DADA2 will
subsequently apply its own length, N, and expected-error filters in
[Step 5](5_dada2_pipeline.md).

</div>

------------------------------------------------------------------------

# Environment Setup

## Load Required Packages

The chunk below loads every R package this notebook depends on, plus
four helper functions shared across the whole pipeline: Excel writing,
column-dictionary documentation, and clickable output links (each
sourced from [R/functions/](../functions/)).

``` r
# Biostrings: Biological string manipulation (Bioconductor)
# Provides functions for handling DNA/RNA sequences, generating orientations,
# and pattern counting (vcountPattern) for the custom primer-hit counter
library(Biostrings)

# data.table: High-performance data manipulation
# Provides fast operations for handling large result tables
library(data.table)

# DT: Interactive tables in R Markdown
# Creates searchable, sortable HTML tables
library(DT)

# fs: Cross-platform filesystem operations
# Consistent functions for file and directory manipulation
library(fs)

# here: Project-relative file paths
# Enables reproducible path construction regardless of working directory
library(here)

# openxlsx: Excel file creation and manipulation
# Read and write Excel files without Java dependencies
library(openxlsx)

# parallel: Parallel processing support
# Built-in R package for multi-core processing
library(parallel)

# ShortRead: FASTQ file handling (Bioconductor)
# Efficient tools for reading and counting FASTQ files
library(ShortRead)

# stringr: Consistent string manipulation
# Intuitive string processing functions
library(stringr)

# Source our custom Excel utility function from the project's function library
# This function handles creating or appending sheets to Excel workbooks
source(here("R", "functions", "add_sheet_to_excel_function.R"))

# Source our custom column-dictionary builder from the project's function library
# This function documents every column of a sheet being exported to Excel
source(here("R", "functions", "build_column_dictionary_function.R"))

# Source our custom output-links helper from the project's function library
# This function renders clickable Markdown links to this notebook's output files
source(here("R", "functions", "render_output_links_function.R"))

# Source the custom render_output_tree utility function from the project's
# function library. This function prints this notebook's entire output
# folder as a clickable directory tree (used in "Output File Summary" below),
# scanned live from disk at knit time so it always matches what was actually
# produced on this run.
source(here("R", "functions", "render_output_tree_function.R"))
```

------------------------------------------------------------------------

# Configuration

## Define Path Parameters

Set up the input and output directory paths. Using `here()` ensures
paths are relative to the [project root](../../), making the script
portable across different systems.

``` r
# Input folder containing the Q20-filtered FASTQ files written by Step 2.
fastq_input_folder <- here("results", "2_quality_filtered_reads", "Q20_filtered_fastq")

# Base results folder for all pipeline outputs
results_folder <- here("results")

# Step 2 workbook carrying the authoritative SampleID-to-PoolNumber mapping.
# PoolNumber is deliberately read as metadata rather than parsed from SampleID.
quality_workbook_path <- here(
  results_folder,
  "2_quality_filtered_reads",
  "quality_and_read_length_summary.xlsx"
)

# Specific output folder for this step (Step 3: Primer Trimming)
output_folder <- here(results_folder, "3_primer_trimming")

# Output folder for the primer-trimmed reads. This is the final output of this
# step and the input the subsequent PacBio DADA2 filtering step consumes.
primer_trimmed_folder <- here(output_folder, "primer_trimmed_reads")

# Folder for cutadapt log files (the human-readable record of what cutadapt did)
log_folder <- here(output_folder, "cutadapt_logs")

# Output Excel filename for primer trimming statistics
output_excel_filename <- "primer_trimming_summary.xlsx"

# Construct the full path to the output Excel file
output_excel_path <- here(output_folder, output_excel_filename)
```

## Define File Pattern Parameters

Configure the file naming pattern used to identify the single-end,
Q20-filtered HiFi reads written by [Step 2](2_quality_filtering.md).

``` r
# Match the uncompressed Q20 FASTQs written by Step 2. Removing this processing
# suffix recovers the complete biological SampleID; PoolNumber is stored only
# in the Step 2 workbook and is not encoded in the identifier or filename.
fastq_pattern <- "(?i)_filtered_Q20\\.(fastq|fq)$"

# Display configuration
cat("File Pattern Configuration:\n",
    "- PacBio HiFi reads pattern:", fastq_pattern, "\n")
```

## Define Primer Sequences

Specify the primer sequences used for 16S amplicon generation. These
primers will be trimmed from the reads.

<div class="alert alert-warning">

**Important**: Update these sequences if a different primer pair was
used. The defaults for this workflow are PacBio’s F27 and R1492
full-length 16S primers.

</div>

``` r
# PacBio F27 forward primer (5' -> 3').
forward_primer <- "AGRGTTYGATYMTGGCTCAG"

# PacBio R1492 reverse primer (5' -> 3').
reverse_primer <- "AAGTCGTAACAAGGTARCY"

# Reverse complements are retained for the before/after diagnostic table and
# to explain the random orientations present in PacBio CCS input reads.
fwd_primer_rc <- as.character(reverseComplement(DNAString(forward_primer)))
rev_primer_rc <- as.character(reverseComplement(DNAString(reverse_primer)))

# Display primer information
cat("Primer Configuration:\n",
    "- Forward primer (5'->3'):", forward_primer, "\n",
    "- Reverse primer (5'->3'):", reverse_primer, "\n",
    "- Forward primer length:", nchar(forward_primer), "bp\n",
    "- Reverse primer length:", nchar(reverse_primer), "bp\n",
    "- Forward primer reverse complement:", fwd_primer_rc, "\n",
    "- Reverse primer reverse complement:", rev_primer_rc, "\n")
```

## Define Processing Parameters

Configure parameters for parallel processing, primer counting, and
cutadapt execution.

``` r
# Determine the number of CPU threads for parallel processing
# Reserve 2 cores for system operations to maintain responsiveness
detected_cores <- suppressWarnings(detectCores())
available_cores <- if (length(detected_cores) == 1L && is.finite(detected_cores) && detected_cores >= 1) as.integer(detected_cores) else 1L
nr_threads <- max(1L, available_cores - 2L)

# Anchor buffer (bp) for the custom primer-hit counter. A read counts as a hit
# only if a primer orientation is found within the first or last
# (primer_length + primer_anchor_buffer) bases. Kept deliberately small (2 bp)
# so the window is precise -- just wide enough to tolerate a minor positional
# offset (e.g. a stray leading base in some library preps) without letting the
# search drift inward and pick up coincidental interior matches of the
# degenerate primer. Raise to a slightly larger value only if primers are known
# to sit several bases from the read end.
primer_anchor_buffer <- 2L

# Number of reads loaded from each FASTQ at a time while counting primer hits.
# This bounds memory use independently of total file size.
fastq_chunk_size <- 100000L

# Path to the project-local Cutadapt executable
cutadapt_path <- here("tools", "cutadapt", "venv", "bin", "cutadapt")

if (!dir_exists(fastq_input_folder)) {
  stop("Raw FASTQ input folder not found: ", fastq_input_folder,
       "\nComplete Step 2 and verify the project paths before running Step 3.")
}
if (!file_exists(cutadapt_path) || file.access(cutadapt_path, mode = 1) != 0) {
  stop("Cutadapt executable not found or not executable: ", cutadapt_path,
       "\nRun Rscript setup/install_required_tools.R from the project root.")
}

# Verify that the executable can actually start. Merely checking the executable
# bit is insufficient for a copied Python virtual environment because its
# launcher can retain an absolute interpreter path from another machine.
cutadapt_version_log <- tempfile("cutadapt-version-", fileext = ".log")
cutadapt_version_status <- system2(
  cutadapt_path,
  args = "--version",
  stdout = cutadapt_version_log,
  stderr = cutadapt_version_log
)
cutadapt_version <- readLines(cutadapt_version_log, warn = FALSE)
unlink(cutadapt_version_log)
if (!identical(cutadapt_version_status, 0L)) {
  stop("Cutadapt could not be started (exit status ", cutadapt_version_status, "): ",
       paste(cutadapt_version, collapse = "\n"),
       "\nRecreate the project-local tool with Rscript setup/install_required_tools.R.")
}

# Display configuration
cat("Processing Configuration:\n",
    "- Available CPU cores:", available_cores, "\n",
    "- Threads for processing:", nr_threads, "\n",
    "- Primer anchor buffer (bp):", primer_anchor_buffer, "\n",
    "- FASTQ counting chunk size:", fastq_chunk_size, "reads\n",
    "- Cutadapt path:", cutadapt_path, "\n")
```

------------------------------------------------------------------------

# Initialize Output Directories

Create the output folder structure for primer trimming results.

``` r
# Create output directories if they don't exist
# Using fs::dir_create which is safe to run multiple times

# Main results folder
if (!dir_exists(results_folder)) {
  dir_create(results_folder, recurse = TRUE)
  cat("Created results directory:", results_folder, "\n")
}

# Step 3 output folder
if (!dir_exists(output_folder)) {
  dir_create(output_folder, recurse = TRUE)
  cat("Created output directory:", output_folder, "\n")
} else {
  cat("Using existing output directory:", output_folder, "\n")
}
```

------------------------------------------------------------------------

# Define Helper Functions

## Sample ID Extraction

This function extracts the sample identifier from a FASTQ filename.

``` r
# Extract Sample ID from FASTQ Filename
#
# Parses a FASTQ filename and returns the sample identifier portion.
# Preserves the complete Step 2 biological sample identifier.
#
# Arguments:
#   filename - Character string of the filename (without path)
#   pattern  - The Step 2 suffix pattern to remove as a regular expression
# Returns:
#   Character string containing the sample ID
#
# Example:
#   extract_sample_id("Sample01_filtered_Q20.fastq", fastq_pattern)
#   # Returns "Sample01"
extract_sample_id <- function(filename, pattern) {
  # Remove the pattern from the filename. `pattern` is matched as a
  # regular expression here (NOT fixed()/literal matching) since
  # fastq_pattern is a regular expression anchored to the filename suffix.
  sample_name <- str_remove(filename, pattern)
  return(sample_name)
}
```

## Primer Orientation Generator

This function generates all four orientations of a primer sequence
(Forward, Complement, Reverse, ReverseComplement). Counting all four
preserves the standard DADA2 sanity check while accommodating randomly
oriented PacBio CCS reads: Forward and ReverseComplement have a
biological mechanism, whereas Complement and Reverse do not.

``` r
# Generate All Primer Orientations
#
# Creates all four possible orientations of a DNA primer sequence, returned as
# a named character vector so downstream tables can label each orientation.
#
# Arguments:
#   primer - Character string of the primer sequence (5' -> 3')
# Returns:
#   Named character vector: Forward, Complement, Reverse, ReverseComplement
get_primer_orientations <- function(primer) {
  dna_seq <- DNAString(primer)
  c(
    Forward           = as.character(dna_seq),
    Complement        = as.character(complement(dna_seq)),
    Reverse           = as.character(reverse(dna_seq)),
    ReverseComplement = as.character(reverseComplement(dna_seq))
  )
}
```

## Anchored Primer-Hit Counter

This function counts how many reads carry a given primer orientation at
a read **end**, honoring IUPAC ambiguity codes but requiring an exact
(zero-mismatch) match.

<div class="alert alert-info">

**Note on the Custom Primer Counter (anchored matching)**: The
before/after primer counts in this notebook are produced by a custom R
search built on `Biostrings::vcountPattern()`.

- The search is **anchored to the read ends**: a read only counts as a
  hit if the primer orientation is found within the first or last
  `primer_length + primer_anchor_buffer` bases, where full-length
  amplicon primers occur.

- A small buffer (default **2 bp**) allows for minor positional offsets
  – for example a stray leading base before the primer – without opening
  the search up to the coincidental *interior* matches of a short,
  IUPAC-degenerate primer that made earlier whole-read counts fail to
  drop to zero after trimming.

- Matching is **exact** (IUPAC-aware but zero-mismatch), so a read whose
  primer region carries a sequencing error may not be counted; these
  counts are therefore a conservative lower bound.

- The cutadapt log files (`cutadapt_logs/`) hold cutadapt’s own
  error-tolerant tally if needed.

</div>

``` r
# Count Reads with a Primer Orientation at Either Read End
#
# For a single already-loaded set of reads (a DNAStringSet), counts how many
# reads contain `orientation_seq` within the first or last
# (nchar(orientation_seq) + anchor_buffer) bases. IUPAC codes in the query are
# honored (fixed = FALSE); matching is exact (no mismatches), so counts are a
# conservative lower bound relative to cutadapt's error-tolerant matching.
#
# Arguments:
#   reads           - DNAStringSet from one streamed FASTQ chunk
#   read_widths     - Integer vector of read lengths (width(reads)); passed in
#                      so it is computed once per file rather than once per
#                      orientation
#   orientation_seq - Character string: the primer orientation to search for
#   anchor_buffer   - Integer buffer (bp) added to the primer length to define
#                      the 5' and 3' search windows
# Returns:
#   Integer count of reads with at least one anchored hit
count_anchored_orientation_hits <- function(reads, read_widths, orientation_seq, anchor_buffer) {
  primer_len  <- nchar(orientation_seq)
  window_len  <- primer_len + anchor_buffer

  # 5' window: bases 1 .. min(window_len, read_width)
  five_prime_window <- subseq(reads,
                              start = 1L,
                              end   = pmin(window_len, read_widths))

  # 3' window: last window_len bases, floored at base 1
  three_prime_window <- subseq(reads,
                               start = pmax(1L, read_widths - window_len + 1L),
                               end   = read_widths)

  # A read is a hit if the orientation is found in either anchored window
  hits_5 <- vcountPattern(orientation_seq, five_prime_window, fixed = FALSE) > 0
  hits_3 <- vcountPattern(orientation_seq, three_prime_window, fixed = FALSE) > 0
  sum(hits_5 | hits_3)
}

# Count Primer Hits in One FASTQ File (long format)
#
# Streams bounded chunks rather than loading the complete file into memory.
count_fastq_primer_hits <- function(fastq_path, primer_specs, read_label,
                                    sample_id, anchor_buffer, chunk_size) {
  hit_totals <- setNames(
    integer(sum(lengths(primer_specs))),
    unlist(lapply(names(primer_specs), function(primer_label) {
      paste(primer_label, names(primer_specs[[primer_label]]), sep = "::")
    }), use.names = FALSE)
  )

  streamer <- FastqStreamer(fastq_path, n = chunk_size)
  on.exit(close(streamer), add = TRUE)

  repeat {
    fastq_chunk <- yield(streamer)
    if (length(fastq_chunk) == 0L) break
    reads <- sread(fastq_chunk)
    read_widths <- width(reads)

    for (primer_label in names(primer_specs)) {
      for (orientation_label in names(primer_specs[[primer_label]])) {
        key <- paste(primer_label, orientation_label, sep = "::")
        hit_totals[[key]] <- hit_totals[[key]] + count_anchored_orientation_hits(
          reads, read_widths, primer_specs[[primer_label]][[orientation_label]], anchor_buffer
        )
      }
    }
  }

  rbindlist(lapply(names(hit_totals), function(key) {
    key_parts <- str_split_fixed(key, fixed("::"), 2L)
    data.table(
      SampleID = sample_id,
      Primer = key_parts[1L],
      Read_File = read_label,
      Orientation = key_parts[2L],
      Hits = unname(hit_totals[[key]])
    )
  }))
}

# Count Primer Hits Across All Samples (long format)
#
# Builds a tidy per-sample / per-primer / per-orientation table
# of anchored primer-hit counts. Each FASTQ file is read exactly once; all
# primer/orientation counts for that file reuse the loaded reads.
#
# Arguments:
#   read_paths                     - Character vector of single-end HiFi FASTQs
#   sample_ids                     - Character vector of sample identifiers
#                                     (aligned with read_paths)
#   fwd_orientations, rev_orientations - Named character vectors from
#                                     get_primer_orientations() for the
#                                     forward and reverse primer
#   anchor_buffer                  - Integer buffer passed to the anchored
#                                     counter
#   n_threads                      - Number of cores for mclapply
#   chunk_size                     - Maximum reads held per FASTQ stream chunk
# Returns:
#   data.table with columns SampleID, Primer, Read_File, Orientation, Hits
count_primer_hits_long <- function(read_paths, sample_ids,
                                   fwd_orientations, rev_orientations,
                                   anchor_buffer, n_threads, chunk_size) {
  per_sample <- mclapply(seq_along(sample_ids), function(i) {
    primer_specs <- list(FWD = fwd_orientations, REV = rev_orientations)
    count_fastq_primer_hits(
      read_paths[i], primer_specs, "HiFi", sample_ids[i],
      anchor_buffer, chunk_size
    )
  }, mc.cores = if (.Platform$OS.type == "windows") 1L else n_threads)

  rbindlist(per_sample)
}
```

------------------------------------------------------------------------

# Discover FASTQ Files

## List Input Files

Scan the [Step 2 output
directory](../../results/2_quality_filtered_reads/Q20_filtered_fastq/)
for single-end PacBio HiFi FASTQ files.

``` r
# Discover and sort the Q20-filtered FASTQs for deterministic processing.
raw_paths <- sort(dir_ls(
  path = fastq_input_folder,
  regexp = fastq_pattern
))

# Recover the complete sample identifiers from the Step 2 filenames.
sample_names <- sapply(
  basename(raw_paths),
  extract_sample_id,
  pattern = fastq_pattern,
  USE.NAMES = FALSE
)

# Display discovery results
cat("File Discovery Results:\n",
    "- Input directory:", fastq_input_folder, "\n",
    "- HiFi FASTQ files found:", length(raw_paths), "\n",
    "- Samples identified:", length(sample_names), "\n")
```

## Validate One FASTQ per Sample

Verify that the input contains exactly one non-empty FASTQ for every
unique sample identifier.

``` r
if (length(raw_paths) == 0L) {
  stop("No Q20-filtered FASTQ files matched in: ", fastq_input_folder,
       "\nPattern: ", fastq_pattern)
}
if (anyDuplicated(sample_names)) {
  stop("Sample IDs are not unique after removing the Step 2 suffix: ",
       paste(unique(sample_names[duplicated(sample_names)]), collapse = ", "))
}
if (any(file_size(raw_paths) == 0)) stop("One or more Step 2 FASTQ files are empty.")
if (!file_exists(quality_workbook_path)) {
  stop("Step 2 quality workbook does not exist: ", quality_workbook_path)
}

# Read the authoritative pool metadata from Step 2. This keeps SampleID and
# PoolNumber independent while preserving pool provenance in Step 3 results.
sample_pool_map <- as.data.table(read.xlsx(
  quality_workbook_path,
  sheet = "Sample_QC",
  cols = c(1, 2)
))
setnames(sample_pool_map, c("PoolNumber", "SampleID"))
sample_pool_map[, `:=`(
  PoolNumber = as.integer(PoolNumber),
  SampleID = as.character(SampleID)
)]

if (anyDuplicated(sample_pool_map$SampleID)) {
  stop("Step 2 Sample_QC contains duplicate SampleIDs.")
}
if (!setequal(sample_names, sample_pool_map$SampleID)) {
  stop("Step 2 FASTQ filenames and Sample_QC identifiers do not match exactly.")
}
sample_pool_map <- sample_pool_map[match(sample_names, SampleID)]

# Create sample inventory table
sample_inventory <- data.table(
  PoolNumber = sample_pool_map$PoolNumber,
  SampleID = sample_names,
  InputFASTQ = basename(raw_paths),
  InputSizeMB = round(as.numeric(file_size(raw_paths)) / 1024^2, 3)
)

# Display sample inventory
cat("Sample Inventory:\n",
    "- Total samples:", length(sample_names), "\n")
```

The complete input inventory is displayed below so each Q20-filtered
filename, sample identifier, and file size can be checked before
Cutadapt is run.

------------------------------------------------------------------------

# Generate Primer Orientations

Create all four orientations of the forward and reverse primers, which
the anchored counter searches for in each HiFi read file.

``` r
fwd_primer_orientations <- get_primer_orientations(forward_primer)
rev_primer_orientations <- get_primer_orientations(reverse_primer)

primer_orientation_table <- data.table(
  Orientation    = names(fwd_primer_orientations),
  Forward_Primer = unname(fwd_primer_orientations),
  Reverse_Primer = unname(rev_primer_orientations)
)

cat("Primer orientations generated (searched for at read ends):\n\n")
```

This table shows the exact forward and reverse primer strings searched
in each orientation. It is a useful configuration check before reading
all FASTQ records.

------------------------------------------------------------------------

# Count Primers Before Trimming

Count primer occurrences at the read ends of the **Q20-filtered** reads,
for every sample, primer, and orientation. This establishes the baseline
that the after-trimming counts are compared against.

<div class="alert alert-info">

**Note**: This step reads every Q20-filtered FASTQ file once. It may
take several minutes for large datasets.

</div>

The following status message marks the beginning of the pre-trimming
primer scan in the rendered report.

The computation below streams each FASTQ in bounded chunks and counts
exact primer-orientation matches only near read ends, producing the full
pre-trimming baseline table.

``` r
primer_hits_before_dt <- count_primer_hits_long(
  read_paths       = raw_paths,
  sample_ids       = sample_names,
  fwd_orientations = fwd_primer_orientations,
  rev_orientations = rev_primer_orientations,
  anchor_buffer    = primer_anchor_buffer,
  n_threads        = nr_threads,
  chunk_size       = fastq_chunk_size
)

cat("Pre-trimming primer counting complete (",
    nrow(primer_hits_before_dt), "rows ).\n")
```

------------------------------------------------------------------------

# Run Cutadapt

## Verify Cutadapt Installation

Check that Cutadapt is available and display its version.

``` r
cat("Cutadapt Configuration:\n",
    "- Path:", cutadapt_path, "\n",
    "- Version:", cutadapt_version, "\n")
```

## Execute Primer Trimming

Run Cutadapt on each already-demultiplexed sample FASTQ to require and
remove the linked primer pair. The `--revcomp` option detects
reverse-oriented CCS reads, reverse-complements them, and writes all
retained sequences in the forward-primer orientation. This is primer
trimming and orientation—not sample demultiplexing. The results are
written to
[primer_trimmed_reads/](../../results/3_primer_trimming/primer_trimmed_reads/).

<div class="alert alert-info">

**Note**: Cutadapt is run with the following settings:

- `-g F27...R1492`: Require the linked full-length primer pair and
  remove both primers
- `--trimmed-only`: Retain only reads in which the linked primer pair is
  found
- `--revcomp`: also search the reverse complement and orient retained
  reads consistently
- `-e 0.1`: allow Cutadapt’s default maximum error rate of 10% in primer
  matching
- `--cores N`: use the configured thread limit while reserving two cores
  when available

</div>

``` r
# Write this run into an isolated staging tree. The final folders consumed by
# downstream steps are replaced only after every Cutadapt command succeeds.
staging_folder <- fs::path(
  output_folder,
  paste0(".cutadapt-staging-", format(Sys.time(), "%Y%m%d%H%M%S"), "-", Sys.getpid())
)
staging_trimmed_folder <- fs::path(staging_folder, "primer_trimmed_reads")
staging_log_folder <- fs::path(staging_folder, "cutadapt_logs")
dir_create(staging_trimmed_folder, recurse = TRUE)
dir_create(staging_log_folder, recurse = TRUE)

# Define one uncompressed, primer-trimmed FASTQ output per sample.
staging_paths <- fs::path(staging_trimmed_folder, paste0(sample_names, "_primer_trimmed.fastq"))

cat("Running Cutadapt for primer trimming...\n",
    "Processing", length(sample_names), "samples.\n\n")

# Run cutadapt for each sample
for (i in seq_along(sample_names)) {

  cat("Processing sample", i, "of", length(sample_names), ":", sample_names[i], "\n")

  # Define log file path
  log_file <- fs::path(staging_log_folder, paste0(sample_names[i], "_cutadapt.log"))

  # Build cutadapt command arguments
  cutadapt_args <- c(
    # PacBio's official HiFi-16S workflow uses a linked adapter expression and
    # --revcomp to recognize either CCS orientation and normalize it.
    "-g", shQuote(paste0(forward_primer, "...", reverse_primer)),
    "--trimmed-only",
    "--revcomp",
    "-e", "0.1",

    # Respect the same bounded thread setting reported above.
    paste0("--cores=", nr_threads),

    # Output files
    "-o", shQuote(as.character(staging_paths[i])),

    # Q20-filtered input FASTQ from Step 2.
    shQuote(as.character(raw_paths[i]))
  )

  # Execute cutadapt and capture output
  result <- system2(
    cutadapt_path,
    args = cutadapt_args,
    stdout = log_file,
    stderr = log_file
  )

  # Check for errors
  if (result != 0 || !file_exists(staging_paths[i]) || file_size(staging_paths[i]) == 0) {
    stop("Cutadapt failed for sample ", sample_names[i],
         " (exit code ", result, "). See log: ", log_file)
  }
}

# Publish the complete run as one dataset only after every sample succeeded.
# Preserve the previous run inside staging until both replacements succeed so a
# filesystem error during publication can roll back to the complete old run.
previous_trimmed_backup <- fs::path(output_folder, ".previous_primer_trimmed_reads")
previous_log_backup <- fs::path(output_folder, ".previous_cutadapt_logs")
# Remove only stale backups owned by this notebook; current published outputs
# are preserved until all new sample commands have succeeded.
if (dir_exists(previous_trimmed_backup)) dir_delete(previous_trimmed_backup)
if (dir_exists(previous_log_backup)) dir_delete(previous_log_backup)
tryCatch({
  if (dir_exists(primer_trimmed_folder)) file_move(primer_trimmed_folder, previous_trimmed_backup)
  if (dir_exists(log_folder)) file_move(log_folder, previous_log_backup)
  file_move(staging_trimmed_folder, primer_trimmed_folder)
  file_move(staging_log_folder, log_folder)
}, error = function(e) {
  if (dir_exists(primer_trimmed_folder)) dir_delete(primer_trimmed_folder)
  if (dir_exists(log_folder)) dir_delete(log_folder)
  if (dir_exists(previous_trimmed_backup)) file_move(previous_trimmed_backup, primer_trimmed_folder)
  if (dir_exists(previous_log_backup)) file_move(previous_log_backup, log_folder)
  stop("Could not publish the completed Cutadapt run; the previous output was restored: ",
       conditionMessage(e))
})
# Delete the previous complete run only after both new output directories have
# been published successfully.
if (dir_exists(previous_trimmed_backup)) dir_delete(previous_trimmed_backup)
if (dir_exists(previous_log_backup)) dir_delete(previous_log_backup)
dir_delete(staging_folder)

trimmed_paths <- fs::path(primer_trimmed_folder, basename(staging_paths))
```

After every sample completes successfully, the report confirms the
published Cutadapt logs and provides a clickable link to their folder.

------------------------------------------------------------------------

# Count Primers After Trimming

Repeat the anchored count on the **cutadapt-trimmed** reads. Comparing
these to the pre-trimming counts shows how many primer-bearing reads
were cleaned per sample, primer, and orientation.

The next status line separates the post-trimming primer scan from the
Cutadapt execution log above.

The same anchored counter is now applied to the published primer-trimmed
FASTQs, making the before/after comparison directly comparable.

``` r
primer_hits_after_dt <- count_primer_hits_long(
  read_paths       = trimmed_paths,
  sample_ids       = sample_names,
  fwd_orientations = fwd_primer_orientations,
  rev_orientations = rev_primer_orientations,
  anchor_buffer    = primer_anchor_buffer,
  n_threads        = nr_threads,
  chunk_size       = fastq_chunk_size
)

cat("Post-trimming primer counting complete (",
    nrow(primer_hits_after_dt), "rows ).\n")
```

## Build Combined Before/After Primer-Hit Table

Merge the before and after counts into one tidy table, adding the number
of primer-bearing reads removed for each combination.

``` r
# Merge on the four identifying keys; rename the Hits columns to Before/After
primer_hit_counts_dt <- merge(
  setnames(copy(primer_hits_before_dt), "Hits", "Hits_Before"),
  setnames(copy(primer_hits_after_dt),  "Hits", "Hits_After"),
  by = c("SampleID", "Primer", "Read_File", "Orientation")
)

# Reads that carried a primer before but not after
primer_hit_counts_dt[, Hits_Removed := Hits_Before - Hits_After]

# Percentage of primer-bearing reads removed, relative to the pre-trimming
# count for that same sample/primer/read-file/orientation. When Hits_Before is
# 0 there was nothing to remove, so the percentage is undefined (0/0) and is
# reported as NA rather than NaN.
primer_hit_counts_dt[, Pct_Removed := fifelse(
  Hits_Before > 0, round(100 * Hits_Removed / Hits_Before, 2), NA_real_
)]

# Order rows so each sample's block reads FWD-then-REV in the canonical
# orientation order.
primer_hit_counts_dt[, Orientation := factor(
  Orientation, levels = c("Forward", "Complement", "Reverse", "ReverseComplement")
)]
setorder(primer_hit_counts_dt, SampleID, Primer, Read_File, Orientation)
primer_hit_counts_dt[, Orientation := as.character(Orientation)]

# Forward and reverse-complement primer orientations are both expected before
# trimming because unaligned PacBio CCS reads can arrive in either orientation.
meaningful_combos <- rbind(
  data.table(Primer = "FWD", Read_File = "HiFi", Orientation = "Forward"),
  data.table(Primer = "REV", Read_File = "HiFi", Orientation = "Forward"),
  data.table(Primer = "FWD", Read_File = "HiFi", Orientation = "ReverseComplement"),
  data.table(Primer = "REV", Read_File = "HiFi", Orientation = "ReverseComplement")
)
# Flag which rows are biologically expected in randomly oriented CCS reads
# versus orientations with no expected mechanism.
# meaningful_combos (above) lists orientations with a real mechanism;
# every other row is a contaminant/artefact sanity-net cell.
primer_hit_counts_dt[, Biological_Relevance := "Contaminant / other"]
primer_hit_counts_dt[meaningful_combos, on = c("Primer", "Read_File", "Orientation"),
                     Biological_Relevance := "Biologically relevant"]
setcolorder(primer_hit_counts_dt,
            c("SampleID", "Primer", "Read_File", "Orientation", "Biological_Relevance"))

meaningful_totals <- merge(primer_hit_counts_dt, meaningful_combos,
                           by = c("Primer", "Read_File", "Orientation"))[
  , .(Hits_Before = sum(Hits_Before), Hits_After = sum(Hits_After)),
  by = .(Primer, Read_File, Orientation)]

# Read_File is an internal label used while combining the before/after counts.
# Every row describes the same single-end HiFi read type, so retaining this
# constant column in the report and workbook would add no information.
primer_hit_counts_dt[, Read_File := NULL]

cat("\nPRIMER HITS (anchored, exact match) -- biologically expected values:\n")
```

For quick review, the report prints the biologically expected forward
and reverse-complement counts before and after trimming. The full
orientation-level table remains available in the workbook.

<div class="alert alert-warning">

**Retention check**: `--trimmed-only` retains a read only when Cutadapt
detects the complete linked primer structure. Unexpectedly low retention
can mean that the primers were already removed upstream, the configured
primers do not match the library, or the primer regions contain more
mismatches than the allowed error rate. Cutadapt’s error-tolerant
retained-read count is authoritative; the notebook’s separate exact
primer counts are a conservative validation aid.

</div>

------------------------------------------------------------------------

# Export Results

## Save to Excel

Export all results to an Excel workbook with multiple sheets.

``` r
# Recreate this run's workbook so sheets left by older notebook versions cannot
# survive and be mistaken for current output.
if (file_exists(output_excel_path)) file_delete(output_excel_path)

# Count complete FASTQ records before and after linked-primer trimming and
# create one typed sample-summary row per sample.
input_read_counts <- as.numeric(ShortRead::countFastq(raw_paths)$records)
trimmed_read_counts <- as.numeric(ShortRead::countFastq(trimmed_paths)$records)
sample_summary <- data.table(
  PoolNumber = sample_inventory$PoolNumber,
  SampleID = sample_names,
  InputFASTQ = sample_inventory$InputFASTQ,
  InputSizeMB = sample_inventory$InputSizeMB,
  InputReads = input_read_counts,
  RetainedReads = trimmed_read_counts,
  DiscardedReads = input_read_counts - trimmed_read_counts,
  PercentRetained = round(100 * trimmed_read_counts / input_read_counts, 2),
  ForwardPrimer = forward_primer,
  ReversePrimer = reverse_primer,
  # Cutadapt 5.2 is deliberately stored as a numeric value so Excel recognizes
  # the cell type as numeric rather than text.
  CutadaptVersion = as.numeric(cutadapt_version[[1L]]),
  OverallStatus = fifelse(trimmed_read_counts > 0, "PASS", "FAIL")
)
setorder(sample_summary, PoolNumber, SampleID)

# Put every table displayed or generated by this notebook into the workbook.
workbook_sheets <- list(
  Sample_Summary = sample_summary,
  Primer_Hit_Counts = primer_hit_counts_dt,
  Primer_Orientations = primer_orientation_table
)

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

The report lists the result sheets written to the primer-trimming
workbook so the export can be checked without opening Excel.

The next line prints the workbook path that contains the run and sample
summaries.

## Document and Export Column Dictionary

Build a trailing `Column_Dictionary` sheet documenting every column of
every sheet just written to `output_excel_path`.

The hidden export chunk appends the generated column dictionary as the
final workbook sheet; the dictionary is not duplicated as a large table
in the HTML report.

The portable link below opens the completed primer-trimming workbook
from either the HTML report or GitHub document.

------------------------------------------------------------------------

# Output File Summary

The tree below lists every file this notebook has written to its own
output folder,
[results/3_primer_trimming/](../../results/3_primer_trimming/), relative
to this notebook’s own location.

------------------------------------------------------------------------

# Recommended Next Step

The primer-trimmed, consistently oriented FASTQ files and per-sample
diagnostics exported above are ready for [Step 5 — DADA2
Pipeline](5_dada2_pipeline.md). Step 5 reads
[primer_trimmed_reads/](../../results/3_primer_trimming/primer_trimmed_reads/)
and applies length, N, and expected-error filtering before ASV inference
and chimera removal.

------------------------------------------------------------------------

# Session Information

Record the R environment for reproducibility.

------------------------------------------------------------------------

# References

## Methods

- Martin M (2011). Cutadapt removes adapter sequences from
  high-throughput sequencing reads. *EMBnet.journal*, 17(1), 10-12.
  <https://doi.org/10.14806/ej.17.1.200> — primary citation for the
  [Cutadapt](https://cutadapt.readthedocs.io/en/stable/) tool this
  notebook runs.
- Callahan BJ, McMurdie PJ, Rosen MJ, Han AW, Johnson AJA, Holmes SP
  (2016). DADA2: High-resolution sample inference from Illumina amplicon
  data. *Nature Methods*, 13, 581-583.
  <https://doi.org/10.1038/nmeth.3869> — see also the [DADA2 ITS
  Pipeline Workflow](https://benjjneb.github.io/dada2/ITS_workflow.html)
  documentation on removing primers before running DADA2.
- Pagès H, Aboyoun P, Gentleman R, DebRoy S.
  [Biostrings](https://bioconductor.org/packages/release/bioc/html/Biostrings.html):
  Efficient manipulation of biological strings. Bioconductor. — provides
  `vcountPattern()`, used by this notebook’s custom anchored primer-hit
  counter.

## Related

- [Step 1 — Data Integrity and Sample
  Mapping](1_data_integrity_and_sample_mapping.md) — validates and maps
  the supplied pool FASTQs.
- [Step 2 — Quality Filtering](2_quality_filtering.md) — calculates
  PacBio read statistics and writes the Q ≥ 20 inputs used here.
- [PacBio HiFi-16S
  workflow](https://github.com/PacificBiosciences/HiFi-16S-workflow) —
  official workflow whose linked-primer Cutadapt strategy is reproduced
  here.

------------------------------------------------------------------------

# Appendix: Troubleshooting Guide

## Common Issues and Solutions

### Cutadapt Not Found

**Error**: `Cutadapt executable not found or not executable` or
`Cutadapt could not be started`

**Solutions**:

- Recreate the project-local installation with
  [setup/install_required_tools.R](../../setup/install_required_tools.R)
- Verify that `cutadapt_path` points to the recreated project-local
  executable
- Do not copy [tools/cutadapt/venv/](../../tools/cutadapt/venv/) between
  project locations or machines; Python virtual environments contain
  absolute interpreter paths

### Primers Still Present After Trimming

**Symptom**: In `Primer_Hit_Counts`, the biologically meaningful cells
(see below) still show substantial `Hits_After`

**Possible causes**:

- Primer sequences in `forward_primer`/`reverse_primer` do not match the
  primers actually used
- `primer_anchor_buffer` is too small for a library prep with several
  leading bases before the primer (raising the buffer would catch
  primers sitting a little further from the read end)
- Read length is shorter than the primer, so the primer cannot be fully
  contained in the read

**Actions**:

- Read the cutadapt logs
  ([cutadapt_logs/](../../results/3_primer_trimming/cutadapt_logs/)):
  the summary and linked-adapter sections are Cutadapt’s own
  error-tolerant tally. If Cutadapt reports trimming but the anchored
  count remains high, review the primer sequence or anchor window.
- Verify primer sequences are correct for the experiment’s amplicon
  region

### Low or Zero Primer Counts Even Before Trimming

**Symptom**: `Hits_Before` is near zero in the meaningful values

**Likely cause**: Primers were already removed upstream (e.g. by the
sequencing facility), so there is nothing to trim. This reflects the
input data and is not a notebook malfunction. Confirm with the cutadapt
logs (they will also report near-zero matches) and by searching a few
raw reads directly.

### Memory Issues

**Error**: Cannot allocate memory for FASTQ processing

**Solutions**:

- Reduce `nr_threads` to use fewer parallel processes
- Reduce `fastq_chunk_size` so each worker holds fewer reads at once
- Process samples in batches

## Understanding the Output

### Which `Primer_Hit_Counts` values matter

The table reports 8 combinations per sample: 2 primers × 4 orientations,
with before and after counts in separate columns. Forward and
ReverseComplement hits are biologically expected before trimming because
PacBio CCS reads can arrive in either orientation. Complement and
Reverse hits have no expected mechanism and act as a contamination or
library-preparation sanity check. All primer orientations should be
approximately zero after successful linked-primer trimming.

### A note on exact matching

`Primer_Hit_Counts` uses an anchored, exact (zero-mismatch) IUPAC
search, so a read whose primer region carries a sequencing error may not
be counted; `Hits_Before` is therefore a conservative lower bound. The
[cutadapt_logs/](../../results/3_primer_trimming/cutadapt_logs/) hold
Cutadapt’s error-tolerant tally for comparison.
