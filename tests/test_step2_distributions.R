#!/usr/bin/env Rscript
# Verify all-read counts beyond the old cap, exact quantiles, and six facets/page.
arg <- grep('^--file=', commandArgs(FALSE), value = TRUE)[[1L]]
root <- normalizePath(file.path(dirname(sub('^--file=', '', arg)), '..'))
setwd(root)
suppressPackageStartupMessages({library(data.table);library(fs);library(ggplot2);library(ShortRead)})
lines <- readLines('R/notebooks/2_quality_filtering.Rmd')
chunk <- function(label) {
  start <- which(grepl(paste0('^```\\{r ',label,'(,|\\})'),lines))
  end <- which(seq_along(lines)>start & lines=='```')[[1L]]
  parse(text=lines[seq.int(start+1L,end-1L)])
}
run_test <- function() {
  tmp <- tempfile('step2-distributions-');dir.create(tmp)
  on.exit(unlink(tmp,recursive=TRUE),add=TRUE)
  eval(chunk('define-qc-parameters'))
  eval(chunk('helper-functions'))
  eval(chunk('distribution-helpers'))
  # Count 50,000 short reads plus late observations outside the previous cap.
  input <- file.path(tmp,'input.fastq.gz')
  con <- gzfile(input,'wt')
  for(i in seq_len(50L)) writeLines(rep(c('@short','ACGT','+','IIII'),1000L),con)
  lengths <- c(1799L,1800L,2000L,2001L)
  for(i in seq_along(lengths)) writeLines(c(paste0('@late',i),strrep('A',lengths[i]),'+',strrep('I',lengths[i])),con)
  close(con)
  audit <- gzfile(file.path(tmp,'audit.tsv.gz'),'wt')
  result <- tryCatch(summarize_fastq(input,'Sample1',file.path(tmp,'filtered.fastq.gz'),audit),finally=close(audit))
  on.exit(unlink(result$summary$HistogramPath),add=TRUE)
  frequencies <- readRDS(result$summary$HistogramPath)
  stopifnot(result$summary$TotalReads==50004, result$summary$PlotReads==50004,
            result$summary$ReadsInAnnotationRange==2,
            sum(frequencies$length$Count)==50004, sum(frequencies$quality$Count)==50004)
  exact <- data.table(Value=c(4,lengths),Count=c(50000,rep(1,4)))
  expanded <- c(rep(4,50000),lengths)
  stopifnot(isTRUE(all.equal(frequency_quantiles(exact,c(.05,.25,.5,.75,.95,1)),
                            unname(quantile(expanded,c(.05,.25,.5,.75,.95,1),type=7)))))
  # Seven sample summaries reuse tiny frequency caches; the plotter must create
  # pages of six and one facets without constructing a read-level plotting table.
  sample_qc <- rbindlist(lapply(seq_len(7),function(i){x<-copy(result$summary);x[,SampleID:=paste0('Sample',i)];x}))
  for(metric in c('length','quality')) {
    p1 <- make_distribution_page(sample_qc[1:6],metric,1,2)
    p2 <- make_distribution_page(sample_qc[7],metric,2,2)
    b1 <- ggplot_build(p1);b2<-ggplot_build(p2)
    stopifnot(nrow(b1$layout$layout)==6,nrow(b2$layout$layout)==1,
              sum(b1$data[[1]]$y)==6*50004)
    if(metric == 'length') {
      stopifnot(all(grepl('1800-2000 bp: 2',b1$data[[3]]$label,fixed=TRUE)))
    } else {
      stopifnot(!any(grepl('1800-2000',b1$data[[3]]$label,fixed=TRUE)),
                all(grepl('Reads with Q >= 20',b1$data[[3]]$label,fixed=TRUE)))
    }
    path <- file.path(tmp,paste0(metric,'.pdf'))
    stopifnot(write_distribution_pdf(metric,path)==2,file.info(path)$size>0)
    pdfinfo <- Sys.which('pdfinfo')
    if(nzchar(pdfinfo)) {
      info <- system2(pdfinfo,shQuote(path),stdout=TRUE)
      stopifnot(any(grepl('^Pages:[[:space:]]+2$',info)))
    }
  }
  stopifnot(as.numeric(object.size(frequencies))<10000)
  cat('PASS: 50,004 reads counted without sampling; inclusive 1800–2000 counts; exact quantiles; two PDF pages with 6+1 facets; compact frequency cache.\n')
}
run_test()
