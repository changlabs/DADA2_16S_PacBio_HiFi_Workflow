# Exercise standalone helpers without launching the app.
expressions <- parse('R/shiny/dada2_parameter_selection_app.R')
for (expression in expressions) {
  if (is.call(expression) && identical(expression[[1]], as.name('<-'))) {
    name <- as.character(expression[[2]])
    if (name %in% c('read_fastq_expected_errors', 'read_cached_profile', 'load_quality_profiles')) eval(expression, .GlobalEnv)
  }
}
PROCESSOR_LIMIT <- 2L
folder <- tempfile('shiny-performance-')
dir.create(folder)
files <- file.path(folder, c('sample1.fastq.gz', 'sample2.fastq.gz'))
for (path in files) {
  con <- gzfile(path, 'wt')
  for (i in 1:1200) writeLines(c(paste0('@read', i), 'ACGT', '+', if (i %% 2) 'IIII' else '5555'), con)
  close(con)
}
cache <- file.path(folder, 'cache')
serial <- load_quality_profiles(files, 100L, c(10L, 11L), 1L, cache)
stopifnot(all(vapply(serial, nrow, integer(1)) == 100L), attr(serial[[1]], 'reads_seen') == 1200L,
  all(serial[[1]]$ExpectedErrors %in% c(4 * 10^-4, 4 * 10^-2)))
parallel_profiles <- load_quality_profiles(files, 100L, c(10L, 11L), 2L, file.path(folder, 'parallel-cache'))
stopifnot(identical(serial, parallel_profiles))
hits <- load_quality_profiles(files, 100L, c(10L, 11L), 2L, cache)
stopifnot(all(vapply(hits, function(p) isTRUE(attr(p, 'cache_hit')), logical(1))))
con <- gzfile(files[[1]], 'wt'); writeLines(c('@changed', 'ACGT', '+', 'IIII'), con); close(con)
changed <- read_cached_profile(files[[1]], 100L, 10L, cache)
stopifnot(nrow(changed) == 1L, !attr(changed, 'cache_hit'))
# Inclusive threshold counts, including ties and both ends.
x <- sort(c(0, 1, 1, 2, 3))
stopifnot(identical(findInterval(c(-1, 0, 1, 3, 4), x), c(0L, 1L, 3L, 5L, 5L)))
unlink(folder, recursive = TRUE)
cat('Shiny serial/parallel sampling, full-file coverage, cache invalidation and inclusive counts passed.\n')

source('R/shiny/dada2_parameter_selection_app.R')
shiny::testServer(server, {
  session$setInputs(processors = 2L, selected_maxee = 1)
  stopifnot(processors() == min(2L, PROCESSOR_LIMIT))
  loaded_reads(data.frame(SampleID = c('B','B','A','A'), ExpectedErrors = c(1,2,1,3), ReadLength = 4L))
  stopifnot(identical(retention_summary()$Reads_EE_le_maxEE, c(1L,1L)))
  curve <- cached_retention_curve()
  session$setInputs(selected_maxee = 3, processors = 9999L)
  stopifnot(identical(retention_summary()$Reads_EE_le_maxEE, c(2L,2L)),
    identical(curve, cached_retention_curve()), processors() == PROCESSOR_LIMIT,
    nrow(cached_sample_curves()) == 802L)
})
cat('Server processor limits, inclusive counts and cached plot calculations passed.\n')
