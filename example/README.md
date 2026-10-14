# Example run

View the [example landing page](https://changlabs.github.io/DADA2_16S_PacBio_HiFi_Workflow/) or browse the [saved results](reference_results/) without installing or running anything. The example sequencing inputs are not included in the repository. Supporting metadata and configuration document the saved analysis.

## Contents

- `data/sample_sheet.xlsx`: maps the filename barcodes to descriptive sample names.
- `data/metadata.tsv`: sample annotations in the workflow's normal metadata layout, with SRA and BioSample provenance.
- `data/cell_count/cell_count.tsv`: required, clearly labelled synthetic microbial loads for Steps 8 and 9.
- `data/dada2_filter_parameters.xlsx`: prepared Step 4 handoff selecting `maxEE = 2`, which Step 5 reads directly.
- `reference_results/`: curated outputs and rendered reports from all Steps 1–9 for viewing without running the workflow.

## Saved analysis

The saved run used four deterministic 5,000-read subsets (20,000 reads total), the prepared Step 4 `maxEE = 2` workbook, and both SILVA and GTDB. It retained 19,329 non-chimeric reads and inferred 238 ASVs. These values describe the subset, not the full BioProject. Saved report versions are documented in [reference-results notes](reference_results/README.md).

## Primers and read orientation

The input FASTQs used for the saved analysis contained the original sequenced primer-bearing CCS reads. Step 3 uses the same full-length bacterial primers as the source DADA2 analysis:

- F27: `AGRGTTYGATYMTGGCTCAG`
- R1492 reference oligo: `RGYTACCTTGTTACGACTT`
- read-oriented reverse sequence used in the linked Cutadapt adapter: `AAGTCGTAACAAGGTARCY`

Cutadapt is called with `F27...read-oriented-R1492`, `--trimmed-only`, `--revcomp`, and an error rate of `0.1`. In this deterministic subset, 19,663 of 20,000 reads contain the complete linked primer pair and pass Step 3; the remaining reads provide realistic failed-trimming cases.

## Included source runs and renamed samples

| SRA run | BioSample | Original library | Example `SampleID` | Reads |
|:---|:---|:---|:---|---:|
| `SRR8557472` | `SAMN10910592` | `R3_1_P3C3` | `Subject-R3-Timepoint-1` | 5,000 |
| `SRR8557475` | `SAMN10910593` | `R3_2_P3C3` | `Subject-R3-Timepoint-2` | 5,000 |
| `SRR8557476` | `SAMN10910594` | `R3_3_P3C3` | `Subject-R3-Timepoint-3` | 5,000 |
| `SRR8557478` | `SAMN10910600` | `R11_1_P3C3` | `Subject-R11-Timepoint-1` | 5,000 |

The subset selection used a fixed pseudorandom seed derived from BioProject `PRJNA521754`. Filenames were changed in the example subset so they follow the source example's conventional barcode naming and remain understandable after mapping.

## Data provenance and citation

The source dataset is BioProject [`PRJNA521754`](https://www.ncbi.nlm.nih.gov/bioproject/PRJNA521754), generated on the PacBio Sequel platform using replicate-2 S/P3-C3/5.0 chemistry and described in the official [DADA2 PacBio fecal analysis](https://benjjneb.github.io/LRASManuscript/LRASms_fecal.html). The four example subsets were retrieved from the NCBI Sequence Read Archive on 29 September 2026.

Please cite the dataset-generating study:

> Callahan BJ, Wong J, Heiner C, Oh S, Theriot CM, Gulati AS, McGill SK, Dougherty MK. (2019). High-throughput amplicon sequencing of the full-length 16S rRNA gene with single-nucleotide resolution. *Nucleic Acids Research*, 47(18), e103. <https://doi.org/10.1093/nar/gkz569>

When describing the analysis, also cite DADA2:

> Callahan BJ, McMurdie PJ, Rosen MJ, Han AW, Johnson AJA, Holmes SP. (2016). DADA2: High-resolution sample inference from Illumina amplicon data. *Nature Methods*, 13, 581–583. <https://doi.org/10.1038/nmeth.3869>

## Third-party data notice

The input FASTQs are third-party research data and are not included in the repository. Saved results retain public accession identifiers and study subject codes (`R3` and `R11`) for provenance. The MIT software license does not grant rights to the original sequencing data. No direct personal identifiers are included.
