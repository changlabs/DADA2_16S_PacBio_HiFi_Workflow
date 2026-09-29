# Workflow input data

This folder contains the PacBio HiFi FASTQ archives, sequencing sample sheet, and optional sample-level tables used for a user's normal workflow run. The supplied tables are editable templates populated with placeholder rows; replace them with study-specific values before interpreting downstream results.

## Bundled example data

The clone-ready example is intentionally stored under [`example/data/`](../example/data/) instead of this normal input directory. It is a 20,000-read PacBio Sequel CCS/HiFi subset from BioProject [`PRJNA521754`](https://www.ncbi.nlm.nih.gov/bioproject/PRJNA521754), targeting the full-length bacterial 16S rRNA gene (V1–V9). Its primer-bearing reads exercise Step 3, and its metadata follows the layout documented below.

Run the complete example from the repository root with:

```bash
Rscript example/run_example.R
```

This runs all Steps 1–9 with both SILVA and GTDB and writes only to the ignored `example/run_results/` directory. The prepared Step 4 workbook is read directly by Step 5. Rendered reports and curated outputs can be viewed without running anything under [`example/reference_results/`](../example/reference_results/). See [`example/README.md`](../example/README.md) for source accessions, primer sequences, synthetic cell-count disclosure, third-party-data notice, and the Callahan et al. (2019) dataset citation.

## Folder contents

- [FASTQ input folder](fastq/) contains the demultiplexed PacBio HiFi FASTQ archives organized in lowercase pool folders such as `pool1` and `pool2`.
- [Sample sheet](sample_sheet.xlsx) maps each sample to its pool and barcode pair using `PoolNumber`, `SampleID`, `ForwardBarcodeID`, and `ReverseBarcodeID`. Barcode nucleotide sequences are not required for these already-demultiplexed FASTQs.
- [Sample metadata](metadata.tsv) contains sample annotations for downstream construction and analysis of the phyloseq object.
- [Cell-count table](cell_count/cell_count.tsv) contains sample-level cell counts for microbial-load correction.

## Sample identifiers and pool numbers

`SampleID` must be unique across the complete run and must match exactly in the sample sheet, metadata table, cell-count table, and workflow outputs.

`PoolNumber` identifies the sequencing pool. It is the first column in both TSV files and must match the value assigned to the sample in the [sample sheet](sample_sheet.xlsx).

The workflow uses `PoolNumber` to create and propagate the pool-specific results under the `separate_pools` output folder when more than one pool is present.

## Metadata table

The [metadata template](metadata.tsv) is a tab-separated text file with one row per sample. `PoolNumber` is the first column so downstream analyses retain the sequencing-pool provenance of every sample.

| Column | Description |
|:-----------------------------------|:-----------------------------------|
| `PoolNumber` | Numeric sequencing-pool identifier matching the sample sheet. |
| `SampleID` | Unique sample identifier matching the sample sheet and ASV count table. |
| `SubjectID` | Identifier for the subject or experimental unit. |
| `Treatment` | Experimental group or treatment assignment. |
| `Timepoint` | Sampling time point. |
| `SampleType` | Sample category, specimen type, or control type. |
| `Batch` | Experimental or laboratory batch. |

The columns after `SampleID` are examples. They may be renamed, removed, or extended to represent the study design. Keep `PoolNumber` and `SampleID` unchanged because those two columns provide the workflow joins; avoid spaces or punctuation in any new column names so they remain easy to use in R.

## Cell-count table

The [cell-count template](cell_count/cell_count.tsv) is a tab-separated text file with one row per sample.

| Column | Description |
|:-----------------------------------|:-----------------------------------|
| `PoolNumber` | Numeric sequencing-pool identifier matching the sample sheet. |
| `SampleID` | Unique sample identifier matching the sample sheet and ASV count table. |
| `Cell_Count` | Positive numeric cell-count measurement used for microbial-load correction. |

Replace the demonstration values in `Cell_Count` with measured values before running microbial-load correction. Use the same measurement unit and method for every sample. Do not include commas, unit labels, or other text in this column.

## Consistency checks before analysis

Before running the downstream steps, confirm that:

1.  Every `SampleID` is unique within each table.
2.  The same spelling and capitalization are used for `SampleID` in all input files.
3.  Every sample has the same `PoolNumber` in the sample sheet, metadata table, and cell-count table.
4.  Every pool is represented by a lowercase input folder such as `data/fastq/pool1`.
5.  `PoolNumber` and `Cell_Count` contain numeric values rather than text.
6.  Placeholder metadata and cell counts have been replaced with study values.
7.  No required values are blank.

Rows can be added or removed, but each retained row must still map unambiguously to one workflow sample and pool. Samples may be omitted from the optional metadata or cell-count table only when the downstream analysis that needs that table is also omitted; Step 8 specifically requires a valid positive cell count for every sample it processes.
