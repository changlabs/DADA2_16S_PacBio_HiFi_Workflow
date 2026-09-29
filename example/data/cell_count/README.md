# Synthetic cell-count fixture

The four `Cell_Count` values in [`cell_count.tsv`](cell_count.tsv) are **synthetic test values**, expressed as cells per gram of feces. They are required inputs so the bundled example executes Step 8 and subsequently builds microbial-load-corrected phyloseq objects in Step 9. They are not measurements from the Callahan et al. PacBio study and must not be used for biological interpretation or method validation.

The values range from `1.8e10` to `4.1e10` cells per gram. This scale is biologically plausible for human fecal material: flow-cytometry measurements in De Volder et al. ranged from `1.2e10` to `5.3e10` cells per gram (median `2.3e10`) while following the quantitative microbiome profiling framework of Vandeputte et al. The modest within-subject variation for subject R3 is included to exercise the quantitative workflow; no biological trend is being claimed.

References:

- De Volder L et al. (2020). *How to Count Our Microbes? The Effect of Different Quantitative Microbiome Profiling Approaches*. Frontiers in Cellular and Infection Microbiology 10:403. <https://doi.org/10.3389/fcimb.2020.00403>
- Vandeputte D et al. (2017). *Quantitative microbiome profiling links gut community variation to microbial load*. Nature 551:507–511. <https://doi.org/10.1038/nature24460>
