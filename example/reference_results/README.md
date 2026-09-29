# Reference results

These are curated outputs from `Rscript example/run_example.R`, generated on 29 September 2026 from the bundled Callahan et al. PacBio HiFi subset with R 4.5.2, DADA2 1.36.0, DECIPHER 3.4.0, phyloseq 1.52.0, Cutadapt 5.2, FastTree 2.2.0, PICRUSt2 2.6.3, SILVA 138.2, and GTDB r220. These database versions describe the historical outputs accurately. The current setup and future example runs use SILVA 144 and SBDI-GTDB R11-RS232-1; the reports were not rerun for that setup-only update. The supplied Step 4 workbook represents the non-interactive expected-error parameter handoff used directly by Step 5.

The `reports/` directory contains rendered HTML reports for every step. Steps 1–3 and 5–9 are executed reports; Step 4 is the rendered parameter-selection guide accompanied by the prepared workbook. Together, the compact step folders contain:

- the archive/sample-mapping audit, quality/length summaries, plots, and primer-trimming summary;
- the exact Step 4 `maxEE = 2` workbook read by Step 5;
- 238 inferred ASVs, the sample-by-ASV table, SILVA and GTDB taxonomy tables, processing summary, error model, quality profiles, and amplicon-length plot;
- the alignment, ASV-labelled tree, SILVA- and GTDB-labelled Newick trees and PDFs, and tree summary;
- PICRUSt2 copy-number-corrected and microbial-load-corrected abundance tables with their audit workbooks; and
- six final tree-bearing phyloseq objects: raw, copy-number-corrected, and microbial-load-corrected abundance for each of SILVA and GTDB, plus both summary workbooks.

Reproducible FASTQ intermediates, checkpoints, console logs, PICRUSt2 placement files, and separate interactive barplot dependency folders are intentionally omitted. Rerunning the example recreates them under the ignored `example/run_results/` tree and never overwrites these committed reference results automatically.

The cell-count inputs used by Steps 8 and 9 are synthetic test values, not measurements from the source study. Do not use them for biological interpretation. See [`../data/cell_count/README.md`](../data/cell_count/README.md) for the assumptions and supporting references.

For provenance, sample mapping, primer definitions, and the complete test command, see the parent [`example/README.md`](../README.md).
