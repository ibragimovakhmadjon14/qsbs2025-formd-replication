*==============================================================================*
* qsbs2025_replication.do
* Replication file for: "Did the 2025 expansion of Qualified Small Business Stock
* relief move start-up fundraising? Early evidence from Form D notices"
* (Ibragimov and Ruzieva, 2026)
*
* Input : data/clean/offerings.dta (built from the SEC Form D Data Sets 2008Q1-2026Q2 by
*         prep.py and extended with the 2026Q3 archive by update_quarter.py; the package
*         ships it compressed as data/clean/offerings.zip and this file unzips it;
*         data/clean/offerings.xlsx is used if neither is present)
* Output: tables/  (rtf and csv: Tables 1-8, A4-A6)
*         figures/ (png: Figures 1-5, A1-A3)
*         qsbs2025_replication.smcl (log, ending with a block of checks against the manuscript)
*
* HOW TO RUN
*   1. Keep the folder structure of the package: this file at the top level, the data in
*      data/clean. In Stata type (with your own folder):
*        cd "C:\path\to\qsbs2025-formd-replication"
*        do qsbs2025_replication.do
*      or open the file in the Do-file Editor and click Execute (do).
*   2. Do NOT paste the contents into the Command window: line continuations and
*      code blocks only work when the file is run with -do-.
*   3. Stata 14 or later. The user-written packages require, ftools, reghdfe, ppmlhdfe,
*      estout and coefplot are installed from SSC on the first run (internet needed); if a
*      folder ado/ with offline copies is placed in the package folder it is used instead.
*      The synthetic control (Section 7) is implemented in Mata below and needs no package.
*      If reghdfe reports a Mata error after installation, run once:  ftools, compile
*      and  reghdfe, compile.
*   4. Nothing is read with -import delimited- (it needs Java): the state coding of
*      Supplemental Table A2 (data/state_conformity.csv) and the counts of the first
*      rows of Table 1 (data/clean/table1_sample_construction.csv) are typed in below.
*   5. Running time: a few minutes (longer on the first run, which installs packages). Run
*      qsbs2025_text_numbers.do afterwards to print every number quoted in the manuscript
*      with five decimals.
*
* The estimates reported in the manuscript are the ones produced by this file on the
* 2008Q1-2026Q3 data (log in logs/). Section 15 prints each of them next to the value
* quoted in the paper. Small differences in the last decimal can arise across Stata versions from
* the PPML convergence criterion.
*==============================================================================*
version 14
clear all
set more off
if c(stata_version) < 16 set matsize 5000
set seed 20250704
capture log close
log using "qsbs2025_replication.smcl", replace
foreach s in chk_late_n chk_late_nreg chk_h4_b chk_h4_se chk_h4_N chk_a4_b chk_a4_se chk_b1_b chk_b1_se ///
             chk_nat_b chk_nat_se_ols chk_nat_se_nw1 chk_nat_se_nw2 chk_prim_b chk_prim_se chk_ddd_b chk_ddd_se ///
             chk_h3_b chk_h3_se chk_h3_N chk_p_rep chk_p_late chk_fd_b chk_fd_se chk_t7_se1 chk_t7_se2 ///
             sc_pre sc_gap_mean sc_p sc_gmin sc_gmax sc_ngood sc_nd {
    scalar `s' = .
}

*------------------------------------------------------------------------------*
* 0. Paths, packages, graph style
*------------------------------------------------------------------------------*
di as result _n "===== SECTION 0. Paths, packages, graph style ====="
* If you did not -cd- into the package folder, write its path here (keep the quotes):
global ROOT ""
* example:  global ROOT "C:\Users\user\Downloads\qsbs2025_stata_package"
if `"$ROOT"' != "" cd `"$ROOT"'
* The package ships the input compressed (data/clean/offerings.zip, GitHub's file-size limit):
* unzip it once if offerings.dta is not there yet
foreach cand in "data/clean" "qsbs2025_stata_package/data/clean" "." {
    cap confirm file "`cand'/offerings.dta"
    if _rc != 0 {
        cap confirm file "`cand'/offerings.zip"
        if _rc == 0 {
            local here "`c(pwd)'"
            qui cd "`cand'"
            di as text "unzipping offerings.zip ..."
            cap noisily unzipfile "offerings.zip", replace
            qui cd "`here'"
        }
    }
}
* Locate the data: the package folder, a qsbs2025_stata_package subfolder, or the current folder
local found ""
foreach cand in "data/clean" "qsbs2025_stata_package/data/clean" "." {
    if "`found'" == "" {
        cap confirm file "`cand'/offerings.dta"
        if _rc == 0 local found "`cand'"
        else {
            cap confirm file "`cand'/offerings.xlsx"
            if _rc == 0 local found "`cand'"
        }
    }
}
if "`found'" == "" {
    di as error "offerings.dta / offerings.xlsx not found in " c(pwd) " (searched data/clean, qsbs2025_stata_package/data/clean and the folder itself)."
    di as error `"Type   cd "C:\path\to\qsbs2025_stata_package"   and run the do-file again."'
    exit 601
}
global D "`found'"
di as text "data folder: `found'"
global T "tables"
global F "figures"
cap mkdir "$T"
cap mkdir "$F"
* user-written packages: offline copies first (folder ado, or ado_offline_update\ado if the
* update zip was extracted into its own folder), then SSC
foreach pkg in require ftools reghdfe ppmlhdfe estout coefplot {
    cap which `pkg'
    if _rc != 0 {
        di as text "installing `pkg' ..."
        local done = 0
        foreach cand in "ado_offline_update/ado" "ado" "qsbs2025_stata_package/ado" {
            if `done' == 0 {
                cap confirm file "`cand'/`pkg'/`pkg'.pkg"
                if _rc == 0 {
                    cap noisily net install `pkg', from("`c(pwd)'/`cand'/`pkg'") replace
                    if _rc == 0 local done = 1
                }
            }
        }
        cap which `pkg'
        if _rc != 0 cap ssc install `pkg', replace
    }
}
cap ftools, compile
cap reghdfe, compile
* reghdfe must actually run: version 6 checks for -require- and for ftools >= 2.50
local upd ""
foreach cand in "ado_offline_update/ado" "ado" "qsbs2025_stata_package/ado" {
    if "`upd'" == "" {
        cap confirm file "`cand'/require/require.pkg"
        if _rc == 0 local upd "`cand'"
    }
}
clear
qui set obs 200
gen double x = rnormal()
gen int g = mod(_n, 10)
gen double y = x + rnormal()
cap noisily reghdfe y x, absorb(g)
if _rc != 0 & "`upd'" != "" {
    di as text "reghdfe did not run; reinstalling require, ftools, reghdfe and ppmlhdfe from `upd'"
    foreach pkg in require ftools reghdfe ppmlhdfe {
        cap noisily net install `pkg', from("`c(pwd)'/`upd'/`pkg'") replace
    }
    discard
    cap ftools, compile
    cap reghdfe, compile
    cap noisily reghdfe y x, absorb(g)
}
if _rc != 0 {
    di as error "reghdfe does not run. Put ado_offline_update.zip into the package folder (next to this"
    di as error "do-file), extract it there, and run this file again."
    exit 199
}
clear
cap which ppmlhdfe
if _rc != 0 {
    di as error "ppmlhdfe is not installed: no internet access to SSC and no offline copy found in `c(pwd)'/ado."
    di as error "Unzip the full package (it contains the ado folder) and run again."
    exit 199
}
set scheme s1mono
graph set window fontface "Times New Roman"
local star "star(* 0.10 ** 0.05 *** 0.01)"

*------------------------------------------------------------------------------*
* 1. Analysis sample and variables (mirrors prep.py)
*------------------------------------------------------------------------------*
di as result _n "===== SECTION 1. Analysis sample and variables (mirrors prep.py) ====="
* Data: either data/clean/offerings.dta or data/clean/offerings.xlsx (same variables; dates in the
* Excel file are text "YYYY-MM-DD" and are converted below)
cap confirm file "$D/offerings.dta"
if _rc == 0 {
    use "$D/offerings.dta", clear
}
else {
    cap confirm file "$D/offerings.xlsx"
    if _rc != 0 {
        di as error "Neither data/clean/offerings.dta nor data/clean/offerings.xlsx found. Type -pwd-: the working directory must be the unzipped package folder."
        exit 601
    }
    import excel "$D/offerings.xlsx", sheet("offerings") firstrow clear
    foreach v in filing_date sale_date event_date {
        cap confirm string variable `v'
        if _rc == 0 {
            gen double `v'_d = date(`v', "YMD")
            drop `v'
            rename `v'_d `v'
        }
        else {
            local f : format `v'
            if strpos("`f'", "tc") > 0 replace `v' = dofc(`v')
        }
        format `v' %td
    }
    * make sure the numeric fields did not arrive as strings
    foreach v in in_sample sale_date_missing amount_sold amount_sold_180d n_investors n_investors_180d ///
                 min_investment offering_amount round_no first_formd priced_equity safe_flag convertible_flag ///
                 sec_equity sec_debt sec_other rule506b rule506c rule504 inc_within_5y inc_year delaware_inc ///
                 ai_name_flag is_fund bus_combination {
        cap confirm string variable `v'
        if _rc == 0 destring `v', replace force
    }
    foreach v in accessionnumber cik state qsbs_group industry_raw entity rev_range {
        cap confirm numeric variable `v'
        if _rc == 0 tostring `v', replace
    }
}
keep if in_sample == 1
keep if inlist(qsbs_group, "eligible", "excluded", "ambiguous")
format event_date %td

* end of data = last filing date; drop the 15-day filing-lag tail and date typos
qui sum filing_date
local data_end = r(max)
local lastday  = `data_end' - 15
drop if event_date > `lastday'
di as text "filings end " %td `data_end' ", sample ends " %td `lastday'

gen reform = td(04jul2025)
gen post   = event_date > reform
gen elig   = qsbs_group == "eligible"
gen ambig  = qsbs_group == "ambiguous"
gen corp   = entity == "corp"
gen ym     = mofd(event_date)
gen yq     = qofd(event_date)
gen year   = yofd(event_date)
format ym %tm
format yq %tq

gen ln_sold      = ln(amount_sold_180d) if amount_sold_180d > 0
gen ln_sold_orig = ln(amount_sold)      if amount_sold > 0
gen ln_inv       = ln(1 + n_investors_180d)
gen ln_minin     = ln(1 + min_investment)
gen big_round    = amount_sold_180d >= 10e6 if amount_sold_180d < .
gen repeat       = round_no > 1
* Revenue above USD 5 million (H3; Table 5, columns 3-4), the cut-off of the published
* estimates. The Form D revenue ranges are 1 - 1,000,000 / 1,000,001 - 5,000,000 /
* 5,000,001 - 25,000,000 / 25,000,001 - 100,000,000 / Over 100,000,000 / No Revenues /
* Decline to Disclose / Not Applicable. "5,000,001" matches the ranges 5,000,001 - 25,000,000
* and 25,000,001 - 100,000,000; "over" matches Over 100,000,000.
gen late_rev     = (strpos(rev_range, "5,000,001") > 0 | strpos(rev_range, "5000001") > 0 | ///
                    strpos(lower(rev_range), "over") > 0)
* revenue above USD 25 million: used only for a sensitivity check printed after Table 5
gen rev25        = (strpos(rev_range, "25,000,001") > 0 | strpos(rev_range, "25000001") > 0 | ///
                    strpos(lower(rev_range), "over") > 0)
gen safe_or_note = (safe_flag == 1 | convertible_flag == 1)
gen amount_m     = amount_sold / 1e6

gen group4 = 1 if elig == 1 & corp == 1
replace group4 = 2 if elig == 0 & corp == 1 & ambig == 0
replace group4 = 3 if elig == 1 & corp == 0
replace group4 = 4 if elig == 0 & corp == 0 & ambig == 0
label define group4 1 "Eligible C-corps" 2 "Excluded C-corps" 3 "Eligible LLCs" 4 "Excluded LLCs"
label values group4 group4

di as result _n "Revenue ranges in the main sample (late_rev = revenue above USD 5 million):"
tab rev_range late_rev if ambig == 0, missing
qui count if late_rev == 1 & ambig == 0
scalar chk_late_n = r(N)
qui count if late_rev == 1 & ambig == 0 & ln_sold < .
scalar chk_late_nreg = r(N)
di as result "CHECK late_rev: " scalar(chk_late_n) " main-sample offerings with revenue above USD 5 million (expected 1023), " ///
    scalar(chk_late_nreg) " of them with ln(amount sold) (expected 785; Table 5, column 4 has N = 670 after reghdfe drops singletons)"

egen st_gr      = group(state qsbs_group)
egen st_gr_corp = group(state qsbs_group corp)
gen ep  = elig * post
gen cp  = corp * post
gen ecp = elig * corp * post
label var ep  "Eligible x Post"
label var cp  "Corp x Post"
label var ecp "Eligible x Corp x Post"

* state conformity (Appendix Table A2) = data/state_conformity.csv, typed in so that no file
* has to be imported
preserve
clear
input str2 state conform nonconform partial notax state_shock drop_in_robustness
"AL" 0 1 0 0 0 0
"AK" 0 0 0 1 0 0
"AZ" 1 0 0 0 0 0
"AR" 1 0 0 0 0 0
"CA" 0 1 0 0 0 0
"CO" 1 0 0 0 0 0
"CT" 1 0 0 0 0 0
"DE" 1 0 0 0 0 0
"DC" 0 1 0 0 1 1
"FL" 0 0 0 1 0 0
"GA" 1 0 0 0 0 0
"HI" 0 0 1 0 0 0
"ID" 1 0 0 0 0 0
"IL" 1 0 0 0 0 0
"IN" 1 0 0 0 0 0
"IA" 1 0 0 0 0 0
"KS" 1 0 0 0 0 0
"KY" 1 0 0 0 0 0
"LA" 1 0 0 0 0 0
"ME" 1 0 0 0 0 0
"MD" 1 0 0 0 0 0
"MA" 1 0 0 0 0 0
"MI" 1 0 0 0 0 0
"MN" 1 0 0 0 0 0
"MS" 0 1 0 0 0 0
"MO" 1 0 0 0 1 0
"MT" 1 0 0 0 0 0
"NE" 1 0 0 0 0 0
"NV" 0 0 0 1 0 0
"NH" 0 0 0 1 0 0
"NJ" 1 0 0 0 1 1
"NM" 1 0 0 0 0 0
"NY" 1 0 0 0 0 0
"NC" 1 0 0 0 0 0
"ND" 1 0 0 0 0 0
"OH" 1 0 0 0 0 0
"OK" 1 0 0 0 0 0
"OR" 0 1 0 0 1 1
"PA" 0 1 0 0 0 0
"RI" 1 0 0 0 0 0
"SC" 1 0 0 0 0 0
"SD" 0 0 0 1 0 0
"TN" 0 0 0 1 0 0
"TX" 0 0 0 1 0 0
"UT" 1 0 0 0 0 0
"VT" 1 0 0 0 0 0
"VA" 1 0 0 0 0 0
"WA" 0 0 0 0 0 1
"WV" 1 0 0 0 0 0
"WI" 1 0 0 0 0 0
"WY" 0 0 0 1 0 0
end
tempfile conf
save `conf'
restore
merge m:1 state using `conf', keep(1 3)
qui count if _merge == 1
if r(N) > 0 di as error "WARNING: " r(N) " offerings have a state code that is not in Table A2"
drop _merge
di as result _n "Offerings by eligible C-corporations by state conformity group (Section 4.5):"
gen str24 conf_group = cond(conform == 1, "conforming", cond(nonconform == 1, "non-conforming", ///
    cond(notax == 1, "no tax on capital gains", cond(partial == 1, "Hawaii (partial)", "Washington"))))
tab conf_group if elig == 1 & corp == 1 & ambig == 0
drop conf_group
save "$D/analysis_sample.dta", replace

* ---- Table 1: sample construction (Form D counts from prep.py, data/clean/table1_sample_construction.csv) ---------
preserve
clear
input str72 step notices issuers
"All Form D submissions, 2008Q1-2026Q3 (original notices and amendments)" 778966 .
"Original notices" 478216 .
"First sale on or after 1 January 2019" 264408 219536
"Excluding pooled investment funds" 131879 92165
"Excluding business-combination offerings" 126290 89302
"Issuers located in the 50 states and DC" 117720 84870
"Corporations and LLCs only" 108850 76991
"First sale on or before 15 September 2026 (broad sample)" 108631 76825
"Classifiable industry group, eligible or excluded (main sample)" 49707 30774
end
format notices issuers %9.0fc
list, noobs clean
export delimited using "$T/tab1_sample_construction.csv", replace
restore
* the last two rows recomputed from the data
qui count
local nb = r(N)
qui count if ambig == 0
local nmain = r(N)
local ib = .
local im = .
cap confirm variable cik
if _rc == 0 {
    egen byte _tb = tag(cik)
    qui count if _tb == 1
    local ib = r(N)
    egen byte _tm = tag(cik) if ambig == 0
    qui count if _tm == 1
    local im = r(N)
    drop _tb _tm
}
di as result "CHECK Table 1: broad sample " %9.0fc `nb' " offerings by " %9.0fc `ib' " issuers   (paper: 108,631 by 76,825)"
di as result "CHECK Table 1: main sample  " %9.0fc `nmain' " offerings by " %9.0fc `im' " issuers   (paper: 49,707 by 30,774)"
tab group4 if ambig == 0

*------------------------------------------------------------------------------*
* 2. Table 2: descriptive statistics by treatment group
*------------------------------------------------------------------------------*
di as result _n "===== SECTION 2. Table 2: descriptive statistics by treatment group ====="
use "$D/analysis_sample.dta", clear
keep if ambig == 0
gen one = 1
preserve
collapse (sum) n_offerings = one (mean) share_post = post amount_mean = amount_m ///
    first_share = first_formd priced_share = priced_equity safe_share = safe_or_note ///
    c506_share = rule506c young_share = inc_within_5y de_share = delaware_inc ///
    (median) amount_median = amount_m investors_median = n_investors_180d minin_median = min_investment, by(group4)
export delimited using "$T/tab2_by_group.csv", replace
list, noobs clean
restore

* Table A4: pairwise correlations
eststo clear
estpost correlate elig corp post ln_sold ln_inv ln_minin first_formd priced_equity, matrix listwise
esttab using "$T/tabA4_correlations.rtf", replace unstack not noobs nonumber b(2) ///
    title("Table A4. Pairwise correlations, main sample")
* CSV copy of the same table (opens in Excel):
esttab using "$T/tabA4_correlations.csv", replace unstack not noobs nonumber b(2) ///
    title("Table A4. Pairwise correlations, main sample")

*------------------------------------------------------------------------------*
* 3. Figure 1: monthly counts by group, indexed to the 2023 mean
*------------------------------------------------------------------------------*
di as result _n "===== SECTION 3. Figure 1: monthly counts by group, indexed to the 2023 mean ====="
collapse (sum) n = one, by(group4 ym)
bys group4: egen base = mean(cond(ym >= tm(2023m1) & ym <= tm(2023m12), n, .))
gen idx = 100 * n / base
twoway (line idx ym if group4 == 1, lcolor(black) lwidth(thick)) ///
       (line idx ym if group4 == 2, lcolor(gs6) lpattern(dash)) ///
       (line idx ym if group4 == 3, lcolor(gs8) lpattern(shortdash)) ///
       (line idx ym if group4 == 4, lcolor(gs10) lpattern(dot)), ///
    xline(`=tm(2025m7)', lpattern(dash) lcolor(gs8)) ///
    legend(order(1 "Eligible C-corps" 2 "Excluded C-corps" 3 "Eligible LLCs" 4 "Excluded LLCs") rows(2) size(small)) ///
    xtitle("") ytitle("Original Form D notices (2023 average = 100)") ///
    xlabel(`=tm(2019m1)'(12)`=tm(2026m1)', format(%tmCY))
graph export "$F/fig1_raw_counts.png", replace width(2400)

*------------------------------------------------------------------------------*
* 4. Cell panels
*------------------------------------------------------------------------------*
di as result _n "===== SECTION 4. Cell panels ====="
* 4a. quarterly panel of C-corporations, broad control (state x eligible x quarter)
use "$D/analysis_sample.dta", clear
keep if corp == 1
drop if inrange(event_date, td(01jul2025), td(04jul2025))
keep if yq <= tq(2026q2)                         // 2026Q3 is a partial quarter
gen one = 1
collapse (sum) n = one, by(state elig yq)
fillin state elig yq
replace n = 0 if _fillin
drop _fillin
egen cell = group(state elig)
gen post = yq >= tq(2025q3)
gen ep = elig * post
label var ep "Eligible x Post"
save "$D/panel_corp_quarterly.dta", replace

* 4b. monthly panel, main sample (state x eligible x corp x month)
use "$D/analysis_sample.dta", clear
keep if ambig == 0
drop if inrange(event_date, td(01jul2025), td(04jul2025))
keep if ym <= tm(2026m8)
gen one = 1
collapse (sum) n = one (sum) n_first = first_formd, by(state elig corp ym)
fillin state elig corp ym
replace n = 0 if _fillin
replace n_first = 0 if _fillin
drop _fillin
egen cell  = group(state elig corp)
egen st_el = group(state elig)
gen post = ym >= tm(2025m7)
gen ep  = elig * post
gen ecp = elig * corp * post
gen ln_n = ln(1 + n)
label var ep  "Eligible x Post"
label var ecp "Eligible x Corp x Post"
save "$D/panel_main_monthly.dta", replace

* 4c. quarterly panel, main sample (for the triple-difference event study and RI)
use "$D/analysis_sample.dta", clear
keep if ambig == 0
drop if inrange(event_date, td(01jul2025), td(04jul2025))
keep if yq <= tq(2026q2)
gen one = 1
collapse (sum) n = one, by(state elig corp yq)
fillin state elig corp yq
replace n = 0 if _fillin
drop _fillin
egen cell  = group(state elig corp)
egen st_el = group(state elig)
gen post = yq >= tq(2025q3)
gen ecp = elig * corp * post
label var ecp "Eligible x Corp x Post"
save "$D/panel_main_quarterly.dta", replace

*------------------------------------------------------------------------------*
* 5. Table 3: counts of original notices
*------------------------------------------------------------------------------*
di as result _n "===== SECTION 5. Table 3: counts of original notices ====="
eststo clear
use "$D/panel_corp_quarterly.dta", clear
ppmlhdfe n ep if yq >= tq(2023q1), absorb(cell yq) vce(cluster cell)
estadd scalar pct = 100 * (exp(_b[ep]) - 1)
eststo m1
ppmlhdfe n ep, absorb(cell yq) vce(cluster cell)
estadd scalar pct = 100 * (exp(_b[ep]) - 1)
eststo m2
use "$D/panel_main_monthly.dta", clear
ppmlhdfe n ep if corp == 1, absorb(cell ym) vce(cluster st_el)
estadd scalar pct = 100 * (exp(_b[ep]) - 1)
eststo m3
ppmlhdfe n ep if corp == 0, absorb(cell ym) vce(cluster st_el)
estadd scalar pct = 100 * (exp(_b[ep]) - 1)
eststo m4
ppmlhdfe n ecp, absorb(cell elig#ym corp#ym) vce(cluster st_el)
estadd scalar pct = 100 * (exp(_b[ecp]) - 1)
eststo m5
ppmlhdfe n_first ecp, absorb(cell elig#ym corp#ym) vce(cluster st_el)
estadd scalar pct = 100 * (exp(_b[ecp]) - 1)
eststo m6
esttab m1 m2 m3 m4 m5 m6 using "$T/tab3_counts.rtf", replace se `star' b(3) label keep(ep ecp) ///
    stats(pct N r2_p, fmt(1 %9.0fc 3) labels("Implied change, %" "Observations (cells)" "Pseudo-R2")) ///
    mtitles("C-corps broad 2023Q1-26Q2" "C-corps broad 2019Q1-26Q2" "C-corps narrow monthly" ///
            "LLCs narrow monthly" "DDD monthly" "DDD first-time") ///
    title("Table 3. Difference-in-differences and triple-difference estimates: counts of original notices")
* CSV copy of the same table (opens in Excel):
esttab m1 m2 m3 m4 m5 m6 using "$T/tab3_counts.csv", replace se `star' b(3) label keep(ep ecp) ///
    stats(pct N r2_p, fmt(1 %9.0fc 3) labels("Implied change, %" "Observations (cells)" "Pseudo-R2")) ///
    mtitles("C-corps broad 2023Q1-26Q2" "C-corps broad 2019Q1-26Q2" "C-corps narrow monthly" ///
            "LLCs narrow monthly" "DDD monthly" "DDD first-time") ///
    title("Table 3. Difference-in-differences and triple-difference estimates: counts of original notices")

*------------------------------------------------------------------------------*
* 6. Quarterly event studies (Figures 2, 4, A1) - reference period 2024
*------------------------------------------------------------------------------*
di as result _n "===== SECTION 6. Quarterly event studies (Figures 2, 4, A1) - reference period 2024 ====="
cap program drop qes
program define qes
    * qes depvar treatvar [if], absorb() cluster() file() ytitle() [ols last(quarter, default 2026q2)]
    syntax varlist(min=2 max=2) [if], absorb(string) cluster(string) file(string) ytitle(string) [ols last(string)]
    tokenize `varlist'
    local dep `1'
    local trt `2'
    if "`last'" == "" local last "2026q2"
    local qa = tq(2023q1)
    local qb = tq(`last')
    local nq = `qb' - `qa' + 1
    preserve
    if `"`if'"' != "" keep `if'
    keep if yq >= `qa' & yq <= `qb'
    local names ""
    forvalues q = `qa'/`qb' {
        if `q' >= tq(2024q1) & `q' <= tq(2024q4) continue
        gen Q_`q' = (yq == `q') * `trt'
        local names "`names' Q_`q'"
    }
    if "`ols'" == "" ppmlhdfe `dep' `names', absorb(`absorb') vce(cluster `cluster')
    else reghdfe `dep' `names', absorb(`absorb') vce(cluster `cluster')
    tempname B
    matrix `B' = J(`nq', 4, .)
    local r = 1
    forvalues q = `qa'/`qb' {
        matrix `B'[`r', 1] = `q'
        if `q' >= tq(2024q1) & `q' <= tq(2024q4) {
            matrix `B'[`r', 2] = 0
            matrix `B'[`r', 3] = 0
            matrix `B'[`r', 4] = 0
        }
        else {
            cap matrix `B'[`r', 2] = _b[Q_`q']
            cap matrix `B'[`r', 3] = _b[Q_`q'] - 1.96 * _se[Q_`q']
            cap matrix `B'[`r', 4] = _b[Q_`q'] + 1.96 * _se[Q_`q']
        }
        local ++r
    }
    clear
    qui set obs `nq'
    svmat `B', names(col)
    rename (c1 c2 c3 c4) (yq b lo hi)
    format yq %tq
    export delimited using "$T/`file'.csv", replace
    twoway (rcap lo hi yq, lcolor(gs8)) (connected b yq, lcolor(black) mcolor(black) msymbol(O) msize(small)), ///
        yline(0, lpattern(dash) lcolor(gs8)) xline(`=tq(2025q3) - 0.5', lpattern(dot) lcolor(gs8)) ///
        xtitle("") ytitle("`ytitle'") xlabel(`qa'(1)`qb', angle(45) format(%tq)) legend(off)
    graph export "$F/`file'.png", replace width(2400)
    restore
end

* Figure 2: counts, C-corps, broad control
use "$D/panel_corp_quarterly.dta", clear
qes n elig, absorb(cell yq) cluster(cell) file(fig2_es_counts_corps) ///
    ytitle("Coefficient (PPML), 95% CI")

* Figure A1 (top): counts, triple difference
use "$D/panel_main_quarterly.dta", clear
gen elig_corp = elig * corp
qes n elig_corp, absorb(cell elig#yq corp#yq) cluster(st_el) file(figA1a_es_counts_ddd) ///
    ytitle("Triple-difference coefficient (PPML), 95% CI")

* Figure 4: amounts, C-corps, broad control (offering level), to 2026Q3 (partial quarter) as in the paper
use "$D/analysis_sample.dta", clear
keep if corp == 1 & ln_sold_orig < .
qes ln_sold_orig elig, absorb(st_gr ym) cluster(st_gr) file(fig4_es_amounts_corps) ///
    ytitle("Coefficient (OLS, log amount), 95% CI") ols last(2026q3)

* Figure A1 (bottom): amounts, triple difference, to 2026Q3 (partial quarter) as in the paper
use "$D/analysis_sample.dta", clear
keep if ambig == 0 & ln_sold_orig < .
gen elig_corp = elig * corp
qes ln_sold_orig elig_corp, absorb(st_gr_corp elig#ym corp#ym) cluster(st_gr) file(figA1b_es_amounts_ddd) ///
    ytitle("Triple-difference coefficient (OLS, log amount), 95% CI") ols last(2026q3)

*------------------------------------------------------------------------------*
* 7. Figure 3: synthetic control for eligible C-corporation counts
*    Donors: industry group x entity type series with at least 5 notices in every
*    quarter (25 series). Weights are non-negative, sum to one and minimise the
*    pre-reform (2019Q1-2025Q2) mean squared error of the DEMEANED log series, so that
*    the synthetic control matches the treated series up to a constant (demeaned
*    synthetic control; Ferman and Pinto 2021). This is a strictly convex quadratic
*    programme; it is solved to machine precision in Mata (accelerated projected
*    gradient with restarts), so the result does not depend on optimiser settings.
*    In-space placebos: each donor in turn is treated, the other 24 donors form its pool.
*    Output: figures/fig3_synthetic_control.png; tables/fig3_synth_path.csv,
*    fig3_synth_weights.csv and fig3_synth_placebos.csv.
*------------------------------------------------------------------------------*
di as result _n "===== SECTION 7. Figure 3: synthetic control ====="
cap mata mata drop sc_proj() sc_weights() sc_csv() sc_run()
mata
real colvector sc_proj(real colvector v)
{
    // Euclidean projection of v onto the unit simplex {w >= 0, sum(w) = 1}
    real colvector u, css
    real scalar k, j, rho, th
    k   = rows(v)
    u   = sort(v, -1)
    css = runningsum(u)
    rho = 1
    for (j = 1; j <= k; j++) {
        if (u[j] * j > css[j] - 1) rho = j
    }
    th = (css[rho] - 1) / rho
    return((v :- th) :* ((v :- th) :> 0))
}

real colvector sc_weights(real colvector y, real matrix X, real scalar maxit)
{
    // min || (y - mean(y)) - (X - mean(X)) w ||^2  subject to  w >= 0, sum(w) = 1
    real colvector yd, b, w, z, wn, g
    real matrix Xd, H
    real scalar L, t, tn, it, k
    yd = y :- mean(y)
    Xd = X :- mean(X)
    H  = cross(Xd, Xd)
    b  = cross(Xd, yd)
    L  = max(symeigenvalues(H))
    k  = cols(X)
    w  = J(k, 1, 1 / k)
    z  = w
    t  = 1
    for (it = 1; it <= maxit; it++) {
        g  = H * z - b
        wn = sc_proj(z - g / L)
        if (cross(g, wn - w) > 0) {
            t = 1
            z = wn
        }
        else {
            tn = (1 + sqrt(1 + 4 * t * t)) / 2
            z  = wn + ((t - 1) / tn) * (wn - w)
            t  = tn
        }
        if (it > 100 & max(abs(wn - w)) < 1e-12) {
            return(wn)
        }
        w = wn
    }
    printf("{err}sc_weights: no convergence after %g iterations\n", maxit)
    return(w)
}

void sc_csv(string scalar fn, string scalar head, string colvector lab, real matrix X)
{
    real scalar fh, i, j
    string scalar line
    if (fileexists(fn)) {
        if (_unlink(fn) != 0) {
            printf("{err}could not replace %s (is it open in Excel?)\n", fn)
            return
        }
    }
    fh = _fopen(fn, "w")
    if (fh < 0) {
        printf("{err}could not write %s\n", fn)
        return
    }
    fput(fh, head)
    for (i = 1; i <= rows(X); i++) {
        line = char(34) + lab[i] + char(34)
        for (j = 1; j <= cols(X); j++) {
            line = line + "," + strtrim(strofreal(X[i, j], "%18.10g"))
        }
        fput(fh, line)
    }
    fclose(fh)
}

void sc_run(real scalar tr, real scalar T, real scalar q1, real scalar maxit, string scalar tdir)
{
    real colvector Yl, Nl, yq, ip, io, w, gap, g, srt, wj, good, syn
    real matrix Y, Nm, G, P
    real rowvector D, Dj
    string colvector nm, names
    real scalar U, nd, j, k, a, aj, pre_tr, post_tr, ratio_tr, nge, p, i
    Yl = st_data(., "ln_n")
    Nl = st_data(., "n")
    U  = rows(Yl) / T
    Y  = colshape(Yl, T)'
    Nm = colshape(Nl, T)'
    yq = st_data((1::T), "yq")
    nm = st_sdata(., "unitname")
    names = nm[(0::(U - 1)) :* T :+ 1]
    ip = selectindex(yq :< q1)
    io = selectindex(yq :>= q1)
    D  = select(1..U, (1..U) :!= tr)
    nd = cols(D)
    // treated series
    w   = sc_weights(Y[ip, tr], Y[ip, D], maxit)
    a   = mean(Y[ip, tr]) - mean(Y[ip, D]) * w
    syn = a :+ Y[., D] * w
    gap = Y[., tr] - syn
    pre_tr   = sqrt(mean(gap[ip] :^ 2))
    post_tr  = sqrt(mean(gap[io] :^ 2))
    ratio_tr = post_tr / pre_tr
    // in-space placebos: each donor is treated, the other donors form its pool
    G = J(T, nd, .)
    P = J(nd, 4, .)
    for (j = 1; j <= nd; j++) {
        k  = D[j]
        Dj = select(D, D :!= k)
        wj = sc_weights(Y[ip, k], Y[ip, Dj], maxit)
        aj = mean(Y[ip, k]) - mean(Y[ip, Dj]) * wj
        g  = Y[., k] - (aj :+ Y[., Dj] * wj)
        G[., j] = g
        P[j, 1] = sqrt(mean(g[ip] :^ 2))
        P[j, 2] = sqrt(mean(g[io] :^ 2))
        P[j, 3] = P[j, 2] / P[j, 1]
        P[j, 4] = mean(g[io])
    }
    nge  = sum(P[., 3] :>= ratio_tr)
    p    = (nge + 1) / (nd + 1)
    good = (P[., 1] :<= 5 * pre_tr)
    printf("\n{txt}Demeaned synthetic control: %g donors, %g pre-reform and %g post-reform quarters\n", nd, rows(ip), rows(io))
    printf("{res}  pre-reform RMSPE %6.4f\n", pre_tr)
    for (i = 1; i <= rows(io); i++) {
        printf("  gap %s: %7.4f\n", strofreal(yq[io[i]], "%tq"), gap[io[i]])
    }
    printf("  mean post-reform gap %7.4f; post/pre RMSPE ratio %5.3f\n", mean(gap[io]), ratio_tr)
    printf("  donors with a ratio at least as large: %g of %g; in-space placebo p = %5.3f\n", nge, nd, p)
    printf("  donors' mean post-reform gaps: %6.3f to %6.3f\n", min(P[., 4]), max(P[., 4]))
    printf("  donors with pre-RMSPE <= 5 x treated (drawn in Figure 3): %g\n", sum(good))
    printf("{txt}  weights:\n")
    srt = order(-w, 1)
    for (i = 1; i <= nd; i++) {
        if (w[srt[i]] >= 0.0005) printf("    %6.3f  %s\n", w[srt[i]], names[D[srt[i]]])
    }
    st_numscalar("sc_pre", pre_tr)
    st_numscalar("sc_gap_mean", mean(gap[io]))
    st_numscalar("sc_p", p)
    st_numscalar("sc_gmin", min(P[., 4]))
    st_numscalar("sc_gmax", max(P[., 4]))
    st_numscalar("sc_ngood", sum(good))
    st_numscalar("sc_nd", nd)
    st_matrix("SC_PATH", (yq, Nm[., tr], exp(syn), gap, G))
    st_matrix("SC_GOOD", good')
    sc_csv(tdir + "/fig3_synth_weights.csv", "donor,weight", names[D'], w)
    sc_csv(tdir + "/fig3_synth_placebos.csv", "donor,pre_rmspe,post_rmspe,ratio,mean_post_gap", names[D'], P)
}
end

use "$D/analysis_sample.dta", clear
drop if inrange(event_date, td(01jul2025), td(04jul2025))
keep if yq <= tq(2026q2)
gen unitname = "TREATED eligible C-corps" if elig == 1 & corp == 1
replace unitname = industry_raw + " | " + cond(corp == 1, "C-corp", "LLC") if unitname == ""
gen one = 1
collapse (sum) n = one, by(unitname yq)
fillin unitname yq
replace n = 0 if _fillin
drop _fillin
bys unitname: egen minn = min(n)
keep if minn >= 5
gen ln_n = ln(n)
egen unit = group(unitname)
qui sum unit if unitname == "TREATED eligible C-corps"
local tr = r(min)
sort unit yq
qui count if unit == `tr'
local nq = r(N)
cap noisily mata: sc_run(`tr', `nq', `=tq(2025q3)', 100000, "$T")
if _rc == 0 {
    local nd = scalar(sc_nd)
    clear
    qui set obs `nq'
    svmat double SC_PATH
    rename (SC_PATH1 SC_PATH2 SC_PATH3 SC_PATH4) (yq actual synthetic gap_tr)
    format yq %tq
    local gl ""
    local ng = 0
    forvalues j = 1/`nd' {
        local c = `j' + 4
        rename SC_PATH`c' g`j'
        if SC_GOOD[1, `j'] == 1 {
            local gl `gl' (line g`j' yq, lcolor(gs12) lwidth(thin))
            local ++ng
        }
    }
    export delimited yq actual synthetic gap_tr using "$T/fig3_synth_path.csv", replace
    if `ng' > 0 local lg `"order(1 "Placebo donors, pre-RMSPE <= 5 x treated" `=`ng' + 1' "Eligible C-corporations")"'
    else local lg `"order(1 "Eligible C-corporations")"'
    twoway (connected actual yq, lcolor(black) mcolor(black) msymbol(O) msize(small)) ///
           (connected synthetic yq, lcolor(gs8) mcolor(gs8) lpattern(dash) msymbol(S) msize(small)), ///
        xline(`=tq(2025q3) - 0.5', lpattern(dot) lcolor(gs8)) ///
        legend(order(1 "Eligible C-corporations" 2 "Synthetic control") rows(2) ring(0) position(7) size(small)) ///
        xtitle("") ytitle("Original notices per quarter") xlabel(`=tq(2019q1)'(4)`=tq(2026q2)', angle(45)) ///
        name(sc_path, replace) nodraw
    twoway `gl' (line gap_tr yq, lcolor(black) lwidth(thick)), ///
        yline(0, lpattern(dash) lcolor(gs8)) xline(`=tq(2025q3) - 0.5', lpattern(dot) lcolor(gs8)) ///
        ylabel(-0.6(0.2)0.6) xlabel(`=tq(2019q1)'(4)`=tq(2026q2)', angle(45)) ///
        legend(`lg' rows(2) ring(0) position(11) size(small)) ///
        xtitle("") ytitle("Gap: log(actual) - log(synthetic)") name(sc_gap, replace) nodraw
    graph combine sc_path sc_gap, rows(1) xsize(12.5) ysize(5)
    graph export "$F/fig3_synthetic_control.png", replace width(2400)
}
else di as error "Synthetic control (Section 7) failed; the rest of the file still runs."

*------------------------------------------------------------------------------*
* 8. Table 4: amount raised per offering
*------------------------------------------------------------------------------*
di as result _n "===== SECTION 8. Table 4: amount raised per offering ====="
use "$D/analysis_sample.dta", clear
local A "absorb(st_gr_corp elig#ym corp#ym) vce(cluster st_gr)"
* Panel A: triple difference, main sample
eststo clear
foreach y in ln_sold big_round ln_inv ln_minin first_formd {
    eststo a_`y': reghdfe `y' ecp if ambig == 0, `A'
}
est restore a_ln_minin
scalar chk_a4_b  = _b[ecp]
scalar chk_a4_se = _se[ecp]
esttab a_* using "$T/tab4_panelA.rtf", replace se `star' b(3) label keep(ecp) ///
    stats(N r2, fmt(%9.0fc 3) labels("Observations" "R2")) ///
    mtitles("ln(amount sold)" "Offering >= USD 10m" "ln(1+investors)" "ln(1+min investment)" "First-time issuer") ///
    title("Table 4, Panel A. Triple difference, offering-level outcomes")
* CSV copy of the same table (opens in Excel):
esttab a_* using "$T/tab4_panelA.csv", replace se `star' b(3) label keep(ecp) ///
    stats(N r2, fmt(%9.0fc 3) labels("Observations" "R2")) ///
    mtitles("ln(amount sold)" "Offering >= USD 10m" "ln(1+investors)" "ln(1+min investment)" "First-time issuer") ///
    title("Table 4, Panel A. Triple difference, offering-level outcomes")
* Panel B: DiD by entity type and treated sub-industry, ln(amount at original notice)
eststo clear
eststo b1: reghdfe ln_sold_orig ep if corp == 1, absorb(st_gr ym) vce(cluster st_gr)
scalar chk_b1_b  = _b[ep]
scalar chk_b1_se = _se[ep]
eststo b2: reghdfe ln_sold_orig ep if corp == 1 & ambig == 0, absorb(st_gr ym) vce(cluster st_gr)
eststo b3: reghdfe ln_sold_orig ep if corp == 0, absorb(st_gr ym) vce(cluster st_gr)
eststo b4: reghdfe ln_sold_orig ep if corp == 1 & (inlist(industry_raw, "Other Technology", "Computers", "Telecommunications") | elig == 0), absorb(st_gr ym) vce(cluster st_gr)
eststo b5: reghdfe ln_sold_orig ep if corp == 1 & (inlist(industry_raw, "Biotechnology", "Pharmaceuticals") | elig == 0), absorb(st_gr ym) vce(cluster st_gr)
eststo b6: reghdfe ln_sold_orig ep if corp == 1 & (inlist(industry_raw, "Manufacturing", "Retailing", "Other Energy", "Energy Conservation", "Environmental Services") | elig == 0), absorb(st_gr ym) vce(cluster st_gr)
foreach m in b1 b2 b3 b4 b5 b6 {
    est restore `m'
    estadd scalar pct = 100 * (exp(_b[ep]) - 1)
    eststo `m'
}
esttab b1 b2 b3 b4 b5 b6 using "$T/tab4_panelB.rtf", replace se `star' b(3) label keep(ep) ///
    stats(pct N, fmt(1 %9.0fc) labels("Implied change, %" "Observations")) ///
    mtitles("C-corps vs all other" "C-corps vs excluded" "LLCs vs other LLCs" "technology" "biotech/pharma" "manuf/retail/energy") ///
    title("Table 4, Panel B. ln(amount sold): difference-in-differences by entity type and treated sub-industry")
* CSV copy of the same table (opens in Excel):
esttab b1 b2 b3 b4 b5 b6 using "$T/tab4_panelB.csv", replace se `star' b(3) label keep(ep) ///
    stats(pct N, fmt(1 %9.0fc) labels("Implied change, %" "Observations")) ///
    mtitles("C-corps vs all other" "C-corps vs excluded" "LLCs vs other LLCs" "technology" "biotech/pharma" "manuf/retail/energy") ///
    title("Table 4, Panel B. ln(amount sold): difference-in-differences by entity type and treated sub-industry")

*------------------------------------------------------------------------------*
* 9. Table 5: heterogeneity (H2-H4) and instrument mix
*------------------------------------------------------------------------------*
di as result _n "===== SECTION 9. Table 5: heterogeneity (H2-H4) and instrument mix ====="
use "$D/analysis_sample.dta", clear
keep if ambig == 0
local A "absorb(st_gr_corp elig#ym corp#ym) vce(cluster st_gr)"
eststo clear
eststo h1: reghdfe ln_sold  ecp if repeat == 0,   `A'
eststo h2: reghdfe ln_sold  ecp if repeat == 1,   `A'
eststo h3: reghdfe ln_sold  ecp if late_rev == 0, `A'
scalar chk_h3_b  = _b[ecp]
scalar chk_h3_se = _se[ecp]
scalar chk_h3_N  = e(N)
cap noisily eststo h4: reghdfe ln_sold  ecp if late_rev == 1, `A'
local ok_h4 = (_rc == 0)
if `ok_h4' {
    scalar chk_h4_b  = _b[ecp]
    scalar chk_h4_se = _se[ecp]
    scalar chk_h4_N  = e(N)
}
eststo h5: reghdfe ln_inv   ecp if repeat == 0,   `A'
eststo h6: reghdfe ln_minin ecp if repeat == 0,   `A'
* equality tests from pooled models in which the triple interaction and all fixed effects
* are interacted with the subsample indicator: _b[ecp_rep] equals column 2 minus column 1
* and _b[ecp_late] equals column 4 minus column 3 (same estimation samples)
gen ecp_rep  = ecp * repeat
gen ecp_late = ecp * late_rev
reghdfe ln_sold ecp ecp_rep, absorb(st_gr_corp#repeat elig#ym#repeat corp#ym#repeat) vce(cluster st_gr)
local p_rep = 2 * ttail(e(df_r), abs(_b[ecp_rep] / _se[ecp_rep]))
scalar chk_p_rep = `p_rep'
local p_late = .
cap noisily reghdfe ln_sold ecp ecp_late, absorb(st_gr_corp#late_rev elig#ym#late_rev corp#ym#late_rev) vce(cluster st_gr)
if _rc == 0 local p_late = 2 * ttail(e(df_r), abs(_b[ecp_late] / _se[ecp_late]))
scalar chk_p_late = `p_late'
est restore h1
estadd scalar p_diff = `p_rep'
eststo h1
est restore h3
estadd scalar p_diff = `p_late'
eststo h3
if `ok_h4' local hlist "h1 h2 h3 h4 h5 h6"
else local hlist "h1 h2 h3 h5 h6"
if `ok_h4' local mt `""First rounds" "Repeat rounds" "Revenue <= USD 5m or undisclosed" "Revenue > USD 5m" "First: ln(1+investors)" "First: ln(1+min inv)""'
else local mt `""First rounds" "Repeat rounds" "Revenue <= USD 5m or undisclosed" "First: ln(1+investors)" "First: ln(1+min inv)""'
esttab `hlist' using "$T/tab5_panelA.rtf", replace se `star' b(3) label keep(ecp) ///
    stats(p_diff N r2, fmt(2 %9.0fc 3) labels("p-value, equality of adjacent columns" "Observations" "R2")) ///
    mtitles(`mt') ///
    title("Table 5, Panel A. Heterogeneity by round number, issuer size and investor breadth")
* CSV copy of the same table (opens in Excel):
esttab `hlist' using "$T/tab5_panelA.csv", replace se `star' b(3) label keep(ecp) ///
    stats(p_diff N r2, fmt(2 %9.0fc 3) labels("p-value, equality of adjacent columns" "Observations" "R2")) ///
    mtitles(`mt') ///
    title("Table 5, Panel A. Heterogeneity by round number, issuer size and investor breadth")
* sensitivity (log only, not in the paper): revenue above USD 25 million
cap noisily reghdfe ln_sold ecp if rev25 == 1, `A'
if _rc == 0 di as result "Sensitivity, revenue above USD 25 million: b = " %7.3f _b[ecp] " (" %5.3f _se[ecp] "), N = " e(N)
eststo clear
eststo i1: reghdfe priced_equity ecp, `A'
eststo i2: reghdfe safe_or_note  ecp, `A'
eststo i3: reghdfe rule506c      ecp, `A'
esttab i1 i2 i3 using "$T/tab5_panelB.rtf", replace se `star' b(3) label keep(ecp) ///
    stats(N r2, fmt(%9.0fc 3) labels("Observations" "R2")) ///
    mtitles("Priced equity only" "SAFE or convertible note" "Rule 506(c)") ///
    title("Table 5, Panel B. Instrument mix")
* CSV copy of the same table (opens in Excel):
esttab i1 i2 i3 using "$T/tab5_panelB.csv", replace se `star' b(3) label keep(ecp) ///
    stats(N r2, fmt(%9.0fc 3) labels("Observations" "R2")) ///
    mtitles("Priced equity only" "SAFE or convertible note" "Rule 506(c)") ///
    title("Table 5, Panel B. Instrument mix")

*------------------------------------------------------------------------------*
* 10. Table 6: state conformity (H5)
*------------------------------------------------------------------------------*
di as result _n "===== SECTION 10. Table 6: state conformity (H5) ====="
cap confirm variable conform
if _rc == 0 {
    gen ecp_conf = ecp * conform
    gen ecp_ntx  = ecp * notax
    local C "c.ep#c.conform c.ep#c.notax c.cp#c.conform c.cp#c.notax c.post#c.conform c.post#c.notax"
    label var ecp_conf "x Conforming state"
    label var ecp_ntx  "x No-tax state"
    eststo clear
    eststo c1: reghdfe ln_sold ecp ecp_conf ecp_ntx `C', `A'
    eststo c2: reghdfe ln_sold ecp ecp_conf ecp_ntx `C' if drop_in_robustness != 1, `A'
    esttab c1 c2 using "$T/tab6_conformity.rtf", replace se `star' b(3) label keep(ecp ecp_conf ecp_ntx) ///
        stats(N, fmt(%9.0fc) labels("Observations")) mtitles("All states" "Excl. DC NJ OR WA") ///
        title("Table 6. Heterogeneity by state conformity to Section 1202")
* CSV copy of the same table (opens in Excel):
    esttab c1 c2 using "$T/tab6_conformity.csv", replace se `star' b(3) label keep(ecp ecp_conf ecp_ntx) ///
        stats(N, fmt(%9.0fc) labels("Observations")) mtitles("All states" "Excl. DC NJ OR WA") ///
        title("Table 6. Heterogeneity by state conformity to Section 1202")
}

*------------------------------------------------------------------------------*
* 11. Figure 5 and Table 7: retiming of first sales around 4 July
*------------------------------------------------------------------------------*
di as result _n "===== SECTION 11. Figure 5 and Table 7: retiming of first sales around 4 July ====="
use "$D/analysis_sample.dta", clear
keep if ambig == 0
tempfile wk
local first = 1
forvalues y = 2019/2025 {
    preserve
    local anchor = mdy(7, 4, `y')
    keep if inrange(event_date, `anchor' - 63, `anchor' + 62)
    gen rel_day = event_date - `anchor'
    gen wk = floor(rel_day / 7)
    gen yr = `y'
    gen one = 1
    * four groups (eligible C-corporations and the three control groups of the main sample):
    * 7 years x 18 weeks x 4 groups = 504 cells, as in Table 7
    collapse (sum) n = one, by(yr wk group4)
    if `first' == 1 {
        save `wk', replace
        local first = 0
    }
    else {
        append using `wk'
        save `wk', replace
    }
    restore
}
use `wk', clear
fillin yr wk group4
replace n = 0 if _fillin
drop _fillin
gen treat = group4 == 1
gen y2025 = yr == 2025
gen after = wk >= 0
gen pre3  = inrange(wk, -3, -1)
gen post3 = inrange(wk, 0, 2)
gen yta   = y2025 * treat * after
gen yt    = y2025 * treat
gen ya    = y2025 * after
gen ta    = treat * after
gen ytpre  = y2025 * treat * pre3
gen ytpost = y2025 * treat * post3
gen ypre   = y2025 * pre3
gen ypost  = y2025 * post3
gen wk_id  = wk + 10
gen ln_n   = ln(1 + n)
label var yta "2025 x Eligible C-corp x After 4 July"
label var ytpre "2025 x Eligible C-corp x weeks -3 to -1"
label var ytpost "2025 x Eligible C-corp x weeks 0 to 2"
label var ya "2025 x After 4 July"
label var ypre "2025 x weeks -3 to -1"
label var ypost "2025 x weeks 0 to 2"
save "$D/retiming_weekly.dta", replace
eststo clear
eststo r1: reg n yta yt ya ta y2025 treat i.wk_id, vce(robust)
eststo r2: poisson n yta yt ya ta y2025 treat i.wk_id, vce(robust)
eststo r3: reg n ytpre ytpost yt i.yr#i.wk_id i.group4#i.wk_id, vce(robust)
scalar chk_t7_se1 = _se[ytpre]
scalar chk_t7_se2 = _se[ytpost]
eststo r4: reg ln_n ya y2025 i.wk_id if treat == 1, vce(robust)
eststo r5: reg ln_n ypre ypost y2025 i.wk_id if treat == 1, vce(robust)
esttab r1 r2 r3 r4 r5 using "$T/tab7_retiming.rtf", replace se `star' b(3) label ///
    keep(yta ytpre ytpost ya ypre ypost) stats(N, fmt(%9.0fc) labels("Observations")) ///
    mtitles("OLS all groups" "Poisson all groups" "OLS week bins" "Eligible C-corps ln(1+n)" "Eligible C-corps week bins") ///
    title("Table 7. Retiming of first sales around 4 July 2025: weekly counts, 2019-2025")
* CSV copy of the same table (opens in Excel):
esttab r1 r2 r3 r4 r5 using "$T/tab7_retiming.csv", replace se `star' b(3) label ///
    keep(yta ytpre ytpost ya ypre ypost) stats(N, fmt(%9.0fc) labels("Observations")) ///
    mtitles("OLS all groups" "Poisson all groups" "OLS week bins" "Eligible C-corps ln(1+n)" "Eligible C-corps week bins") ///
    title("Table 7. Retiming of first sales around 4 July 2025: weekly counts, 2019-2025")
* Figure 5 (whole-number week ticks; en dash in the legend)
keep if treat == 1
collapse (mean) n, by(y2025 wk)
twoway (connected n wk if y2025 == 0, lcolor(gs8) mcolor(gs8) lpattern(dash) msymbol(Oh)) ///
       (connected n wk if y2025 == 1, lcolor(black) mcolor(black) msymbol(O)), ///
    xline(-0.5, lpattern(dot) lcolor(gs8)) xlabel(-9(1)8) legend(order(1 "2019–2024 average" 2 "2025") size(small)) ///
    xtitle("Weeks relative to 4 July (week 0 begins on 4 July)") ytitle("Original Form D notices, eligible C-corporations")
graph export "$F/fig5_retiming.png", replace width(2400)

*------------------------------------------------------------------------------*
* 12. Table 8, Panel A: placebo-in-time distributions over fictitious reform quarters
*     (13 dates 2021Q3-2024Q3; window = ten pre-reform and FOUR post-reform quarters,
*      data before July 2025 only, matching the four full post-reform quarters 2025Q3-2026Q2
*      of the actual estimate). The three-post-quarter window of the June 2026 data vintage
*      is still computed (RI3) for comparison only.
*------------------------------------------------------------------------------*
di as result _n "===== SECTION 12. Table 8, Panel A: placebo-in-time distributions ====="
matrix RI  = J(13, 4, .)
matrix RI3 = J(13, 4, .)
matrix colnames RI  = quarter b_primary b_ddd b_national
matrix colnames RI3 = quarter b_primary b_ddd b_national
* actual estimates in the same window (2023Q1-2026Q2: ten pre and four post quarters)
use "$D/panel_corp_quarterly.dta", clear
ppmlhdfe n ep if yq >= tq(2025q3) - 10 & yq <= tq(2025q3) + 3, absorb(cell yq) vce(cluster cell)
local b_prim = _b[ep]
scalar chk_prim_b  = _b[ep]
scalar chk_prim_se = _se[ep]
use "$D/panel_main_quarterly.dta", clear
ppmlhdfe n ecp if yq >= tq(2025q3) - 10 & yq <= tq(2025q3) + 3, absorb(cell elig#yq corp#yq) vce(cluster st_el)
local b_ddd = _b[ecp]
scalar chk_ddd_b  = _b[ecp]
scalar chk_ddd_se = _se[ecp]
* national series (4 groups x quarter, ln counts), same window, OLS and Newey-West (HAC) errors
* computed within each group's series (tsset g yq); the paper reports the two-lag version
collapse (sum) n, by(elig corp yq)
keep if yq >= tq(2025q3) - 10 & yq <= tq(2025q3) + 3
gen ln_n  = ln(n)
gen npost = yq >= tq(2025q3)
gen necp  = elig * corp * npost
gen nep   = elig * npost
gen ncp   = corp * npost
egen g = group(elig corp)
reg ln_n necp nep ncp i.g i.yq
local b_nat = _b[necp]
scalar chk_nat_b      = _b[necp]
scalar chk_nat_se_ols = _se[necp]
tsset g yq
cap noisily newey ln_n necp nep ncp i.g i.yq, lag(1) force
if _rc == 0 scalar chk_nat_se_nw1 = _se[necp]
cap noisily newey ln_n necp nep ncp i.g i.yq, lag(2) force
if _rc == 0 scalar chk_nat_se_nw2 = _se[necp]
* placebo reforms
local r = 1
forvalues fq = `=tq(2021q3)'/`=tq(2024q3)' {
    foreach w in 3 2 {
        if `w' == 3 local M "RI"
        else local M "RI3"
        matrix `M'[`r', 1] = `fq'
        use "$D/panel_corp_quarterly.dta", clear
        keep if yq >= `fq' - 10 & yq <= `fq' + `w'
        gen fpost = yq >= `fq'
        gen fep = elig * fpost
        cap ppmlhdfe n fep, absorb(cell yq) vce(cluster cell)
        if _rc == 0 matrix `M'[`r', 2] = _b[fep]
        use "$D/panel_main_quarterly.dta", clear
        keep if yq >= `fq' - 10 & yq <= `fq' + `w'
        gen fpost = yq >= `fq'
        gen fecp = elig * corp * fpost
        cap ppmlhdfe n fecp, absorb(cell elig#yq corp#yq) vce(cluster st_el)
        if _rc == 0 matrix `M'[`r', 3] = _b[fecp]
        * national series (4 groups x quarter), log counts
        collapse (sum) n, by(elig corp yq)
        gen ln_n = ln(n)
        gen fpost = yq >= `fq'
        gen fecp = elig * corp * fpost
        gen fep = elig * fpost
        gen fcp = corp * fpost
        egen g = group(elig corp)
        cap reg ln_n fecp fep fcp i.g i.yq
        if _rc == 0 matrix `M'[`r', 4] = _b[fecp]
    }
    local ++r
}
foreach M in RI RI3 {
    preserve
    clear
    qui set obs 13
    svmat `M', names(col)
    format quarter %tq
    if "`M'" == "RI" export delimited using "$T/tab8_panelA_ri_placebos.csv", replace
    else export delimited using "$T/tab8_panelA_ri_placebos_3post.csv", replace
    if "`M'" == "RI" di as result _n "Placebo-in-time distributions, four post-reform quarters (as in the paper):"
    else di as result _n "For comparison only - three post-reform quarters (June 2026 data vintage):"
    foreach v in b_primary b_ddd b_national {
        if "`v'" == "b_primary"  local act = `b_prim'
        if "`v'" == "b_ddd"      local act = `b_ddd'
        if "`v'" == "b_national" local act = `b_nat'
        qui count if abs(`v') >= abs(`act') & `v' < .
        local nge = r(N)
        qui count if `v' < .
        local p = `nge' / r(N)
        qui sum `v'
        di as result "  `v': actual " %7.3f `act' "; placebos mean " %6.3f r(mean) ", sd " %6.3f r(sd) ///
            ", range " %6.3f r(min) " to " %6.3f r(max) "; share |placebo| >= |actual| " %4.2f `p'
    }
    if "`M'" == "RI" {
        di as result "  paper, Table 8: primary +0.073; 0.047; +0.003 to +0.161; 0.46 | triple difference +0.250; 0.258;"
        di as result "                 -0.188 to +0.637; 0.38 | national series +0.244; 0.257; -0.206 to +0.631; 0.38"
        * Figure A3: placebo distributions (frequencies, whole-number ticks)
        foreach v in b_primary b_ddd {
            qui sum `v'
            local lo = r(min)
            local wd = (r(max) - r(min)) / 8
            gen _bin = min(floor((`v' - `lo') / `wd'), 7) if `v' < .
            bys _bin: gen _cnt = _N if _bin < .
            qui sum _cnt
            local ymax_`v' = r(max)
            if "`ymax_`v''" == "." local ymax_`v' = 1
            drop _bin _cnt
        }
        twoway (histogram b_primary, frequency bin(8) fcolor(gs12) lcolor(gs6)), xline(`b_prim', lcolor(black) lwidth(thick)) ///
            xline(0, lpattern(dash) lcolor(gs8)) ylabel(0(1)`ymax_b_primary') ///
            xtitle("Placebo-reform coefficient, primary design") ytitle("Number of placebo reforms") name(hA, replace)
        twoway (histogram b_ddd, frequency bin(8) fcolor(gs12) lcolor(gs6)), xline(`b_ddd', lcolor(black) lwidth(thick)) ///
            xline(0, lpattern(dash) lcolor(gs8)) ylabel(0(1)`ymax_b_ddd') ///
            xtitle("Placebo-reform coefficient, quarterly triple difference") ytitle("Number of placebo reforms") name(hB, replace)
        graph combine hA hB, rows(1)
        graph export "$F/figA3_placebo_distribution.png", replace width(2400)
    }
    restore
}

*------------------------------------------------------------------------------*
* 13. Table 8, Panel B: individual placebo reforms and robustness
*------------------------------------------------------------------------------*
di as result _n "===== SECTION 13. Table 8, Panel B: individual placebo reforms and robustness ====="
cap program drop addrow
program define addrow
    args mat row var
    matrix `mat'[`row', 1] = _b[`var']
    matrix `mat'[`row', 2] = _se[`var']
    matrix `mat'[`row', 3] = 2 * normal(-abs(_b[`var'] / _se[`var']))
    matrix `mat'[`row', 4] = e(N)
end
matrix R = J(17, 4, .)
matrix colnames R = b se p N
* placebo reforms, primary quarterly design (two years before and after)
use "$D/panel_corp_quarterly.dta", clear
local row = 1
foreach fq in 2023q3 2024q3 {
    preserve
    keep if yq >= tq(`fq') - 8 & yq < tq(2025q3) & yq <= tq(`fq') + 7
    gen fpost = yq >= tq(`fq')
    gen fep = elig * fpost
    ppmlhdfe n fep, absorb(cell yq) vce(cluster cell)
    addrow R `row' fep
    restore
    local ++row
}
* placebo reforms, monthly triple difference (two years before and after)
use "$D/panel_main_monthly.dta", clear
foreach fm in 2023m7 2024m7 {
    preserve
    keep if ym >= tm(`fm') - 24 & ym < tm(2025m7) & ym <= tm(`fm') + 23
    gen fpost = ym >= tm(`fm')
    gen fecp = elig * corp * fpost
    ppmlhdfe n fecp, absorb(cell elig#ym corp#ym) vce(cluster st_el)
    addrow R `row' fecp
    restore
    local ++row
}
* placebo reforms, amounts, C-corps vs all other C-corps
use "$D/analysis_sample.dta", clear
foreach fq in 2023q3 2024q3 {
    preserve
    keep if corp == 1 & ln_sold_orig < . & yq >= tq(`fq') - 8 & yq <= tq(`fq') + 3 & yq < tq(2025q3)
    gen fpost = yq >= tq(`fq')
    gen fep = elig * fpost
    reghdfe ln_sold_orig fep, absorb(st_gr ym) vce(cluster st_gr)
    addrow R `row' fep
    restore
    local ++row
}
* robustness variants of the triple difference for ln(amount sold)
use "$D/analysis_sample.dta", clear
local A "absorb(st_gr_corp elig#ym corp#ym) vce(cluster st_gr)"
reghdfe ln_sold ecp if ambig == 0, `A'
addrow R 7 ecp
reghdfe ln_sold ecp, `A'
addrow R 8 ecp
reghdfe ln_sold ecp if ambig == 0 & ai_name_flag == 0, `A'
addrow R 9 ecp
reghdfe ln_sold ecp if ambig == 0 & state != "CA", `A'
addrow R 10 ecp
reghdfe ln_sold ecp if ambig == 0 & (inlist(industry_raw, "Biotechnology", "Pharmaceuticals", "Manufacturing") | elig == 0), `A'
addrow R 11 ecp
* offerings dated by filing date: Post and the month effects use the filing month
gen post_f = filing_date > reform
gen ecp_f  = elig * corp * post_f
gen ym_f   = mofd(filing_date)
reghdfe ln_sold ecp_f if ambig == 0, absorb(st_gr_corp elig#ym_f corp#ym_f) vce(cluster st_gr)
addrow R 12 ecp_f
scalar chk_fd_b  = _b[ecp_f]
scalar chk_fd_se = _se[ecp_f]
reghdfe ln_sold ecp if ambig == 0 & priced_equity == 1, `A'
addrow R 13 ecp
reghdfe ln_sold_orig ecp if ambig == 0, `A'
addrow R 14 ecp
cap confirm variable drop_in_robustness
if _rc == 0 {
    reghdfe ln_sold ecp if ambig == 0 & drop_in_robustness != 1, `A'
    addrow R 15 ecp
}
reghdfe ln_sold ecp if ambig == 0 & ym != tm(2025m6), `A'
addrow R 16 ecp
reghdfe ln_sold ecp if ambig == 0 & sale_date_missing == 0, `A'
addrow R 17 ecp
matrix rownames R = placebo_2023q3_primary placebo_2024q3_primary placebo_2023m7_ddd placebo_2024m7_ddd ///
    placebo_2023q3_amounts placebo_2024q3_amounts baseline_ddd_amounts plus_ambiguous no_AI_names ///
    no_California bio_pharma_manuf filing_date priced_equity_only original_notice_amount ///
    excl_DC_NJ_OR_WA excl_June2025 first_sale_date_reported
esttab matrix(R, fmt(3 3 3 %9.0fc)) using "$T/tab8_panelB_robustness.rtf", replace ///
    title("Table 8, Panel B. Individual placebo reforms and robustness checks")
* CSV copy of the same table (opens in Excel):
esttab matrix(R, fmt(4 4 4 0)) using "$T/tab8_panelB_robustness.csv", replace
matrix list R, format(%9.3f)

*------------------------------------------------------------------------------*
* 14. Appendix: Table A5 (pre-trend), Table A6 (variance estimator), Figure A2 (LLC check)
*------------------------------------------------------------------------------*
di as result _n "===== SECTION 14. Appendix: Table A5 (pre-trend), Table A6 (variance estimator), Figure A2 (LLC check) ====="
use "$D/panel_main_monthly.dta", clear
keep if ym < tm(2025m7)
gen trend = ym - tm(2019m1)
gen ec_trend = elig * corp * trend
label var ec_trend "Eligible x Corp x linear month trend"
eststo clear
eststo pt1: ppmlhdfe n ec_trend, absorb(cell elig#ym corp#ym) vce(cluster st_el)
eststo pt2: reghdfe ln_n ec_trend, absorb(cell elig#ym corp#ym) vce(cluster st_el)
esttab pt1 pt2 using "$T/tabA5_pretrend.rtf", replace se `star' b(4) label keep(ec_trend) ///
    stats(N, fmt(%9.0fc) labels("Observations (cells)")) mtitles("PPML" "OLS ln(1+n)") ///
    title("Table A5. Differential pre-trend test, January 2019 to June 2025")
* CSV copy of the same table (opens in Excel):
esttab pt1 pt2 using "$T/tabA5_pretrend.csv", replace se `star' b(4) label keep(ec_trend) ///
    stats(N, fmt(%9.0fc) labels("Observations (cells)")) mtitles("PPML" "OLS ln(1+n)") ///
    title("Table A5. Differential pre-trend test, January 2019 to June 2025")

use "$D/panel_main_monthly.dta", clear
egen st = group(state)
matrix V = J(4, 3, .)
matrix colnames V = b se p
local i = 1
foreach vc in "robust" "cluster st_el" "cluster st" "cluster cell" {
    ppmlhdfe n ecp, absorb(cell elig#ym corp#ym) vce(`vc')
    matrix V[`i', 1] = _b[ecp]
    matrix V[`i', 2] = _se[ecp]
    matrix V[`i', 3] = 2 * normal(-abs(_b[ecp] / _se[ecp]))
    local ++i
}
matrix rownames V = robust_HC cluster_state_x_group cluster_state cluster_cell
esttab matrix(V, fmt(4 3 2)) using "$T/tabA6_variance.rtf", replace ///
    title("Table A6. Sensitivity of the monthly triple-difference count estimate to the variance estimator")
* CSV copy of the same table (opens in Excel):
esttab matrix(V, fmt(4 3 2)) using "$T/tabA6_variance.csv", replace ///
    title("Table A6. Sensitivity of the monthly triple-difference count estimate to the variance estimator")

* Figure A2: monthly event study, LLCs only, eligible vs excluded, reference 2024
use "$D/panel_main_monthly.dta", clear
keep if corp == 0 & ym >= tm(2023m1)
local names ""
forvalues m = `=tm(2023m1)'/`=tm(2026m8)' {
    if `m' >= tm(2024m1) & `m' <= tm(2024m12) continue
    gen M_`m' = (ym == `m') * elig
    local names "`names' M_`m'"
}
ppmlhdfe n `names', absorb(cell ym) vce(cluster st_el)
tempname B
local nm = tm(2026m8) - tm(2023m1) + 1
matrix `B' = J(`nm', 4, .)
local r = 1
forvalues m = `=tm(2023m1)'/`=tm(2026m8)' {
    matrix `B'[`r', 1] = `m'
    if `m' >= tm(2024m1) & `m' <= tm(2024m12) {
        matrix `B'[`r', 2] = 0
        matrix `B'[`r', 3] = 0
        matrix `B'[`r', 4] = 0
    }
    else {
        cap matrix `B'[`r', 2] = _b[M_`m']
        cap matrix `B'[`r', 3] = _b[M_`m'] - 1.96 * _se[M_`m']
        cap matrix `B'[`r', 4] = _b[M_`m'] + 1.96 * _se[M_`m']
    }
    local ++r
}
clear
qui set obs `nm'
svmat `B', names(col)
rename (c1 c2 c3 c4) (ym b lo hi)
format ym %tm
export delimited using "$T/figA2_llc_check.csv", replace
twoway (rcap lo hi ym, lcolor(gs8)) (connected b ym, lcolor(black) mcolor(black) msymbol(O) msize(small)), ///
    yline(0, lpattern(dash) lcolor(gs8)) xline(`=tm(2025m7) - 0.5', lpattern(dot) lcolor(gs8)) ///
    xtitle("") ytitle("Eligible vs excluded industries," "LLCs only (PPML), 95% CI") legend(off)
graph export "$F/figA2_llc_check.png", replace width(2400)

*------------------------------------------------------------------------------*
* 15. Checks against the manuscript (send this part of the log to the authors)
*------------------------------------------------------------------------------*
di as result _n "===== SECTION 15. CHECKS AGAINST THE MANUSCRIPT ====="
di as result "Revenue above USD 5m (main sample / with ln amount): " scalar(chk_late_n) " / " scalar(chk_late_nreg) "   expected: 1023 / 785"
di as result "Table 5, col. 3 (revenue <= USD 5m):  b = " %7.3f scalar(chk_h3_b) " (" %5.3f scalar(chk_h3_se) "), N = " %6.0f scalar(chk_h3_N) "    paper: 0.025 (0.200), N = 44,354"
di as result "Table 5, col. 4 (revenue > USD 5m):   b = " %7.3f scalar(chk_h4_b) " (" %5.3f scalar(chk_h4_se) "), N = " %6.0f scalar(chk_h4_N) "    paper: -0.406 (2.092), N = 670"
di as result "Table 5, equality p-values:           rounds " %4.2f scalar(chk_p_rep) ", revenue " %4.2f scalar(chk_p_late) "            paper: 0.29, 0.81"
di as result "Table 4, Panel A, col. 4 (min. inv.):  b = " %7.3f scalar(chk_a4_b) " (" %5.3f scalar(chk_a4_se) ")              paper: -0.893 (0.482)"
di as result "Table 4, Panel B, col. 1:              b = " %7.3f scalar(chk_b1_b) " (" %5.3f scalar(chk_b1_se) ")              paper: -0.377 (0.089)"
di as result "Table 7, col. 3 robust SEs:            " %6.3f scalar(chk_t7_se1) ", " %6.3f scalar(chk_t7_se2) "                    paper: 7.601, 7.756"
di as result "Table 8, Panel A, primary design:      b = " %7.3f scalar(chk_prim_b) " (" %5.3f scalar(chk_prim_se) ")              paper: 0.060 (0.068)"
di as result "Table 8, Panel A, quarterly DDD:       b = " %7.3f scalar(chk_ddd_b) " (" %5.3f scalar(chk_ddd_se) ")              paper: -0.346 (0.124)"
di as result "Table 8, Panel A, national series:     b = " %7.3f scalar(chk_nat_b) "  OLS SE " %5.3f scalar(chk_nat_se_ols) ///
    ", Newey-West lag 1 " %5.3f scalar(chk_nat_se_nw1) ", lag 2 " %5.3f scalar(chk_nat_se_nw2) "    paper: -0.322 (0.127, lag 2)"
di as result "Table 8, Panel B, filing date:         b = " %7.3f scalar(chk_fd_b) " (" %5.3f scalar(chk_fd_se) ")              paper: -0.078 (0.184)"
di as result "Synthetic control: pre-RMSPE " %6.4f scalar(sc_pre) ", mean post gap " %7.4f scalar(sc_gap_mean) ", p = " %4.2f scalar(sc_p) ///
    ", donor gaps " %6.3f scalar(sc_gmin) " to " %6.3f scalar(sc_gmax) ", donors drawn " scalar(sc_ngood)
di as result "                   paper: 2.8 log points, +0.018 (gaps +0.021, -0.007, -0.002, +0.061), p = 0.73, -0.380 to +0.433, 8 donors"

di as result _n "Done. Tables in $T, figures in $F. Log: qsbs2025_replication.smcl"
log close
