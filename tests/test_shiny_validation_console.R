# Verify the asynchronous console lifecycle with a short deterministic worker.
source('R/shiny/dada2_parameter_selection_app.R')
real_worker <- run_validation_worker
run_validation_worker <- function(selected_files, selected_samples, validation_selection,
                                  threshold, processors, validation_directory) {
  cat('[stage] Learning a PacBio error model ...\n')
  flush.console()
  Sys.sleep(1)
  cat('[stage] Inferring ASVs ...\n')
  flush.console()
  Sys.sleep(1)
  data.frame(SampleID = selected_samples, maxEE = threshold)
}
shiny::testServer(server, {
  messages <- list()
  session$sendCustomMessage <- function(type, message) {
    if (identical(type, 'console_msg')) messages[[length(messages) + 1L]] <<- message$text
  }
  loaded_reads(data.frame(SampleID = 'Sample1', ExpectedErrors = 1, ReadLength = 1200L))
  loaded_files(c(Sample1 = 'unused.fastq.gz'))
  session$setInputs(selected_maxee = 2, processors = 1, validation_n_samples = 1,
    validate_all_samples = FALSE, run_validation = 1)
  stopifnot(!is.null(validation_job()), is.null(validation_results()))
  directory <- validation_job()$directory
  state <- validation_job()
  state$last_heartbeat <- Sys.time() - 11
  validation_job(state)
  session$elapse(500)
  stopifnot(any(grepl('Still running:', unlist(messages))))
  for (i in seq_len(60)) {
    Sys.sleep(.1)
    session$elapse(500)
    if (is.null(validation_job())) break
  }
  stopifnot(is.null(validation_job()), nrow(validation_results()) == 1L,
    !dir.exists(directory), any(grepl('Learning a PacBio', unlist(messages))),
    any(grepl('Inferring ASVs', unlist(messages))),
    any(grepl('completed successfully', unlist(messages))))
})
# Verify failure is reported, temporary files removed, and the app can retry.
run_validation_worker <- function(...) stop('Deliberate validation failure')
shiny::testServer(server, {
  messages <- character()
  session$sendCustomMessage <- function(type, message) {
    if (identical(type, 'console_msg')) messages <<- c(messages, message$text)
  }
  loaded_reads(data.frame(SampleID = 'Sample1', ExpectedErrors = 1, ReadLength = 1200L))
  loaded_files(c(Sample1 = 'unused.fastq.gz'))
  session$setInputs(selected_maxee = 2, processors = 1, validation_n_samples = 1,
    validate_all_samples = FALSE, run_validation = 1)
  directory <- validation_job()$directory
  for (i in seq_len(60)) {
    Sys.sleep(.1)
    session$elapse(500)
    if (is.null(validation_job())) break
  }
  stopifnot(is.null(validation_job()), is.null(validation_results()),
    !dir.exists(directory), any(grepl('Validation stopped:', messages)))
})
run_validation_worker <- real_worker
cat('Live validation stages, heartbeat, results, error reporting and cleanup passed.\n')
# Exercise the real worker and DADA2 filters through callr, stopping deliberately
# at an impossible maxEE to avoid fitting an error model to synthetic reads.
folder <- tempfile('validation-real-worker-')
dir.create(folder)
path <- file.path(folder, 'sample.fastq.gz')
con <- gzfile(path, 'wt')
for (i in 1:5) writeLines(c(paste0('@read', i), paste(rep('ACGT', 300), collapse = ''),
  '+', paste(rep('I', 1200), collapse = '')), con)
close(con)
log <- file.path(folder, 'worker.log')
job <- callr::r_bg(real_worker, args = list(selected_files = path, selected_samples = 'Sample1',
  validation_selection = data.frame(SampleID = 'Sample1'), threshold = 0, processors = 1L,
  validation_directory = file.path(folder, 'reads')), stdout = log, stderr = '2>&1')
job$wait(timeout = 30000)
if (job$is_alive()) { job$kill_tree(); stop('Validation worker timed out') }
failed <- tryCatch({job$get_result(); FALSE}, error = function(e) grepl('No reads remained', conditionMessage(e)))
lines <- readLines(log, warn = FALSE)
stopifnot(failed, any(grepl('target-length filter', lines)),
  any(grepl('ambiguous bases', lines)), any(grepl('Filtering with maxEE', lines)),
  !dir.exists(file.path(folder, 'reads')))
unlink(folder, recursive = TRUE)
cat('Real DADA2 worker filtering, streamed stages and error cleanup passed.\n')
