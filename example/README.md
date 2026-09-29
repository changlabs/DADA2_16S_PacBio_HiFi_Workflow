# Bundled PacBio HiFi example

This directory contains a self-contained test profile for the complete workflow. It is deliberately separate from [`data/`](../data/) and the generated `results/` directory: running it cannot mix the example reads with a user's FASTQ files, and adding another dataset to `data/fastq/` cannot alter the example run.

The source material is a deterministic 5,000-read subset from each of four PacBio Sequel CCS/HiFi fecal-sample runs used in the DADA2 full-length 16S analysis. It targets the bacterial **full-length V1–V9 16S rRNA gene**, not an Illumina V4 amplicon. The reads retain their sequenced primers so Step 3 produces real trimming results.

## Contents

- `data/fastq/pool1/Callahan-Fecal-HiFi-Example.fastq.zip`: 20,000 reads in four Lima-style archive members.
- `data/sample_sheet.xlsx`: maps the archive barcodes to descriptive sample names.
- `data/metadata.tsv`: sample annotations in the workflow's normal metadata layout, with SRA and BioSample provenance.
- `data/cell_count/cell_count.tsv`: required, clearly labelled synthetic microbial loads for Steps 8 and 9.
- `data/dada2_filter_parameters.xlsx`: prepared Step 4 handoff selecting `maxEE = 2`, which Step 5 reads directly.
- `reference_results/`: curated outputs and rendered reports from all Steps 1–9 for viewing without running the workflow.
- `run_example.R`: executes the complete example without reading or modifying the normal `data/fastq/` or `results/` trees.

## Run the complete example

First install the repository's R dependencies, project-local Cutadapt and FastTree tools, PICRUSt2, and both SILVA and GTDB reference databases as described in the root [`README.md`](../README.md). Then run this command from the repository root:

```bash
Rscript example/run_example.R
```

The command runs Steps 1–3, renders the Step 4 guide and copies its prepared parameter workbook into the isolated run results, and then runs Steps 5–9. All steps are required for this example. Step 5 assigns both SILVA and GTDB taxonomy; those parallel taxonomy branches are retained in the labelled Step 6 trees and all six Step 9 database-by-abundance phyloseq objects. Generated files go only to the ignored `example/run_results/` directory.

The prepared Step 4 workbook records expected-error retention calculated from the bundled, primer-trimmed reads. Its selected `maxEE = 2` matches the source PacBio DADA2 analysis and is loaded by Step 5 through `DADA2_PARAMETER_FILE`; the example never falls back to the notebook's generic setting.

New example runs use SILVA 144 and the SBDI Sativa-curated GTDB R11-RS232-1 files installed by the setup script. The committed reference reports were generated before this database update and retain their original version labels; they were not regenerated for the setup-only change.

To inspect results without installing or running anything, open the HTML files in [`reference_results/reports/`](reference_results/reports/) or use the repository's GitHub Pages site. The Step 4 report is a rendered guide, while the accompanying workbook is the actual non-interactive parameter handoff used by Step 5.

The bundled result is methodologically comparable to the official analysis, but its numerical ASV totals and abundance tables are not expected to be identical: this repository uses fixed 5,000-read subsets from four of the source runs, whereas the published analysis used the complete experiment. The reference run retained 19,329 non-chimeric reads and inferred 238 ASVs. These values are regression expectations for this bundled subset, not targets for the full BioProject.

## Primers and read orientation

The FASTQ archive contains the original sequenced primer-bearing CCS reads. Step 3 uses the same full-length bacterial primers as the source DADA2 analysis:

- F27: `AGRGTTYGATYMTGGCTCAG`
- R1492 reference oligo: `RGYTACCTTGTTACGACTT`
- read-oriented reverse sequence used in the linked Cutadapt adapter: `AAGTCGTAACAAGGTARCY`

Cutadapt is called with `F27...read-oriented-R1492`, `--trimmed-only`, `--revcomp`, and an error rate of `0.1`. In this deterministic subset, 19,663 of 20,000 reads contain the complete linked primer pair and pass Step 3; the remaining reads provide realistic failed-trimming cases.

## Included source runs and renamed samples

| SRA run | BioSample | Original library | Bundled `SampleID` | Reads |
|:---|:---|:---|:---|---:|
| `SRR8557472` | `SAMN10910592` | `R3_1_P3C3` | `Subject-R3-Timepoint-1` | 5,000 |
| `SRR8557475` | `SAMN10910593` | `R3_2_P3C3` | `Subject-R3-Timepoint-2` | 5,000 |
| `SRR8557476` | `SAMN10910594` | `R3_3_P3C3` | `Subject-R3-Timepoint-3` | 5,000 |
| `SRR8557478` | `SAMN10910600` | `R11_1_P3C3` | `Subject-R11-Timepoint-1` | 5,000 |

The subset selection used a fixed pseudorandom seed derived from BioProject `PRJNA521754`. Filenames were changed only inside the bundled archive so they follow this workflow's Lima barcode convention and remain understandable after mapping.

## Data provenance and citation

The source dataset is BioProject [`PRJNA521754`](https://www.ncbi.nlm.nih.gov/bioproject/PRJNA521754), generated on the PacBio Sequel platform using replicate-2 S/P3-C3/5.0 chemistry and described in the official [DADA2 PacBio fecal analysis](https://benjjneb.github.io/LRASManuscript/LRASms_fecal.html). The four bundled subsets were retrieved from the NCBI Sequence Read Archive on 29 September 2026.

Please cite the dataset-generating study:

> Callahan BJ, Wong J, Heiner C, Oh S, Theriot CM, Gulati AS, McGill SK, Dougherty MK. (2019). High-throughput amplicon sequencing of the full-length 16S rRNA gene with single-nucleotide resolution. *Nucleic Acids Research*, 47(18), e103. <https://doi.org/10.1093/nar/gkz569>

When describing the analysis, also cite DADA2:

> Callahan BJ, McMurdie PJ, Rosen MJ, Han AW, Johnson AJA, Holmes SP. (2016). DADA2: High-resolution sample inference from Illumina amplicon data. *Nature Methods*, 13, 581–583. <https://doi.org/10.1038/nmeth.3869>

## Third-party data notice

The FASTQ reads are third-party human-fecal research data from the cited study. Their inclusion does not place them under this repository's MIT software license; attribution and any applicable rights remain with the original authors and data repository. The archive contains sequencing reads and public accession identifiers, not participant identifiers or clinical metadata.
