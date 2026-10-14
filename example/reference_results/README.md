# Reference results

View the [example landing page](https://changlabs.github.io/DADA2_16S_PacBio_HiFi_Workflow/) or browse the saved outputs below. No installation or execution is required. Example sequencing inputs are not included in the repository.

These are curated analysis outputs, generated on 29 September 2026 from the Callahan et al. PacBio HiFi subset with R 4.5.2, DADA2 1.36.0, DECIPHER 3.4.0, phyloseq 1.52.0, Cutadapt 5.2, FastTree 2.2.0, PICRUSt2 2.6.3, SILVA 138.2, and GTDB r220. These database versions describe the historical outputs accurately. The current setup uses SILVA 144 and SBDI-GTDB R11-RS232-1; saved reports retain the historical database versions above. The supplied Step 4 workbook represents the non-interactive expected-error parameter handoff used directly by Step 5.

The `reports/` directory contains rendered HTML reports for every step. Steps 1–3 and 5–9 are executed reports; Step 4 is the rendered parameter-selection guide accompanied by the prepared workbook. Together, the compact step folders contain:

- the original FASTQ sample-mapping audit, quality/length summaries, plots, and primer-trimming summary;
- the exact Step 4 `maxEE = 2` workbook read by Step 5;
- 238 inferred ASVs, the sample-by-ASV table, SILVA and GTDB taxonomy tables, processing summary, error model, quality profiles, and amplicon-length plot;
- the alignment, ASV-labelled tree, SILVA- and GTDB-labelled Newick trees and PDFs, and tree summary;
- PICRUSt2 copy-number-corrected and microbial-load-corrected abundance tables with their audit workbooks; and
- six final tree-bearing phyloseq objects: raw, copy-number-corrected, and microbial-load-corrected abundance for each of SILVA and GTDB, plus both summary workbooks.

Reproducible FASTQ intermediates, checkpoints, console logs, PICRUSt2 placement files, and separate interactive barplot dependency folders are intentionally omitted. Links to saved outputs and tracked workflow source files remain clickable in the executed reports; omitted runtime targets are displayed as annotated plain text instead of broken links.

The cell-count inputs used by Steps 8 and 9 are synthetic test values, not measurements from the source study. Do not use them for biological interpretation. See [`../data/cell_count/README.md`](../data/cell_count/README.md) for the assumptions and supporting references.

For provenance, sample mapping, primer definitions, and analysis details, see the parent [`example/README.md`](../README.md).

On 8 October 2026, Steps 1–3 were refreshed using individual gzip FASTQ inputs and the updated workflow; their HTML reports, summary workbooks, and Step 2 plots were replaced. Step 4's HTML guide was regenerated. `per_read_statistics.tsv.gz` is now included alongside Step 2's summary workbook. Step 1 exports an optional `Unlisted_FASTQs` sheet, accepts case-insensitive pool folder names, and matches literal sample-sheet barcode pairs, including Kinnex names. The example subset uses four direct gzip files with unchanged reads.

Steps 5–9 retain their original executed biological results and embedded code, with their provenance documented here. They predate the input and compression changes. Current sources write gzip FASTQs in Steps 2, 3, all three Step 5 filtering stages, and the Step 4 app's temporary validation stages. Displayed user home paths in the reports use `/Users/jon/`; portable result links remain relative.

Step 2 was refreshed again for all-read distribution histograms and exact length quantiles. Both distribution PDFs use six sample facets per page; only read-length facets annotate the inclusive 1,800–2,000 bp count. QV facets annotate the QV-passing count. Frequency caches are temporary and the per-read TSV is never loaded for plotting, so memory does not scale with audit size.

Step 1 was refreshed for the mapping-only handoff: original FASTQs are validated in place, `Sample_Manifest` contains project-relative `SourceFASTQPath` values, and no copied `mapped_fastq/` dataset is produced. Step 2 reads those original paths and retains sample-named filtered outputs.

The Step 1 workbook now omits duplicated filename and barcode columns, repeated matched/validated counts, and the full inventory of already mapped files. `Unlisted_FASTQs` is exported only when needed; `SourceSampleID` appears only when sanitization changes an identifier. Its six core manifest columns preserve the downstream handoff.
