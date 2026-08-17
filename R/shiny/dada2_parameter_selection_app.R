################################################################################
# PacBio HiFi maxEE Parameter Explorer
#
# Purpose
#   - Calculate the expected-error (EE) distribution of the complete,
#     primer-trimmed PacBio HiFi reads produced by Step 3.
#   - Show how overall and per-sample retention changes across candidate maxEE
#     thresholds without introducing Illumina-only truncLen or paired-read
#     controls.
#   - Validate the selected maxEE on real reads with the same core DADA2
#     operations used by Step 5: filterAndTrim(), learnErrors(PacBioErrfun),
#     derepFastq(), and dada().
#   - Export the selected numeric maxEE value and its provenance to the workbook
#     automatically consumed by Step 5.
################################################################################

required_packages <- c(
  "shiny", "bslib", "shinyFiles", "shinyjs", "DT", "plotly", "ggplot2",
  "dada2", "ShortRead", "fs", "here", "openxlsx"
)
missing_packages <- required_packages[!vapply(required_packages, requireNamespace,
                                               logical(1), quietly = TRUE)]
if (length(missing_packages)) {
  stop("Install the required package(s) before running the app: ",
       paste(missing_packages, collapse = ", "))
}

library(shiny)

# Shared workbook helpers keep the exported report consistent with the other
# workflow workbooks, including styled sheets and a Column_Dictionary sheet.
source(here::here("R", "functions", "add_sheet_to_excel_function.R"))
source(here::here("R", "functions", "build_column_dictionary_function.R"))

default_fastq_folder <- here::here(
  "results", "3_primer_trimming", "primer_trimmed_reads"
)
default_export_path <- here::here(
  "results", "4_dada2_parameter_selection", "dada2_filter_parameters.xlsx"
)

# Return uncompressed and gzip-compressed FASTQ files in a deterministic order.
find_fastq_files <- function(folder) {
  if (!fs::dir_exists(folder)) return(character())
  files <- fs::dir_ls(
    folder,
    regexp = "\\.(fastq|fq)(\\.gz)?$",
    type = "file",
    recurse = FALSE,
    fail = FALSE
  )
  sort(as.character(files))
}

# Derive SampleID from the Step 3 naming convention while retaining a sensible
# fallback for FASTQs whose names do not include the standard suffix.
sample_id_from_path <- function(path) {
  name <- fs::path_file(path)
  name <- sub("\\.gz$", "", name, ignore.case = TRUE)
  name <- sub("\\.(fastq|fq)$", "", name, ignore.case = TRUE)
  sub("_primer_trimmed$", "", name, ignore.case = TRUE)
}

# Read at most max_reads complete FASTQ records and calculate each read's total
# expected errors directly from its Phred+33 quality string:
#       EE = sum(10^(-Q/10))
# Reading in chunks avoids loading an entire production FASTQ into memory.
# Adapt sampling depth to cohort size so large studies remain responsive while
# small studies retain a deeper, more stable expected-error sample.
# The smaller per-sample sample size for larger cohorts bounds total runtime and
# memory while still representing every sample in the retention calculation.
recommended_reads_per_sample <- function(n_samples) {
  if (!is.numeric(n_samples) || length(n_samples) != 1L || is.na(n_samples) ||
      !is.finite(n_samples) || n_samples <= 0) return(15000L)
  if (n_samples <= 20) return(20000L)
  if (n_samples <= 50) return(15000L)
  if (n_samples <= 100) return(9000L)
  4000L
}

SAMPLING_BASE_SEED <- 20260806L

# Stream the complete FASTQ and retain a reproducible reservoir sample. Unlike
# reading the first N records, this gives reads near the beginning and end of a
# sequencing file the same probability of selection.
read_fastq_expected_errors <- function(path, max_reads = 20000L,
                                       chunk_reads = 5000L, seed = 1L) {
  connection <- if (grepl("\\.gz$", path, ignore.case = TRUE)) {
    gzfile(path, open = "rt")
  } else {
    file(path, open = "rt")
  }
  on.exit(close(connection), add = TRUE)

  set.seed(as.integer(seed))
  expected_errors <- numeric(max_reads)
  read_lengths <- integer(max_reads)
  reads_seen <- 0L
  reads_kept <- 0L
  malformed_records <- 0L

  repeat {
    lines <- readLines(connection, n = 4L * chunk_reads, warn = FALSE)
    if (!length(lines)) break

    complete_line_count <- length(lines) - (length(lines) %% 4L)
    if (complete_line_count != length(lines)) malformed_records <- malformed_records + 1L
    if (complete_line_count == 0L) break
    lines <- lines[seq_len(complete_line_count)]

    sequence_lines <- lines[seq.int(2L, complete_line_count, by = 4L)]
    quality_lines <- lines[seq.int(4L, complete_line_count, by = 4L)]
    matching_width <- nchar(sequence_lines, type = "bytes") ==
      nchar(quality_lines, type = "bytes")
    malformed_records <- malformed_records + sum(!matching_width)
    if (!any(matching_width)) next

    sequence_lines <- sequence_lines[matching_width]
    quality_lines <- quality_lines[matching_width]
    chunk_ee <- vapply(
      quality_lines,
      function(quality_string) {
        phred_scores <- utf8ToInt(quality_string) - 33L
        if (any(phred_scores < 0L)) return(NA_real_)
        sum(10^(-phred_scores / 10))
      },
      numeric(1)
    )
    valid <- is.finite(chunk_ee)
    chunk_ee <- chunk_ee[valid]
    chunk_lengths <- nchar(sequence_lines[valid], type = "bytes")
    for (record_index in seq_along(chunk_ee)) {
      reads_seen <- reads_seen + 1L
      if (reads_kept < max_reads) {
        reads_kept <- reads_kept + 1L
        slot <- reads_kept
      } else {
        slot <- sample.int(reads_seen, 1L)
        if (slot > max_reads) next
      }
      expected_errors[[slot]] <- chunk_ee[[record_index]]
      read_lengths[[slot]] <- chunk_lengths[[record_index]]
    }
  }

  if (reads_kept == 0L) {
    expected_errors <- numeric()
    read_lengths <- integer()
  } else {
    expected_errors <- expected_errors[seq_len(reads_kept)]
    read_lengths <- read_lengths[seq_len(reads_kept)]
  }

  data.frame(
    ExpectedErrors = expected_errors,
    ReadLength = read_lengths,
    stringsAsFactors = FALSE,
    check.names = FALSE
  ) |>
    structure(malformed_records = malformed_records, reads_seen = reads_seen,
              sampling_seed = as.integer(seed))
}

# Use a retention-stratified spread for real DADA2 validation, matching the
# Illumina app: lowest and highest retention are included when possible and
# interior samples are chosen at evenly spaced quantiles.
recommended_validation_samples <- function(n_samples) {
  if (!is.finite(n_samples) || n_samples <= 0) return(3L)
  if (n_samples <= 5) return(as.integer(n_samples))
  if (n_samples <= 20) return(5L)
  if (n_samples <= 50) return(6L)
  if (n_samples <= 100) return(8L)
  10L
}

select_validation_samples <- function(retention, n_validate) {
  n_total <- length(retention)
  if (!n_total) return(data.frame())
  n_validate <- max(1L, min(as.integer(n_validate), n_total))
  sample_names <- names(retention)
  if (is.null(sample_names)) sample_names <- paste0("Sample", seq_len(n_total))
  ordering_value <- ifelse(is.finite(retention), retention, -Inf)
  ranked <- order(ordering_value, sample_names)
  positions <- if (n_validate == 1L) {
    ceiling(n_total / 2)
  } else {
    unique(round(seq(1, n_total, length.out = n_validate)))
  }
  while (length(positions) < n_validate) {
    positions <- sort(c(positions, setdiff(seq_len(n_total), positions)[1]))
  }
  chosen <- ranked[positions]
  probabilities <- if (n_validate == 1L) 0.5 else seq(0, 1, length.out = n_validate)
  roles <- ifelse(
    probabilities == 0, "lowest retention",
    ifelse(probabilities == 1, "highest retention",
           ifelse(probabilities == 0.5, "median retention",
                  paste0("p", round(100 * probabilities), " retention tier")))
  )
  data.frame(
    SampleID = sample_names[chosen],
    Estimated_Retention_Percent = as.numeric(retention[chosen]),
    Validation_Role = roles,
    stringsAsFactors = FALSE
  )
}

# Static audit-table settings match the workflow reports: horizontal scrolling
# is enabled, while searching, sorting, pagination, and column filters are not.
static_datatable <- function(data, caption = NULL) {
  DT::datatable(
    data,
    rownames = FALSE,
    caption = caption,
    filter = "none",
    options = list(
      scrollX = TRUE,
      paging = FALSE,
      searching = FALSE,
      ordering = FALSE,
      info = FALSE,
      dom = "t",
      autoWidth = TRUE,
      columnDefs = list(list(className = "dt-left", targets = "_all"))
    )
  )
}

console_panel <- bslib::accordion(
  id = "exp_console_accordion", open = "exp_console_panel",
  bslib::accordion_panel(
    title = "Processing Details", value = "exp_console_panel", icon = icon("terminal"),
    div(id = "console_container", class = "console-container",
        div(style = "color:#6c757d;font-style:italic;",
            "Select a FASTQ folder, then load quality profiles."))
  )
)

selection_help <- bslib::accordion(
  id = "exp_help_accordion", open = FALSE,
  bslib::accordion_panel(
    "Help",
    div(class = "help-longform",
        p("Use Select to estimate how many complete primer-trimmed reads would pass candidate maximum expected-error thresholds before running the computationally heavier DADA2 validation or full pipeline."),
        p("For every base with quality score Q, the estimated error probability is 10^(-Q/10). These probabilities are summed across the complete read."),
        tags$ul(
          tags$li("A read passes when EE ≤ maxEE; lower values are stricter."),
          tags$li("Start near maxEE = 2, then look for a useful retention plateau rather than treating the default as universally optimal."),
          tags$li("Inspect the per-sample distribution, bar plot, and table because the pooled curve can hide a weak sample."),
          tags$li("The fast estimate uses quality strings. The Validate tab confirms the choice with real DADA2 processing.")
        ),
        p(class = "small text-muted", "Changing maxEE does not truncate reads and does not replace the fixed target-length or ambiguous-base filters used during validation and Step 5."),
        h5("Retained-read columns"),
        tags$ul(
          tags$li(tags$strong("Sample: "), "sample identifier derived from the primer-trimmed FASTQ filename."),
          tags$li(tags$strong("Reads Evaluated: "), "reads included in the reproducible expected-error sample."),
          tags$li(tags$strong("Reads Passing maxEE: "), "sampled reads whose expected errors are less than or equal to maxEE."),
          tags$li(tags$strong("Retained (%): "), "percentage of evaluated reads passing maxEE."),
          tags$li(tags$strong("Median EE: "), "median expected errors per complete sampled read."),
          tags$li(tags$strong("95th Percentile EE: "), "expected-error value below which 95% of sampled reads fall."))
        ))
  )

ui <- bslib::page_navbar(
  id = "main_nav",
  title = tags$span(icon("dna"), " ", "DADA2 Parameter Explorer"),
  theme = bslib::bs_theme(
    version = 5, bootswatch = "flatly", primary = "#2c3e50",
    secondary = "#95a5a6", success = "#18bc9c", info = "#3498db",
    warning = "#f39c12", danger = "#e74c3c", font_scale = 0.9
  ),
  header = tagList(
    shinyjs::useShinyjs(),
    tags$head(tags$style(HTML("
      .navbar { position:sticky; top:0; z-index:1030; }
      .nav-pills .nav-link.active { background:linear-gradient(135deg,#264653 0%,#2A9D8F 100%); }
      .workflow-separator { color:#95a5a6; padding:.45rem .1rem; }
      .page-intro { margin-bottom:.85rem; } .page-intro h4 { color:#264653; margin-bottom:.15rem; }
      .page-intro p { color:#66747b; margin-bottom:0; }
      .metric-box { background:linear-gradient(135deg,#f8f9fa 0%,#e9ecef 100%); border-radius:10px; padding:1rem; text-align:center; border:1px solid #dee2e6; }
      .metric-value { font-size:1.75rem; font-weight:700; color:#2A9D8F; line-height:1.2; }
      .metric-label { font-size:.8rem; color:#6c757d; text-transform:uppercase; letter-spacing:.5px; }
      .empty-state { min-height:360px; display:flex; flex-direction:column; align-items:center; justify-content:center; text-align:center; color:#6c757d; background:repeating-linear-gradient(135deg,#fff,#fff 12px,#fafbfb 12px,#fafbfb 24px); border:1px dashed #cbd4d8; border-radius:.5rem; padding:2rem; }
      .empty-state .fa,.empty-state .fas { font-size:2rem; color:#95a5a6; }
      .status-strip { display:flex; flex-wrap:wrap; gap:.5rem; margin-bottom:.75rem; }
      .status-chip { background:#eef2f3; border:1px solid #d9e0e3; border-radius:999px; padding:.25rem .65rem; color:#52606d; }
      .console-container { background:#1e1e1e; color:#d4d4d4; font-family:Consolas,Monaco,monospace; font-size:11px; height:clamp(320px,calc(100vh - 500px),480px); overflow-y:auto; white-space:pre-wrap; overflow-wrap:anywhere; padding:.65rem; border-radius:.3rem; }
      table.dataTable th,table.dataTable td { white-space:nowrap !important; text-align:left !important; }
      .maxee-slider .irs-min,.maxee-slider .irs-max { display:none !important; }
      #validation_table { width:100% !important; max-width:100%; }
      #validation_table table.dataTable { table-layout:fixed; width:100% !important; }
      #validation_table table.dataTable td,#validation_table table.dataTable th { white-space:normal !important; word-wrap:break-word; overflow-wrap:break-word; font-size:.78rem; }
      #sample_retention_table { width:100% !important; max-width:100%; }
      #sample_retention_table,#sample_retention_table .dataTables_wrapper { height:100% !important; }
      #sample_retention_table table.dataTable { table-layout:fixed; width:100% !important; height:100% !important; }
      #sample_retention_table table.dataTable td,#sample_retention_table table.dataTable th { white-space:normal !important; word-wrap:break-word; overflow-wrap:break-word; font-size:.82rem; }
      #sample_retention_table table.dataTable tbody td { vertical-align:middle !important; }
      #exp_help_accordion .accordion-button.collapsed,#val_help_accordion .accordion-button.collapsed,#report_help_accordion .accordion-button.collapsed { background:#eef6fa; color:#264653; }
    "))),
    tags$head(tags$script(HTML("
      Shiny.addCustomMessageHandler('console_msg',function(msg){var c=document.getElementById('console_container');if(c){var d=document.createElement('div');d.style.color=msg.color;d.style.marginBottom='2px';var s=document.createElement('span');s.style.color='#6c757d';s.textContent='['+msg.time+'] ';d.appendChild(s);d.appendChild(document.createTextNode(String(msg.text)));c.appendChild(d);c.scrollTop=c.scrollHeight;}});
      Shiny.addCustomMessageHandler('move_console',function(msg){var p=document.getElementById('exp_console_accordion'),a=document.getElementById(msg.slot);if(p&&a&&a.parentElement)a.parentElement.insertBefore(p,a);});
      document.addEventListener('shown.bs.tab',function(event){var value=event.target&&event.target.dataset?event.target.dataset.value:null,p=document.getElementById('exp_console_accordion'),a=value?document.getElementById('console_slot_'+value):null;if(p&&a&&a.parentElement)a.parentElement.insertBefore(p,a);});
      document.addEventListener('click',function(event){var target=event.target.closest&&event.target.closest('.navbar .nav-link[data-value]');if(target){setTimeout(function(){var p=document.getElementById('exp_console_accordion'),a=document.getElementById('console_slot_'+target.dataset.value);if(p&&a&&a.parentElement)a.parentElement.insertBefore(p,a);},0);}});
    ")))
  ),
  bslib::nav_panel(
    title = tags$span(icon("sliders-h"), " Select"), value = "select",
    bslib::layout_sidebar(
      fillable = FALSE,
      sidebar = bslib::sidebar(
        width = 320, open = "always",
        bslib::accordion(
          id = "exp_controls_accordion",
          open = c("exp_data_panel", "exp_parameters_panel"),
          bslib::accordion_panel(
            title = "FASTQ Data", value = "exp_data_panel", icon = icon("folder-open"),
            tags$label(class = "form-label fw-semibold", "Primer-trimmed FASTQ folder"),
            p(class = "small text-muted mb-2",
              "The default project folder is selected automatically; choose another folder if needed."),
            shinyFiles::shinyDirButton("fastq_folder_button", "Choose folder...", "Select FASTQ Directory", class = "btn-outline-primary btn-sm w-100"),
            tags$div(class = "form-text mt-2", "Selected folder"),
            verbatimTextOutput("selected_fastq_folder", placeholder = TRUE),
            actionButton("load_fastq", "Load quality profiles", icon = icon("chart-line"), class = "btn-primary btn-sm w-100 mt-3")
          ),
          bslib::accordion_panel(
            title = "Parameters", value = "exp_parameters_panel", icon = icon("sliders-h"),
            p(class = "small text-muted mb-1", "Select the maximum expected-error threshold for complete reads."),
            p(class = "small text-muted mb-2", "Lower values are stricter; use the plots and per-sample results to guide the choice."),
            div(class = "maxee-slider", sliderInput("selected_maxee", "Maximum expected errors (maxEE)", min = 0, max = 10, value = 2, step = .1)),
            helpText("A read passes when its summed expected errors are ≤ maxEE.")
          )
        ),
        console_panel,
        div(id = "console_slot_select")
      ),
      div(class = "page-intro", h4("Select maxEE"), p("Explore retention of complete, primer-trimmed PacBio HiFi reads without truncation or paired-end settings.")),
      uiOutput("selection_content")
    )
  ),
  bslib::nav_item(tags$span(class = "workflow-separator", ">")),
  bslib::nav_panel(
    title = tags$span(icon("flask"), " Validate"), value = "validate",
    bslib::layout_sidebar(
      fillable = FALSE,
      sidebar = bslib::sidebar(
        width = 340, open = "always",
        bslib::accordion(
          open = "Validation Settings",
          bslib::accordion_panel(
            "Validation Settings",
            uiOutput("validation_parameter_summary"),
            tags$p(class = "text-muted small mb-1", "Choose the number of representative samples."),
            tags$p(class = "text-muted small mb-2", "The recommended value is automatically filled based on the dataset size!"),
            numericInput("validation_n_samples", "Samples to validate", value = 3, min = 1, step = 1),
            checkboxInput("validate_all_samples", "Validate on all loaded samples", FALSE),
            actionButton("run_validation", "Validate with real DADA2", icon = icon("flask"), class = "btn-success btn-sm w-100 mt-2")
          )
        ),
        div(id = "console_slot_validate")
      ),
      div(class = "page-intro", h4("Validate with real DADA2"), p("Confirm the selected threshold with the filtering and PacBio error-learning operations used by Step 5.")),
      uiOutput("validation_status"),
      bslib::card(
        bslib::card_header(
          class = "bg-success text-white py-2",
          tags$span(icon("table"), " Predicted vs. Real Retention per Sample")
        ),
        bslib::card_body(class = "p-2", uiOutput("validation_table_ui"))
      ),
      bslib::accordion(id = "val_help_accordion", open = FALSE,
        bslib::accordion_panel(
          "Help",
          p("Use this tab after choosing a plausible maxEE value in Select. Validation runs the important Step 5 DADA2 operations on representative samples, so it is slower than the sampled expected-error calculation but provides a more realistic check before a full dataset run."),
          h5("How samples and reads are validated"),
          tags$ul(
            tags$li("Samples are selected across the cohort's estimated retention range rather than by filename order. This deliberately includes relatively low-, middle-, and high-retention samples."),
            tags$li("The fixed 1,000–1,600 bp target-length interval and maxN = 0 are applied before the selected maxEE threshold."),
            tags$li("DADA2 then learns a PacBio HiFi error model, infers ASVs independently for each sample, constructs a sequence table, and removes chimeras by the consensus method.")),
          h5("How to interpret the comparison"),
          p("Predicted Filtered % is the fast maxEE estimate from the reproducible quality-string sample loaded in Select. Real Filtered % is measured at the maxEE stage after length and ambiguous-base filtering. Real Non-chim % shows final retention after denoising and chimera removal."),
          p("Prefer a threshold that gives acceptable retention across samples without becoming unnecessarily permissive. Large losses before maxEE point to length or ambiguous-base problems; large losses after denoising or chimera removal cannot be corrected simply by increasing maxEE. Difference (pp) is Predicted Filtered % minus Real Filtered %."),
          p(class = "small text-muted", "Small differences are expected because the fast estimate uses sampled quality strings, whereas empirical validation uses complete reads and sequential preprocessing denominators. Validation is diagnostic and does not replace the complete Step 5 run."),
          h5("Validation-result columns"),
          tags$ul(class = "mb-0",
            tags$li(tags$strong("Sample: "), "sample identifier selected for real DADA2 validation."),
            tags$li(tags$strong("Reads In: "), "complete primer-trimmed reads entering validation."),
            tags$li(tags$strong("Filtered %: "), "percentage of Reads In remaining after target-length filtering, ambiguous-base removal, PhiX removal, and the selected maxEE."),
            tags$li(tags$strong("Denoised %: "), "percentage of Reads In represented by sequence variants inferred by DADA2."),
            tags$li(tags$strong("Predicted Filtered %: "), "percentage predicted to pass maxEE from the reproducible quality-string sample used in Select."),
            tags$li(tags$strong("Real Filtered %: "), "percentage entering the real maxEE stage that passed that stage after target-length and ambiguous-base filtering."),
            tags$li(tags$strong("Real Non-chim %: "), "percentage of Reads In retained after denoising and consensus chimera removal."),
            tags$li(tags$strong("Difference (pp): "), "Predicted Filtered % minus Real Filtered %, expressed in percentage points."))))
    )
  ),
  bslib::nav_item(tags$span(class = "workflow-separator", ">")),
  bslib::nav_panel(
    title = tags$span(icon("file-export"), " Export"), value = "export",
    bslib::layout_sidebar(
      fillable = FALSE,
      sidebar = bslib::sidebar(
        width = 340, open = "always",
        p(class = "small mb-2", "Review the table and save the selected parameters for subsequent pipeline steps."),
        bslib::accordion(open = "Report Settings",
          bslib::accordion_panel("Report Settings",
            tags$small(class = "text-muted", "Parameter workbook:"),
            verbatimTextOutput("export_path_display"),
            actionButton("save_parameters", "Save parameters", icon = icon("floppy-disk"), class = "btn-success btn-sm w-100"),
            helpText("Step 5 reads max_expected_errors from this workbook automatically.")
          )),
        div(id = "console_slot_export")
      ),
      div(class = "page-intro", h4("Export selected parameters"), p("Save the selected numeric maxEE value, sample retention, validation results, and sampling provenance.")),
      bslib::card(bslib::card_header("Parameter preview"), tableOutput("export_parameter_preview")),
      uiOutput("export_status"),
      bslib::accordion(id = "report_help_accordion", open = FALSE,
        bslib::accordion_panel(
          "Help",
          p("Save only after reviewing both the pooled and per-sample Select results. Running empirical validation first is recommended, especially when sample retention varies substantially."),
          p("The workbook is written to the displayed Step 4 results path. Saving again replaces that workbook with the current selection so Step 5 cannot accidentally load an older threshold."),
          tags$ul(
            tags$li(tags$strong("Parameters: "), "the numeric max_expected_errors value that Step 5 reads automatically."),
            tags$li(tags$strong("Sample_Retention: "), "per-sample expected-error summaries for the reproducibly sampled reads."),
            tags$li(tags$strong("DADA2_Validation: "), "empirical validation results; included only when Validate has completed in the current app session."),
            tags$li(tags$strong("Info: "), "input folder, sampling settings, software version, and other provenance."),
            tags$li(tags$strong("Column_Dictionary: "), "plain-language definitions for every exported column.")),
          p(class = "small text-muted mb-0", "After saving, continue with Step 5. Its report states whether maxEE came from this workbook or from the fallback value.")))
    )
  )
)

server <- function(input, output, session) {
  loaded_reads <- reactiveVal(NULL)
  loaded_files <- reactiveVal(NULL)
  selected_fastq_folder <- reactiveVal(fs::path_abs(default_fastq_folder))
  sampling_depth <- reactiveVal(NA_integer_)
  validation_results <- reactiveVal(NULL)
  export_message <- reactiveVal(NULL)

  # Keep one shared, color-coded processing console and move its single DOM
  # node into the active tab's sidebar without losing earlier messages.
  add_console_msg <- function(message, type = "info") {
    colors <- c(info = "#18bc9c", success = "#2ecc71", warning = "#f39c12",
                error = "#e74c3c", progress = "#3498db", validation = "#9b59b6")
    session$sendCustomMessage("console_msg", list(
      time = format(Sys.time(), "%H:%M:%S"), text = as.character(message),
      color = if (type %in% names(colors)) unname(colors[[type]]) else "#d4d4d4"
    ))
  }
  observeEvent(input$main_nav, {
    session$sendCustomMessage("move_console", list(slot = paste0("console_slot_", input$main_nav)))
  }, ignoreInit = FALSE)

  # Use a native directory chooser, as in the Illumina app. Restricting the
  # chooser to the project/home volumes avoids accidentally exposing unrelated
  # filesystem roots in the browser.
  chooser_roots <- c(Project = here::here(), Home = fs::path_home())
  shinyFiles::shinyDirChoose(input, "fastq_folder_button", roots = chooser_roots,
                             session = session)
  observeEvent(input$fastq_folder_button, {
    chosen <- shinyFiles::parseDirPath(chooser_roots, input$fastq_folder_button)
    if (length(chosen) && nzchar(chosen[[1]])) selected_fastq_folder(fs::path_abs(chosen[[1]]))
  })
  output$selected_fastq_folder <- renderText(selected_fastq_folder())
  output$export_path_display <- renderText(fs::path_abs(default_export_path))

  observeEvent(input$load_fastq, {
    folder <- selected_fastq_folder()
    files <- find_fastq_files(folder)
    if (!length(files)) {
      add_console_msg(paste("No FASTQ files were found in", folder), "error")
      showNotification("No FASTQ files were found in the selected folder.", type = "error")
      return()
    }

    sample_ids <- vapply(files, sample_id_from_path, character(1))
    if (anyDuplicated(sample_ids)) {
      add_console_msg("FASTQ filenames produce duplicated SampleID values.", "error")
      return()
    }

    target_reads <- recommended_reads_per_sample(length(files))
    sampling_depth(target_reads)
    add_console_msg("=== PacBio HiFi quality-profile sampling ===", "progress")
    add_console_msg(paste("FASTQ folder:", folder), "info")
    add_console_msg(paste("Found", length(files), "samples."), "success")
    add_console_msg(paste0("Adaptive sampling depth: ", format(target_reads, big.mark = ","),
                           " reads per sample; base seed ", SAMPLING_BASE_SEED, "."), "info")
    add_console_msg("Reservoir-sampling across each complete FASTQ ...", "progress")

    profiles <- withProgress(message = "Reading FASTQ quality scores", value = 0, {
      lapply(seq_along(files), function(index) {
        incProgress(1 / length(files), detail = sample_ids[[index]])
        profile <- read_fastq_expected_errors(
          files[[index]],
          max_reads = target_reads,
          seed = SAMPLING_BASE_SEED + index
        )
        profile$SampleID <- sample_ids[[index]]
        profile$FASTQ_File <- files[[index]]
        profile
      })
    })

    empty_samples <- sample_ids[vapply(profiles, nrow, integer(1)) == 0L]
    if (length(empty_samples)) {
      add_console_msg(paste("No valid FASTQ records were read for:", paste(empty_samples, collapse = ", ")), "error")
      return()
    }

    profile_table <- do.call(rbind, profiles)
    rownames(profile_table) <- NULL
    loaded_reads(profile_table)
    loaded_files(setNames(files, sample_ids))
    validation_results(NULL)
    updateNumericInput(session, "validation_n_samples",
      value = recommended_validation_samples(length(files)), max = length(files))
    add_console_msg(paste("Loaded", format(nrow(profile_table), big.mark = ","),
                          "sampled reads across", length(files), "samples."), "success")
    showNotification(
      paste(format(nrow(profile_table), big.mark = ","), "reads loaded across", length(files), "samples."),
      type = "message"
    )
  })

  retention_summary <- reactive({
    reads <- loaded_reads()
    req(reads)
    threshold <- as.numeric(input$selected_maxee)
    # Preserve the FASTQ manifest order; plain split() would alphabetically
    # reorder character SampleIDs (for example, Sample10 before Sample2).
    sample_order <- unique(reads$SampleID)
    split_reads <- split(reads, factor(reads$SampleID, levels = sample_order))
    rows <- lapply(split_reads, function(sample_reads) {
      retained <- sum(sample_reads$ExpectedErrors <= threshold)
      data.frame(
        SampleID = sample_reads$SampleID[[1]],
        Reads_Evaluated = nrow(sample_reads),
        Reads_EE_le_maxEE = retained,
        Retained_Percent = round(100 * retained / nrow(sample_reads), 2),
        Median_EE = round(stats::median(sample_reads$ExpectedErrors), 3),
        P95_EE = round(as.numeric(stats::quantile(sample_reads$ExpectedErrors, 0.95)), 3),
        stringsAsFactors = FALSE
      )
    })
    do.call(rbind, rows)
  })

  output$selection_content <- renderUI({
    if (is.null(loaded_reads())) {
      return(div(class = "empty-state", icon("chart-line"), h4("No quality profiles loaded"),
                 p("Choose the Step 3 primer-trimmed FASTQ folder and load the profiles to begin."),
                 selection_help))
    }
    tagList(
      bslib::navset_card_pill(
        bslib::nav_panel(
          "maxEE Selection",
          bslib::layout_columns(
            col_widths = c(6, 6),
            bslib::card(
              bslib::card_header(class = "text-white py-2", style = "background-color:#2A9D8F;",
                                 "Read retention across maxEE thresholds"),
              bslib::card_body(class = "p-2", plotly::plotlyOutput("retention_curve", height = "360px"))
            ),
            bslib::card(
              bslib::card_header(class = "text-white py-2", style = "background-color:#2A9D8F;",
                                 "Per-sample expected-error distributions"),
              bslib::card_body(class = "p-2", plotly::plotlyOutput("ee_distribution", height = "360px"))
            )
          )
        ),
        bslib::nav_panel(
          "Retained reads",
          bslib::layout_columns(
            col_widths = c(5, 7),
            bslib::card(
              bslib::card_header(class = "bg-secondary text-white py-2", "Retention by sample"),
              bslib::card_body(class = "p-2", plotly::plotlyOutput("sample_retention_barplot", height = "430px"))
            ),
            bslib::card(
              bslib::card_header(class = "bg-light py-2", "Per-sample retained reads"),
              bslib::card_body(class = "p-2", style = "height:430px;", DT::DTOutput("sample_retention_table", height = "100%"))
            )
          )
        )
      ),
      div(class = "status-strip mt-3",
          span(class = "status-chip", paste(length(loaded_files()), "samples")),
          span(class = "status-chip", paste(format(nrow(loaded_reads()), big.mark = ","), "reads sampled")),
          span(class = "status-chip", paste(format(sampling_depth(), big.mark = ","), "requested/sample")),
          span(class = "status-chip", paste("seed", SAMPLING_BASE_SEED))),
      uiOutput("selection_metrics"),
      div(class = "mt-3", selection_help)
    )
  })

  output$selection_metrics <- renderUI({
    reads <- loaded_reads()
    req(reads)
    retained <- sum(reads$ExpectedErrors <= input$selected_maxee)
    retained_percent <- 100 * retained / nrow(reads)
    fluidRow(
      column(4, div(class = "metric-box", div(class = "metric-value", sprintf("%.1f", input$selected_maxee)), div(class = "metric-label", "Selected maxEE"))),
      column(4, div(class = "metric-box", div(class = "metric-value", format(retained, big.mark = ",")), div(class = "metric-label", "Sampled reads retained"))),
      column(4, div(class = "metric-box", div(class = "metric-value", sprintf("%.1f%%", retained_percent)), div(class = "metric-label", "Pooled retention")))
    )
  })

  output$validation_parameter_summary <- renderUI({
    tags$div(class = "alert alert-light py-2",
             tags$strong("Current maxEE: "), sprintf("%.1f", input$selected_maxee))
  })

  output$validation_status <- renderUI({
    if (is.null(loaded_reads())) {
      return(div(class = "alert alert-warning", "Load FASTQ quality profiles in Select before validation."))
    }
    if (is.null(validation_results())) {
      return(div(class = "status-strip", span(class = "status-chip", "Ready for empirical validation")))
    }
    div(class = "alert alert-success", "Real DADA2 validation completed successfully.")
  })

  output$retention_curve <- plotly::renderPlotly({
    reads <- loaded_reads()
    req(reads)
    thresholds <- seq(0, 20, by = 0.1)
    curve <- data.frame(
      maxEE = thresholds,
      RetainedPercent = vapply(
        thresholds,
        function(threshold) 100 * mean(reads$ExpectedErrors <= threshold),
        numeric(1)
      )
    )
    selected_retention <- 100 * mean(reads$ExpectedErrors <= input$selected_maxee)
    plot <- ggplot2::ggplot(curve, ggplot2::aes(maxEE, RetainedPercent)) +
      ggplot2::geom_line(linewidth = 1, colour = "#18bc9c") +
      ggplot2::geom_vline(xintercept = input$selected_maxee, linetype = 2, colour = "#e74c3c") +
      ggplot2::geom_point(
        data = data.frame(maxEE = input$selected_maxee, RetainedPercent = selected_retention),
        size = 3, colour = "#e74c3c"
      ) +
      ggplot2::annotate(
        "text", x = input$selected_maxee, y = selected_retention,
        label = sprintf("  maxEE %.1f: %.1f%%", input$selected_maxee, selected_retention),
        hjust = 0, vjust = -0.7
      ) +
      ggplot2::scale_x_continuous(limits = c(0, 20), breaks = seq(0, 20, 2)) +
      ggplot2::scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 10)) +
      ggplot2::labs(
        x = "Maximum expected errors (maxEE)",
        y = "Reads retained (%)"
      ) +
      ggplot2::theme_minimal(base_size = 13)
    plotly::ggplotly(plot, tooltip = c("x", "y")) |>
      plotly::config(displaylogo = FALSE, modeBarButtonsToRemove = c("select2d", "lasso2d"))
  })

  output$ee_distribution <- plotly::renderPlotly({
    reads <- loaded_reads()
    req(reads)
    plot_limit <- max(20, as.numeric(stats::quantile(reads$ExpectedErrors, 0.99)))
    plot <- ggplot2::ggplot(reads, ggplot2::aes(ExpectedErrors, colour = SampleID)) +
      ggplot2::stat_ecdf(ggplot2::aes(y = ggplot2::after_stat(y) * 100), linewidth = 0.8) +
      ggplot2::geom_vline(xintercept = input$selected_maxee, linetype = 2, colour = "#e74c3c") +
      ggplot2::coord_cartesian(xlim = c(0, plot_limit)) +
      ggplot2::scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 20),
                                  labels = function(value) paste0(value, "%")) +
      ggplot2::labs(
        x = "Expected errors per complete read",
        y = "Cumulative reads (%)",
        colour = "SampleID"
      ) +
      ggplot2::theme_minimal(base_size = 13)
    plotly::ggplotly(plot, tooltip = c("x", "y", "colour")) |>
      plotly::config(displaylogo = FALSE, modeBarButtonsToRemove = c("select2d", "lasso2d"))
  })

  # Horizontal per-sample retained-read bars provide an immediate cohort
  # comparison while accommodating long SampleID text.
  output$sample_retention_barplot <- plotly::renderPlotly({
    summary <- retention_summary()
    # Preserve the workflow/sample-table order instead of ranking samples by
    # retention. Reversing only the factor levels compensates for a horizontal
    # bar chart drawing its first category at the bottom, so the first sample
    # appears at the top without changing the underlying row order.
    summary$SampleID <- factor(summary$SampleID, levels = rev(summary$SampleID))
    labels <- sprintf("%.1f%%", summary$Retained_Percent)
    plotly::plot_ly(
      summary,
      x = ~Retained_Percent, y = ~SampleID, type = "bar", orientation = "h",
      marker = list(color = "#2A9D8F"), text = labels, textposition = "outside",
      cliponaxis = FALSE,
      hovertemplate = paste0(
        "%{y}<br>Retained %{x:.1f}%<br>",
        "Reads passing: %{customdata[0]:,}<br>Reads evaluated: %{customdata[1]:,}<extra></extra>"
      ),
      customdata = ~cbind(Reads_EE_le_maxEE, Reads_Evaluated)
    ) |>
      plotly::layout(
        xaxis = list(title = "Reads retained (%)", range = c(0, 108), fixedrange = TRUE),
        yaxis = list(title = "", automargin = TRUE, fixedrange = TRUE),
        margin = list(l = 90, r = 45, t = 10, b = 45),
        showlegend = FALSE, paper_bgcolor = "white", plot_bgcolor = "white"
      ) |>
      plotly::config(displayModeBar = FALSE)
  })

  output$sample_retention_table <- DT::renderDT({
    # Use plain-language display labels in the app while leaving the workbook's
    # stable machine-readable column names unchanged.
    display <- retention_summary()
    names(display) <- c(
      "Sample", "Reads Evaluated", "Reads Passing maxEE", "Retained (%)",
      "Median EE", "95th Percentile EE"
    )
    DT::datatable(
      display,
      rownames = FALSE,
      filter = "none",
      options = list(
        scrollX = FALSE, paging = FALSE, searching = FALSE, ordering = FALSE,
        info = FALSE, dom = "t", autoWidth = FALSE,
        columnDefs = list(
          list(width = "14%", targets = 0),
          list(width = "17%", targets = 1),
          list(width = "20%", targets = 2),
          list(width = "16%", targets = 3),
          list(width = "14%", targets = 4),
          list(width = "19%", targets = 5),
          list(className = "dt-left", targets = "_all")
        )
      )
    )
  }, server = FALSE)

  observeEvent(input$run_validation, {
    files <- loaded_files()
    req(files)
    retention <- retention_summary()
    retention_vector <- setNames(retention$Retained_Percent, retention$SampleID)
    n_validate <- if (isTRUE(input$validate_all_samples)) length(files) else input$validation_n_samples
    validation_selection <- select_validation_samples(retention_vector, n_validate)
    selected_samples <- validation_selection$SampleID
    selected_files <- unname(files[selected_samples])
    threshold <- as.numeric(input$selected_maxee)

    add_console_msg("", "info")
    add_console_msg("=== Empirical DADA2 validation ===", "validation")
    add_console_msg(sprintf("Validating maxEE %.1f on %d retention-stratified sample(s).", threshold, length(selected_samples)), "validation")
    for (index in seq_len(nrow(validation_selection))) {
      add_console_msg(sprintf("  - %s (%s; estimated retention %.2f%%)",
        validation_selection$SampleID[[index]], validation_selection$Validation_Role[[index]],
        validation_selection$Estimated_Retention_Percent[[index]]), "info")
    }

    validation_directory <- tempfile("pacbio_maxee_validation_")
    fs::dir_create(validation_directory)
    on.exit(unlink(validation_directory, recursive = TRUE, force = TRUE), add = TRUE)
    length_folder <- fs::path(validation_directory, "length_filtered")
    n_folder <- fs::path(validation_directory, "no_ambiguous_bases")
    final_folder <- fs::path(validation_directory, "maxee_filtered")
    fs::dir_create(c(length_folder, n_folder, final_folder))
    length_paths <- fs::path(length_folder, paste0(selected_samples, ".fastq"))
    n_paths <- fs::path(n_folder, paste0(selected_samples, ".fastq"))
    filtered_paths <- fs::path(final_folder, paste0(selected_samples, ".fastq"))

    append_message <- function(...) {
      add_console_msg(paste0(...), "progress")
    }

    result <- tryCatch(
      withProgress(message = "Running real DADA2 validation", value = 0, {
        append_message("Applying the fixed 1,000–1,600 bp target-length filter ...")
        length_counts <- dada2::filterAndTrim(
          fwd = selected_files,
          filt = length_paths,
          truncLen = 0,
          minLen = 1000,
          maxLen = 1600,
          maxN = Inf,
          maxEE = Inf,
          truncQ = 0,
          minQ = 0,
          rm.phix = FALSE,
          compress = FALSE,
          multithread = FALSE,
          verbose = FALSE
        )
        rownames(length_counts) <- selected_samples

        append_message("Removing reads containing ambiguous bases ...")
        n_counts <- dada2::filterAndTrim(
          fwd = length_paths,
          filt = n_paths,
          truncLen = 0,
          minLen = 1,
          maxLen = Inf,
          maxN = 0,
          maxEE = Inf,
          truncQ = 0,
          minQ = 0,
          rm.phix = FALSE,
          compress = FALSE,
          multithread = FALSE,
          verbose = FALSE
        )
        rownames(n_counts) <- selected_samples

        append_message("Filtering with maxEE = ", threshold, " ...")
        maxee_counts <- dada2::filterAndTrim(
          fwd = n_paths,
          filt = filtered_paths,
          truncLen = 0,
          minLen = 1,
          maxLen = Inf,
          maxN = 0,
          maxEE = threshold,
          truncQ = 0,
          minQ = 0,
          rm.phix = TRUE,
          compress = FALSE,
          multithread = FALSE,
          verbose = FALSE
        )
        rownames(maxee_counts) <- selected_samples
        incProgress(0.25, detail = "Filtering complete")

        retained_samples <- selected_samples[maxee_counts[, "reads.out"] > 0]
        if (!length(retained_samples)) {
          stop("No reads remained after filtering at maxEE = ", threshold, ".")
        }
        retained_paths <- filtered_paths[match(retained_samples, selected_samples)]

        append_message("Learning a PacBio error model from retained reads ...")
        error_model <- dada2::learnErrors(
          retained_paths,
          errorEstimationFunction = dada2::PacBioErrfun,
          # Keep error-learning depth fixed, as in the Illumina app; maxEE is
          # the only parameter this PacBio selection step asks users to tune.
          nbases = 1e8,
          randomize = TRUE,
          BAND_SIZE = 32,
          multithread = FALSE,
          verbose = FALSE,
          MAX_CONSIST = 25
        )
        incProgress(0.30, detail = "Error model learned")

        append_message("Dereplicating and inferring ASVs independently ...")
        dereplicated <- dada2::derepFastq(retained_paths, verbose = FALSE)
        names(dereplicated) <- retained_samples
        denoised <- dada2::dada(
          dereplicated,
          err = error_model,
          BAND_SIZE = 32,
          pool = FALSE,
          multithread = FALSE,
          verbose = FALSE
        )
        incProgress(0.30, detail = "Sample inference complete")

        # Complete empirical validation by assembling inferred sequences into
        # a sequence table and removing chimeras before calculating final
        # sample retention.
        append_message("Building the sequence table and removing chimeras ...")
        sequence_table <- dada2::makeSequenceTable(denoised)
        nonchim_sequence_table <- dada2::removeBimeraDenovo(
          sequence_table,
          method = "consensus",
          multithread = FALSE,
          verbose = FALSE
        )
        nonchim_reads_by_sample <- rowSums(nonchim_sequence_table)
        incProgress(0.15, detail = "Chimera removal complete")

        rows <- lapply(selected_samples, function(sample_id) {
          input_reads <- as.numeric(length_counts[sample_id, "reads.in"])
          after_length <- as.numeric(length_counts[sample_id, "reads.out"])
          after_n <- as.numeric(n_counts[sample_id, "reads.out"])
          filtered_reads <- as.numeric(maxee_counts[sample_id, "reads.out"])
          if (sample_id %in% names(denoised)) {
            denoised_reads <- sum(dada2::getUniques(denoised[[sample_id]]))
            inferred_asvs <- length(dada2::getUniques(denoised[[sample_id]]))
          } else {
            denoised_reads <- 0
            inferred_asvs <- 0
          }
          nonchim_reads <- if (sample_id %in% names(nonchim_reads_by_sample)) {
            as.numeric(nonchim_reads_by_sample[[sample_id]])
          } else 0
          data.frame(
            SampleID = sample_id,
            maxEE = threshold,
            Input_Reads = input_reads,
            After_Length_Filter = after_length,
            After_N_Filter = after_n,
            After_maxEE_Filter = filtered_reads,
            maxEE_Retained_Percent = if (after_n > 0) {
              round(100 * filtered_reads / after_n, 2)
            } else NA_real_,
            Overall_Retained_Percent = round(100 * filtered_reads / input_reads, 2),
            Denoised_Reads = denoised_reads,
            Nonchim_Reads = nonchim_reads,
            Inferred_ASVs = inferred_asvs,
            stringsAsFactors = FALSE
          )
        })
        result_table <- do.call(rbind, rows)
        merge(validation_selection, result_table, by = "SampleID", sort = FALSE)
      }),
      error = function(error) {
        append_message("Validation stopped: ", conditionMessage(error))
        showNotification(conditionMessage(error), type = "error", duration = NULL)
        NULL
      }
    )

    if (!is.null(result)) {
      validation_results(result)
      add_console_msg("Validation completed successfully.", "success")
      showNotification("Real DADA2 validation completed.", type = "message")
    }
  })

  # Match the Illumina app's useful empty state instead of rendering a one-cell
  # placeholder table before validation has been run.
  output$validation_table_ui <- renderUI({
    result <- validation_results()
    if (is.null(result) || !nrow(result)) {
      return(tags$p(
        class = "text-muted mb-0", style = "font-size:0.82rem;",
        "Not yet run. Set your sample count (or check \"Validate on all loaded samples\") ",
        "in the sidebar and click \"Validate with real DADA2\" to see per-sample results here."
      ))
    }
    DT::DTOutput("validation_table", fill = FALSE)
  })

  # Present the PacBio stages using the same compact in-cell horizontal bars as
  # the Illumina validation results. Counts remain unscaled; every percentage
  # is calculated against the relevant input and displayed on a common 0-100
  # scale. Difference (pp) uses the Illumina teal/orange/red diagnostic tiers.
  output$validation_table <- DT::renderDT({
    result <- validation_results()
    if (is.null(result) || !nrow(result)) return(NULL)

    safe_percent <- function(numerator, denominator) {
      ifelse(denominator > 0, round(100 * numerator / denominator, 1), NA_real_)
    }
    display <- data.frame(
      Sample = result$SampleID,
      `Reads In` = format(result$Input_Reads, big.mark = ","),
      `Filtered %` = round(result$Overall_Retained_Percent, 1),
      `Denoised %` = safe_percent(result$Denoised_Reads, result$Input_Reads),
      `Predicted Filtered %` = round(result$Estimated_Retention_Percent, 1),
      `Real Filtered %` = round(result$maxEE_Retained_Percent, 1),
      `Real Non-chim %` = safe_percent(result$Nonchim_Reads, result$Input_Reads),
      `Difference (pp)` = round(
        result$Estimated_Retention_Percent - result$maxEE_Retained_Percent, 1
      ),
      check.names = FALSE,
      stringsAsFactors = FALSE
    )

    difference_max <- max(1, max(abs(display$`Difference (pp)`), na.rm = TRUE))
    difference_bar <- DT::JS(sprintf(
      "isNaN(parseFloat(value)) ? '' : (function(v, maxAbs) {
        var absV = Math.abs(v);
        var transparent = (maxAbs - Math.min(absV, maxAbs)) / maxAbs * 100;
        var color = absV <= 5 ? '#18bc9c' : (absV <= 15 ? '#f39c12' : '#e74c3c');
        return 'linear-gradient(270deg, transparent ' + transparent + '%%, ' + color + ' ' + transparent + '%%)';
      })(value, %f)", difference_max
    ))

    table_widget <- DT::datatable(
      display,
      rownames = FALSE,
      class = "compact stripe hover",
      filter = "none",
      options = list(
        scrollX = FALSE, paging = FALSE, searching = FALSE, ordering = FALSE,
        info = FALSE, dom = "t", autoWidth = FALSE,
        columnDefs = list(
          list(width = "14%", targets = 0),
          list(width = "10%", targets = 1),
          list(width = "12%", targets = 2),
          list(width = "12%", targets = 3),
          list(width = "15%", targets = 4),
          list(width = "13%", targets = 5),
          list(width = "13%", targets = 6),
          list(width = "11%", targets = 7),
          list(className = "dt-left", targets = "_all")
        )
      )
    )

    percentage_columns <- c(
      "Filtered %", "Denoised %", "Predicted Filtered %", "Real Filtered %",
      "Real Non-chim %"
    )
    percentage_colors <- c(
      "#6f42c1", "#2A9D8F", "#3498db", "#18bc9c", "#95a5a6"
    )
    for (column_index in seq_along(percentage_columns)) {
      table_widget <- DT::formatStyle(
        table_widget,
        percentage_columns[[column_index]],
        background = DT::styleColorBar(c(0, 100), percentage_colors[[column_index]], angle = 270),
        backgroundSize = "98% 88%", backgroundRepeat = "no-repeat",
        backgroundPosition = "right"
      )
    }
    DT::formatStyle(
      table_widget, "Difference (pp)", background = difference_bar,
      backgroundSize = "98% 88%", backgroundRepeat = "no-repeat",
      backgroundPosition = "right"
    )
  }, server = FALSE)

  parameter_preview <- reactive({
    data.frame(
      Parameter = "max_expected_errors",
      Value = as.numeric(input$selected_maxee),
      stringsAsFactors = FALSE
    )
  })
  output$export_parameter_preview <- renderTable(parameter_preview(), align = "l")

  observeEvent(input$save_parameters, {
    req(loaded_reads())
    workbook_path <- fs::path_abs(default_export_path)
    add_console_msg("=== Export parameter workbook ===", "progress")
    fs::dir_create(fs::path_dir(workbook_path), recurse = TRUE)
    if (fs::file_exists(workbook_path)) fs::file_delete(workbook_path)

    parameters <- parameter_preview()
    retention <- retention_summary()
    info <- data.frame(
      Field = c(
        "Created", "FASTQ_Folder", "Samples", "Reads_Evaluated",
        "Selection_Method", "Sampling_Method", "Requested_Reads_Per_Sample",
        "Sampling_Base_Seed", "Validation_Run", "DADA2_Version"
      ),
      Value = c(
        format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
        selected_fastq_folder(),
        length(unique(loaded_reads()$SampleID)),
        nrow(loaded_reads()),
        "Empirical per-read expected-error retention curve",
        "Reproducible reservoir sample across each complete FASTQ",
        sampling_depth(),
        SAMPLING_BASE_SEED,
        if (is.null(validation_results())) "No" else "Yes",
        as.character(utils::packageVersion("dada2"))
      ),
      stringsAsFactors = FALSE
    )

    add_sheet_to_excel(workbook_path, "Parameters", parameters)
    add_sheet_to_excel(workbook_path, "Sample_Retention", retention)
    if (!is.null(validation_results())) {
      add_sheet_to_excel(workbook_path, "DADA2_Validation", validation_results())
    }
    add_sheet_to_excel(workbook_path, "Info", info)

    dictionaries <- list(
      build_column_dictionary(
        "Parameters", parameters,
        c(
          Parameter = "Step 5 variable name for the selected DADA2 expected-error threshold.",
          Value = "Numeric maximum expected errors; a read passes when its expected errors are less than or equal to this value."
        ), workbook_path
      ),
      build_column_dictionary(
        "Sample_Retention", retention,
        c(
          SampleID = "Sample identifier derived from the Step 3 primer-trimmed FASTQ filename.",
          Reads_Evaluated = "Number of reads sampled from this FASTQ for the fast expected-error calculation.",
          Reads_EE_le_maxEE = "Sampled reads whose expected errors are less than or equal to the selected maxEE.",
          Retained_Percent = "Percentage of sampled reads passing the selected maxEE.",
          Median_EE = "Median expected errors per complete sampled read.",
          P95_EE = "95th percentile of expected errors per complete sampled read."
        ), workbook_path
      ),
      build_column_dictionary(
        "Info", info,
        c(
          Field = "Provenance field recorded for this parameter-selection export.",
          Value = "Recorded value for the provenance field."
        ), workbook_path
      )
    )
    if (!is.null(validation_results())) {
      validation <- validation_results()
      dictionaries <- append(dictionaries, list(build_column_dictionary(
        "DADA2_Validation", validation,
        c(
          SampleID = "Sample selected for real DADA2 validation.",
          Estimated_Retention_Percent = "Expected maxEE retention estimated from the reproducible FASTQ sample.",
          Validation_Role = "Retention tier used for cohort-stratified validation sample selection.",
          maxEE = "Maximum expected-error threshold used by filterAndTrim().",
          Input_Reads = "Reads entering real DADA2 filtering.",
          After_Length_Filter = "Reads retained after the fixed 1,000–1,600 bp target-length filter.",
          After_N_Filter = "Reads retained after removing sequences containing ambiguous bases.",
          After_maxEE_Filter = "Reads retained after applying the selected maxEE and PhiX filters.",
          maxEE_Retained_Percent = "Percentage of reads entering the maxEE stage that pass the selected threshold.",
          Overall_Retained_Percent = "Percentage of original input reads retained after all validation filters.",
          Denoised_Reads = "Reads represented in the inferred dada object.",
          Nonchim_Reads = "Denoised reads retained after consensus chimera removal.",
          Inferred_ASVs = "Unique sequence variants inferred for this sample during validation."
        ), workbook_path
      )))
    }
    column_dictionary <- do.call(rbind, dictionaries)
    add_sheet_to_excel(workbook_path, "Column_Dictionary", column_dictionary)

    export_message(paste("Saved:", workbook_path))
    add_console_msg(paste("Saved:", workbook_path), "success")
    showNotification("maxEE parameter workbook saved.", type = "message")
  })

  output$export_status <- renderUI({
    message <- export_message()
    if (is.null(message)) return(NULL)
    div(class = "alert alert-success", message)
  })
}

shinyApp(ui, server)
