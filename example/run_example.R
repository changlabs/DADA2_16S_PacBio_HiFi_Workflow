#!/usr/bin/env Rscript

# Run all nine workflow steps against the bundled PacBio HiFi example. Inputs,
# generated outputs, and rendered reports remain below example/ so this run
# never reads from data/fastq or writes to the normal results/ directory.

script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
if (!length(script_argument)) {
  stop("Run this file with Rscript: Rscript example/run_example.R", call. = FALSE)
}

script_path <- normalizePath(sub("^--file=", "", script_argument[[1]]), mustWork = TRUE)
project_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
setwd(project_root)

if (length(commandArgs(trailingOnly = TRUE))) {
  stop("This runner accepts no arguments. Use: Rscript example/run_example.R", call. = FALSE)
}

data_root <- file.path(project_root, "example", "data")
run_results <- file.path(project_root, "example", "run_results")
reference_results <- file.path(project_root, "example", "reference_results")
configuration_workbook <- file.path(data_root, "dada2_filter_parameters.xlsx")

Sys.setenv(
  DADA2_DATA_DIR = data_root,
  DADA2_RESULTS_DIR = run_results,
  DADA2_REPORT_DIR = file.path(run_results, "reports"),
  DADA2_PARAMETER_FILE = configuration_workbook,
  DADA2_TAXONOMY_DATABASE = "BOTH"
)

required_packages <- c(
  "rmarkdown", "openxlsx", "ShortRead", "dada2", "DECIPHER", "ape",
  "phangorn", "phyloseq", "htmlwidgets"
)
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages)) {
  stop(
    "Install the workflow R dependencies first; missing: ",
    paste(missing_packages, collapse = ", "),
    call. = FALSE
  )
}

archive_path <- file.path(
  data_root, "fastq", "pool1", "Callahan-Fecal-HiFi-Example.fastq.zip"
)
sample_sheet_path <- file.path(data_root, "sample_sheet.xlsx")
metadata_path <- file.path(data_root, "metadata.tsv")
cell_count_path <- file.path(data_root, "cell_count", "cell_count.tsv")
required_inputs <- c(
  archive_path, sample_sheet_path, metadata_path, cell_count_path,
  configuration_workbook
)
if (!all(file.exists(required_inputs))) {
  stop(
    "The bundled example is incomplete. Missing:\n  - ",
    paste(required_inputs[!file.exists(required_inputs)], collapse = "\n  - "),
    call. = FALSE
  )
}

archive_members <- utils::unzip(archive_path, list = TRUE)$Name
expected_members <- paste0(
  "lima.bc", sprintf("%04d", 1001:1004), "--bc",
  sprintf("%04d", 1001:1004), ".Q20.fastq"
)
if (!identical(sort(archive_members), sort(expected_members))) {
  stop(
    "The example archive must contain exactly the four documented Lima-style FASTQs.",
    call. = FALSE
  )
}

sample_sheet <- openxlsx::read.xlsx(sample_sheet_path, sheet = "SampleSheet")
metadata <- utils::read.delim(metadata_path, check.names = FALSE)
cell_counts <- utils::read.delim(cell_count_path, check.names = FALSE)
expected_sample_ids <- c(
  "Subject-R3-Timepoint-1", "Subject-R3-Timepoint-2",
  "Subject-R3-Timepoint-3", "Subject-R11-Timepoint-1"
)
for (input_table in list(sample_sheet, metadata, cell_counts)) {
  if (!"SampleID" %in% names(input_table) ||
      !identical(sort(input_table$SampleID), sort(expected_sample_ids))) {
    stop("Example sample identifiers are missing or inconsistent across inputs.", call. = FALSE)
  }
}
if (!all(is.finite(cell_counts$Cell_Count)) || any(cell_counts$Cell_Count <= 0)) {
  stop("The example requires one positive synthetic Cell_Count per sample.", call. = FALSE)
}

configuration_sheets <- openxlsx::getSheetNames(configuration_workbook)
if (!all(c("Parameters", "Sample_Retention", "Info") %in% configuration_sheets)) {
  stop("The example Step 4 workbook is missing a required worksheet.", call. = FALSE)
}
step4_parameters <- openxlsx::read.xlsx(
  configuration_workbook, sheet = "Parameters", check.names = FALSE
)
maxee_row <- match("max_expected_errors", step4_parameters$Parameter)
selected_maxee <- suppressWarnings(as.numeric(step4_parameters$Value[maxee_row]))
if (is.na(selected_maxee) || selected_maxee != 2) {
  stop("The prepared PacBio Step 4 workbook must select maxEE = 2.", call. = FALSE)
}

step4_info <- openxlsx::read.xlsx(
  configuration_workbook, sheet = "Info", check.names = FALSE
)
step4_info_values <- setNames(as.character(step4_info$Value), step4_info$Field)
if (!identical(unname(step4_info_values[["Source_BioProject"]]), "PRJNA521754") ||
    !grepl("Full-length", unname(step4_info_values[["Target"]]), fixed = TRUE)) {
  stop("The prepared Step 4 workbook must identify PRJNA521754 and full-length 16S.", call. = FALSE)
}

# rmarkdown needs Pandoc. RStudio normally configures it; from a terminal,
# reuse Quarto's bundled executable when it is available.
if (!rmarkdown::pandoc_available()) {
  quarto_executable <- Sys.which("quarto")
  if (nzchar(quarto_executable)) {
    pandoc_candidates <- list.files(
      file.path(dirname(normalizePath(quarto_executable)), "tools"),
      pattern = "^pandoc$", recursive = TRUE, full.names = TRUE
    )
    pandoc_candidates <- pandoc_candidates[file.access(pandoc_candidates, 1L) == 0L]
    if (length(pandoc_candidates)) Sys.setenv(RSTUDIO_PANDOC = dirname(pandoc_candidates[[1]]))
  }
}
if (!rmarkdown::pandoc_available()) {
  stop("Pandoc is required. Run from RStudio or install Quarto/Pandoc.", call. = FALSE)
}

taxonomy_files <- c(
  file.path(project_root, "tools", "trainsets", "SILVA", c(
    "silva_nr99_v144_toGenus_trainset.fa.gz",
    "silva_v144_assignSpecies.fa.gz"
  )),
  file.path(project_root, "tools", "trainsets", "GTDB", c(
    "sbdi-gtdb-sativa.r11rs232-1.1genome.assignTaxonomy.fna.gz",
    "sbdi-gtdb-sativa.r11rs232-1.20genomes.addSpecies.fna.gz"
  ))
)
if (!all(file.exists(taxonomy_files))) {
  stop(
    "The complete SILVA and GTDB trainsets are required. Run ",
    "setup/download_reference_databases.R first. Missing:\n  - ",
    paste(taxonomy_files[!file.exists(taxonomy_files)], collapse = "\n  - "),
    call. = FALSE
  )
}

required_executables <- c(
  Cutadapt = file.path(project_root, "tools", "cutadapt", "venv", "bin", "cutadapt"),
  FastTree = file.path(project_root, "tools", "fasttree", "FastTree")
)
missing_executables <- names(required_executables)[file.access(required_executables, 1L) != 0L]
if (length(missing_executables)) {
  stop(
    "Required project-local tool(s) missing or not executable: ",
    paste(missing_executables, collapse = ", "), ". Run setup/install_required_tools.R first.",
    call. = FALSE
  )
}

conda_candidates <- c(Sys.which("conda"), "/opt/anaconda3/bin/conda", "/opt/homebrew/bin/conda")
conda_candidates <- unique(conda_candidates[nzchar(conda_candidates)])
if (!any(file.access(conda_candidates, 1L) == 0L)) {
  stop(
    "Conda with a picrust2 environment is required for Step 7. See ",
    "setup/install_picrust2.sh.", call. = FALSE
  )
}

if (dir.exists(run_results)) unlink(run_results, recursive = TRUE, force = TRUE)
report_directory <- file.path(run_results, "reports")
dir.create(report_directory, recursive = TRUE, showWarnings = FALSE)

step4_run_directory <- file.path(run_results, "4_dada2_parameter_selection")
dir.create(step4_run_directory, recursive = TRUE, showWarnings = FALSE)
file.copy(
  configuration_workbook,
  file.path(step4_run_directory, "dada2_filter_parameters.xlsx"),
  overwrite = TRUE
)

render_step <- function(filename) {
  message("\nRendering ", filename, " ...")
  rmarkdown::render(
    input = file.path(project_root, "R", "notebooks", filename),
    output_format = "html_document",
    output_dir = report_directory,
    envir = new.env(parent = globalenv()),
    clean = TRUE,
    quiet = FALSE
  )
}

render_step("1_data_integrity_and_sample_mapping.Rmd")
render_step("2_quality_filtering.Rmd")
render_step("3_primer_trimming.Rmd")
render_step("4_dada2_parameter_selection.Rmd")
render_step("5_dada2_pipeline.Rmd")
render_step("6_phylogenetic_tree.Rmd")
message(
  "\nSteps 8-9 use synthetic cell counts solely to exercise the complete workflow; ",
  "they are not source-study measurements."
)
render_step("7_copy_number_correction.Rmd")
render_step("8_microbial_load_correction.Rmd")
render_step("9_phyloseq_object.Rmd")

# Narrative links in the generic notebooks use ../../results/. Within the
# isolated example report directory, the equivalent step folders are one
# level up. Dynamic output links already honor DADA2_REPORT_DIR; this rewrite
# keeps the explanatory links portable as well.
report_files <- list.files(report_directory, pattern = "[.]html$", full.names = TRUE)
for (report_file in report_files) {
  report_html <- readLines(report_file, warn = FALSE, encoding = "UTF-8")
  report_html <- gsub('href="../../results/', 'href="../', report_html, fixed = TRUE)
  writeLines(report_html, report_file, useBytes = TRUE)
}

required_outputs <- c(
  file.path(run_results, "1_data_integrity_and_sample_mapping", "data_integrity_and_sample_mapping.xlsx"),
  file.path(run_results, "2_quality_filtered_reads", "quality_and_read_length_summary.xlsx"),
  file.path(run_results, "3_primer_trimming", "primer_trimming_summary.xlsx"),
  file.path(run_results, "4_dada2_parameter_selection", "dada2_filter_parameters.xlsx"),
  file.path(run_results, "5_dada2_pipeline", c(
    "asv_count_table.csv", "asv_sequences.csv", "silva_taxonomy_table.csv",
    "gtdb_taxonomy_table.csv", "processing_summary.xlsx"
  )),
  file.path(run_results, "6_phylogenetic_tree", c(
    "phylogenetic_tree_SILVA_labeled.nwk", "phylogenetic_tree_GTDB_labeled.nwk",
    "phylogenetic_tree_SILVA.pdf", "phylogenetic_tree_GTDB.pdf"
  )),
  file.path(run_results, "7_copy_number_correction", c(
    "copy_number_corrected_asv_count_table.csv", "copy_number_correction_summary.xlsx"
  )),
  file.path(run_results, "8_microbial_load_correction", c(
    "microbial_load_corrected_abundance_table.csv", "microbial_load_correction_summary.xlsx"
  )),
  file.path(run_results, "9_phyloseq_object", "SILVA", "phyloseq_objects", c(
    "phyloseq_object_silva_raw_counts.RData",
    "phyloseq_object_silva_copy_number_corrected.RData",
    "phyloseq_object_silva_microbial_load_corrected.RData"
  )),
  file.path(run_results, "9_phyloseq_object", "GTDB", "phyloseq_objects", c(
    "phyloseq_object_gtdb_raw_counts.RData",
    "phyloseq_object_gtdb_copy_number_corrected.RData",
    "phyloseq_object_gtdb_microbial_load_corrected.RData"
  )),
  file.path(report_directory, paste0(c(
    "1_data_integrity_and_sample_mapping", "2_quality_filtering",
    "3_primer_trimming", "4_dada2_parameter_selection", "5_dada2_pipeline",
    "6_phylogenetic_tree", "7_copy_number_correction",
    "8_microbial_load_correction", "9_phyloseq_object"
  ), ".html"))
)
missing_outputs <- required_outputs[!file.exists(required_outputs)]
if (length(missing_outputs)) {
  stop(
    "The example run did not produce the complete required deliverable set:\n  - ",
    paste(missing_outputs, collapse = "\n  - "),
    call. = FALSE
  )
}

message(
  "\nExample run complete.\n",
  "Completed: all Steps 1-9, including the Step 4 guide and prepared handoff.\n",
  "Taxonomy: SILVA and GTDB through the labelled trees and all six final ",
  "database-by-abundance phyloseq objects.\n",
  "Generated results: ", run_results, "\n",
  "Bundled reference results: ", reference_results, "\n",
  "The normal data/fastq and results/ directories were not touched."
)
