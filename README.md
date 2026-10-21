# Replication package: the 2025 QSBS expansion and start-up fundraising (Form D)

Code, data and output for the manuscript

> Ibragimov, A., and N. Ruzieva. 2026. "Did the 2025 Expansion of Qualified Small Business Stock Relief Move Start-Up Fundraising? Early Evidence from Form D Notices." Manuscript under review.

The paper asks whether the expansion of the Section 1202 (Qualified Small Business Stock) capital-gains exclusion enacted on 4 July 2025 (Public Law 119-21) changed private capital raising by the firms it targets. It uses the universe of SEC Form D notices filed by operating companies with first sales from January 2019 to September 2026 and compares C-corporations in QSBS-eligible industries with other corporations and with LLCs, before and after enactment.

## Contents

| Path | What it is |
|---|---|
| `qsbs2025_replication.do` | Main Stata do-file. Unzips and loads `data/clean/offerings.dta`, builds the analysis sample and the cell panels, estimates every model, writes Tables 1–8 and A4–A6 to `tables/` and Figures 1–5 and A1–A3 to `figures/`, and ends with a block of checks that prints each estimate next to the value quoted in the manuscript (Section 15). The synthetic control of Figure 3 is implemented in Mata inside the file. |
| `qsbs2025_text_numbers.do` | Prints, with five decimals, every coefficient, standard error and p-value quoted in the tables and text of the paper. Run it after the main do-file, from the same folder. |
| `prep.py` | Python script that builds `data/clean/offerings.dta` (and `.xlsx`) from the quarterly SEC Form D Data Sets: original notices, first-sale date, amounts reported in amendments filed within 180 days, the issuer's round number since 2008, the sample restrictions of Table 1 and all 35 variables (documented in the file and in Supplemental Table A3). |
| `update_quarter.py` | Extends an existing `offerings.dta` with one further quarterly archive without re-reading the full history (new original notices, amendments within 180 days, round numbers continued from the existing file). Used to add the 2026Q3 archive on 20 October 2026. |
| `data/clean/offerings.zip` | The estimation input `offerings.dta`, compressed (28 MB → 3 MB): 108,850 original Form D notices with a first sale on or after 1 January 2019, 35 variables (SEC archives 2008Q1–2026Q3). The do-file unzips it automatically. |
| `data/clean/offerings.xlsx` | The same data as an Excel workbook (sheet `offerings`; dates as text `YYYY-MM-DD`) for readers without Stata. The do-file falls back to it if neither the `.zip` nor the `.dta` is present. |
| `data/clean/table1_sample_construction.csv` | Counts of notices and issuers after each sample-construction step, produced by the data build. The do-file types these counts into Table 1 and adds the last two rows (the 15 September 2026 cut-off and the classification into eligible and excluded industries), so the last row of this file (49,791) precedes the cut-off applied in the paper (49,707). |
| `data/state_conformity.csv` | Coding of each state's income-tax treatment of Section 1202 gain during the observation window (Supplemental Table A2), with the coding rules, confidence level, notes and sources for every state. The do-file carries the same coding inline (nothing is read with `import delimited`, which needs Java); this file documents it. |
| `logs/` | Stata logs (`.smcl`) of the run behind the submitted version (20 October 2026, data through 2026Q3): `qsbs2025_replication.smcl` (main file) and `qsbs2025_text_numbers.smcl` (every number quoted in the paper, with five decimals). The `paper:` strings that Section 15 of the main log prints next to each estimate are the values of the June 2026 data vintage that the run was compared against; the do-file in this repository carries the values of the submitted version (the strings are display-only and do not affect any estimate). |
| `tables/`, `figures/` | The output of that run: tables as `.rtf` and `.csv`, figures as `.png`, plus the data behind the event-study and synthetic-control figures (`fig*.csv`). Running the do-file regenerates all of them. |

The quarterly SEC archives themselves (75 files, about 1 GB) are not redistributed; see *Data* below.

## Data

Source: U.S. Securities and Exchange Commission, *Form D Data Sets*, https://www.sec.gov/data-research/sec-markets-data/form-d-data-sets (public domain). The paper uses all 75 quarterly data sets from 2008Q1 to 2026Q3: the 2008Q1–2026Q2 archives were processed in September 2026 with `prep.py`, and the 2026Q3 archive (published by the SEC on 2 October 2026) was added on 20 October 2026 with `update_quarter.py`. Because a substantial share of notices is filed after the 15-day deadline, the most recent quarters change when the SEC publishes later vintages; the counts in the paper refer to this vintage, which is the vintage of the shipped `offerings.dta`.

`prep.py` re-implements, as a single script, the construction of `offerings.dta` described in Section 3.2 and Supplemental Table A3 of the paper. To rebuild the file, place the quarterly archives in `data/raw/` and run

```
python prep.py            # writes data/clean/offerings.dta, offerings.xlsx, table1_sample_construction.csv
python prep.py --check    # writes offerings_rebuilt.dta instead and reports, variable by variable,
                          # how closely it matches the shipped offerings.dta
```

Requirements: Python 3.10 or later, `pandas` 2.x, `openpyxl` (Excel output only); 5–15 minutes and about 4 GB of memory for the full set of archives.

Columns of `data/state_conformity.csv`: `conform`, `nonconform`, `partial`, `notax` (mutually exclusive indicators), `static_conformity`, `state_shock` (the state changed its own treatment during the window), `drop_in_robustness` (DC, NJ, OR and WA are dropped in the robustness checks), `confidence`, `note`, `source`.

## Requirements for the Stata part

* Stata 14 or later. User-written packages: `require`, `ftools`, `reghdfe`, `ppmlhdfe`, `estout`, `coefplot`. The do-file installs any missing package from SSC on the first run (internet required); if a folder `ado/` with offline copies is placed in the package root, it is used instead. If `reghdfe` reports a Mata error after installation, run `ftools, compile` and `reghdfe, compile` once.
* No Java is needed: the do-file reads nothing with `import delimited`.

## How to run

1. Download or clone this repository and open Stata.
2. Change to the package folder and run the main file:

   ```stata
   cd "C:\path\to\qsbs2025-formd-replication"
   do qsbs2025_replication.do
   ```

   Run it with `do` (or from the Do-file Editor), not by pasting into the Command window: `///` continuations and `{ }` blocks only work when the file is executed as a whole. The first run unzips the data and installs packages; the estimation itself takes a few minutes (the logged run of 20 October 2026 completed in under a minute on a desktop PC). The results appear in `tables/` and `figures/`, the log in `qsbs2025_replication.smcl`.
3. To print every number quoted in the manuscript:

   ```stata
   do qsbs2025_text_numbers.do
   ```

   It reads the datasets that the main file saves in `data/clean/` (`analysis_sample`, `panel_corp_quarterly`, `panel_main_monthly`, `panel_main_quarterly`, `retiming_weekly`) and takes well under a minute.

## Where each table and figure is produced

| Manuscript | Section of `qsbs2025_replication.do` | Output file(s) |
|---|---|---|
| Table 1 | 1 | `tables/tab1_sample_construction.csv` |
| Table 2 | 2 | `tables/tab2_by_group.csv` |
| Table A4 | 2 | `tables/tabA4_correlations.*` |
| Figure 1 | 3 | `figures/fig1_raw_counts.png` |
| Cell panels (inputs to Tables 3, 8, A5, A6) | 4 | `data/clean/panel_*.dta` |
| Table 3 | 5 | `tables/tab3_counts.*` |
| Figures 2, 4 and A1 (event studies) | 6 | `figures/fig2_es_counts_corps.png`, `fig4_es_amounts_corps.png`, `figA1a_es_counts_ddd.png`, `figA1b_es_amounts_ddd.png` and the matching `tables/*.csv` |
| Figure 3 (synthetic control) | 7 | `figures/fig3_synthetic_control.png`; `tables/fig3_synth_path.csv`, `fig3_synth_weights.csv`, `fig3_synth_placebos.csv` |
| Table 4 | 8 | `tables/tab4_panelA.*`, `tab4_panelB.*` |
| Table 5 | 9 | `tables/tab5_panelA.*`, `tab5_panelB.*` |
| Table 6 | 10 | `tables/tab6_conformity.*` |
| Figure 5 and Table 7 | 11 | `figures/fig5_retiming.png`, `tables/tab7_retiming.*`, `data/clean/retiming_weekly.dta` |
| Table 8, Panel A and Figure A3 | 12 | `tables/tab8_panelA_ri_placebos.csv` (four post-reform quarters, as in the paper; `_3post.csv` for comparison), `figures/figA3_placebo_distribution.png` |
| Table 8, Panel B | 13 | `tables/tab8_panelB_robustness.*` |
| Tables A5, A6 and Figure A2 | 14 | `tables/tabA5_pretrend.*`, `tabA6_variance.*`, `figures/figA2_llc_check.png` |
| Checks against the manuscript | 15 | printed at the end of the log |

Supplemental Tables A1–A3 are documentation (industry mapping, state coding, variable definitions) and are not estimated.

## Main variables

Definitions follow Supplemental Table A3 of the paper. In `offerings.dta`: `accessionnumber`, `cik` (primary issuer), `state`, `industry_raw` (Form D industry group), `qsbs_group` (eligible / excluded / ambiguous, Table A1), `entity` (corp / llc), `filing_date`, `sale_date`, `event_date` (first-sale date, filing date when missing), `sale_date_missing`, `rev_range`, `amount_sold` (original notice), `amount_sold_180d` (maximum reported within 180 days), `n_investors`, `n_investors_180d`, `min_investment`, `offering_amount`, `round_no` (the issuer's notices since 2008), `first_formd`, `priced_equity`, `safe_flag`, `convertible_flag`, `sec_equity`, `sec_debt`, `sec_other`, `rule506b`, `rule506c`, `rule504`, `inc_within_5y`, `inc_year`, `delaware_inc`, `ai_name_flag`, `is_fund`, `bus_combination`, `in_sample`.

Created by the do-file: `elig`, `corp`, `post` (first sale after 4 July 2025), `ep = elig × post`, `cp = corp × post`, `ecp = elig × corp × post`, `ambig`, `ln_sold`, `ln_sold_orig`, `big_round`, `ln_inv`, `ln_minin`, `repeat`, `late_rev` (revenue above USD 5 million), `safe_or_note`, `conform`, `notax`, `drop_in_robustness`, `st_gr` and `st_gr_corp` (cluster and fixed-effect identifiers), `ym`, `yq`; in the cell panels the counts `n` and `n_first` by state × group × entity × period with the identifiers `cell` and `st_el`.

## Citation

If you use this code or data, please cite the paper above and this repository (see `CITATION.cff`).

## Licence

The code is released under the MIT Licence (see `LICENSE`). The data files are derived from public-domain SEC filings; the state conformity coding is released under the same terms as the code.
