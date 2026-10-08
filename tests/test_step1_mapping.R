#!/usr/bin/env Rscript
# Regression coverage for direct gzip inputs and literal sample-sheet matching.
script_arg <- grep('^--file=', commandArgs(FALSE), value = TRUE)
project_root <- normalizePath(file.path(dirname(sub('^--file=', '', script_arg[[1L]])), '..'))
setwd(project_root)
here::i_am('tests/test_step1_mapping.R')
notebook <- readLines('R/notebooks/1_data_integrity_and_sample_mapping.Rmd')
chunk_code <- function(label) {
  start <- which(grepl(paste0('^```\\{r ', label, '(,|\\})'), notebook))
  stopifnot(length(start) == 1L)
  end <- which(seq_along(notebook) > start & notebook == '```')[[1L]]
  parse(text = notebook[seq.int(start + 1L, end - 1L)])
}
fixture <- tempfile('step1-mapping-')
dir.create(fixture)
# Run inside a function so fixture cleanup always executes.
run_tests <- function() {
  on.exit(unlink(fixture, recursive = TRUE), add = TRUE)
  data_root <- file.path(fixture, 'data')
  for (pool in c('Pool1', 'POOL2')) dir.create(file.path(data_root, 'fastq', pool), recursive = TRUE)
  sheet <- data.frame(
    PoolNumber = c(1, 1, 2, 3),
    SampleID = c('IgAN61_fecal_bulk', 'Conventional', 'Literal', 'Inactive'),
    ForwardBarcodeID = c('Kinnex16S_Fwd_06', 'bc03', 'Fwd+06', 'unused'),
    ReverseBarcodeID = c('Kinnex16S_Rev_16', 'bc04', 'Rev[16]', 'unused')
  )
  openxlsx::write.xlsx(sheet, file.path(data_root, 'sample_sheet.xlsx'))
  names <- c(
    'm84157_260831_153015_s4.hifi_reads.Kinnex16S_Fwd_06--Kinnex16S_Rev_16.hifi_reads.fastq.gz',
    'lima.bc03--bc04.Q20.fastq.gz', 'run.Fwd+06--Rev[16].fastq.gz',
    'run.bc030--bc04.fastq.gz'
  )
  sources <- file.path(data_root, 'fastq', c('Pool1', 'Pool1', 'POOL2', 'Pool1'), names)
  for (p in sources) {
    con <- gzfile(p, 'wt')
    writeLines(c('@read1', 'ACGT', '+', 'IIII'), con)
    close(con)
  }
  checksums <- tools::md5sum(sources)
  make_environment <- function() {
    env <- new.env(parent = globalenv())
    env$raw_fastq_root <- file.path(data_root, 'fastq')
    env$sequencing_sheet_path <- file.path(data_root, 'sample_sheet.xlsx')
    env$sequencing_sheet_name <- 1
    env$results_folder <- tempfile('results-', tmpdir = fixture)
    env$project_root <- fixture
    dir.create(env$results_folder, recursive = TRUE)
    env$workbook_path <- file.path(env$results_folder, 'summary.xlsx')
    env$validate_complete_fastq <- TRUE
    for (chunk in c('load-packages', 'helper-functions', 'discover-pools-and-fastqs', 'read-sequencing-sheet')) {
      invisible(eval(chunk_code(chunk), env))
    }
    env
  }
  env <- make_environment()
  stopifnot(env$extract_pool_number('pool1') == 1L,
            env$extract_pool_number('Pool1') == 1L,
            env$extract_pool_number('POOL1') == 1L,
            is.na(env$extract_pool_number('Pool1_extra')))
  for (chunk in c('match-samples', 'validate-original-fastq', 'export-results', 'final-integrity-decision')) {
    invisible(eval(chunk_code(chunk), env))
  }
  stopifnot(nrow(env$sample_manifest) == 3L,
            sum(env$sample_manifest$Input_Reads) == 3,
            sum(!env$fastq_inventory$Listed_In_Sequencing_Sheet) == 1L,
            identical(unname(tools::md5sum(sources)), unname(checksums)),
            !dir.exists(file.path(env$results_folder,'mapped_fastq')))
  manifest <- openxlsx::read.xlsx(env$workbook_path, sheet = 'Sample_Manifest')
  stopifnot(all(file.exists(file.path(fixture,manifest$SourceFASTQPath))),
            !any(grepl('^/',manifest$SourceFASTQPath)),
            'Unlisted_FASTQs' %in% openxlsx::getSheetNames(env$workbook_path),
            'Inactive_Sheet_Rows' %in% openxlsx::getSheetNames(env$workbook_path),
            !any(c('SourceFASTQ','ForwardBarcodeID','ReverseBarcodeID','SourceSampleID') %in% names(manifest)),
            grepl('Kinnex16S_Fwd_06--Kinnex16S_Rev_16',manifest$SourceFASTQPath[manifest$SampleID == 'IgAN61_fecal_bulk'],fixed=TRUE))
  # Move the input layout to another root and exercise Step 2's actual reader.
  relocated <- file.path(fixture, 'relocated_project')
  dir.create(relocated)
  for (i in seq_len(nrow(manifest))) {
    destination <- file.path(relocated, manifest$SourceFASTQPath[[i]])
    dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
    file.copy(file.path(fixture, manifest$SourceFASTQPath[[i]]), destination)
  }
  step2_lines <- readLines('R/notebooks/2_quality_filtering.Rmd')
  start <- which(grepl('^```\\{r read-manifest', step2_lines))
  end <- which(seq_along(step2_lines) > start & step2_lines == '```')[[1L]]
  env$project_root <- relocated
  env$step1_workbook <- env$workbook_path
  invisible(eval(parse(text = step2_lines[seq.int(start + 1L, end - 1L)]), env))
  stopifnot(all(file.exists(env$sample_manifest$FASTQ)),
            all(startsWith(env$sample_manifest$FASTQ, as.character(fs::path_norm(relocated)))),
            setequal(env$sample_manifest$SampleID, manifest$SampleID))
  altered <- sheet
  altered$SampleID[altered$SampleID == 'Literal'] <- 'Literal Name'
  openxlsx::write.xlsx(altered, file.path(data_root, 'sample_sheet.xlsx'), overwrite = TRUE)
  sanitized <- make_environment()
  for (label in c('match-samples','validate-original-fastq','export-results')) {
    invisible(eval(chunk_code(label), sanitized))
  }
  audited <- openxlsx::read.xlsx(sanitized$workbook_path, sheet = 'Sample_Manifest')
  stopifnot('SourceSampleID' %in% names(audited),
            audited$SourceSampleID[audited$SampleID == 'Literal-Name'] == 'Literal Name')
  openxlsx::write.xlsx(sheet, file.path(data_root, 'sample_sheet.xlsx'), overwrite = TRUE)
  expect_error <- function(expr, message) {
    error <- tryCatch({force(expr); NULL}, error = identity)
    stopifnot(inherits(error, 'error'), grepl(message, conditionMessage(error), fixed = TRUE))
  }
  duplicate <- file.path(dirname(sources[[1L]]), 'second.Kinnex16S_Fwd_06--Kinnex16S_Rev_16.fastq.gz')
  file.copy(sources[[1L]], duplicate)
  env <- make_environment()
  expect_error(eval(chunk_code('match-samples'), env), 'Multiple FASTQ files match')
  unlink(duplicate)
  combined <- file.path(dirname(sources[[1L]]), 'Kinnex16S_Fwd_06--Kinnex16S_Rev_16.bc03--bc04.fastq.gz')
  file.rename(sources[[1L]], combined); unlink(sources[[2L]])
  env <- make_environment()
  expect_error(eval(chunk_code('match-samples'), env), 'matches more than one')
  unlink(combined)
  env <- make_environment()
  expect_error(eval(chunk_code('match-samples'), env), 'missing from the supplied FASTQs')
  stopifnot(!env$matches_barcode_pair('run.bc030--bc04.fastq.gz', 'bc03', 'bc04'),
            !env$matches_barcode_pair(names[[1L]], 'kinnex16s_fwd_06', 'Kinnex16S_Rev_16'))
  cat('PASS: Kinnex, conventional and literal punctuation identifiers; unlisted/inactive rows; unchanged originals and project-relative source mapping; duplicate, ambiguous and missing match rejection.\n')
}
run_tests()
