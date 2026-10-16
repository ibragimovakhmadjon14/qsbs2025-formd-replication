*==============================================================================*
* qsbs2025_text_numbers.do
* Prints, with five decimals, every coefficient, standard error and p-value that the
* manuscript quotes in its tables and text, so that the paper can be matched to Stata
* exactly. Run it AFTER qsbs2025_replication.do, from the same package folder: it only
* reads the datasets that file saves in data/clean. It takes one to three minutes.
*   cd "C:\Users\user\Desktop\qsbs2025_stata_package (1)"
*   do qsbs2025_text_numbers.do
* Send back the file qsbs2025_text_numbers.smcl (or copy the log from the Results window).
*==============================================================================*
version 14
clear all
set more off
capture log close
log using "qsbs2025_text_numbers.smcl", replace
* The datasets saved by the NEW qsbs2025_replication.do must all be in one folder.
local need "analysis_sample panel_corp_quarterly panel_main_monthly panel_main_quarterly retiming_weekly"
local found ""
foreach cand in "data/clean" "qsbs2025_stata_package/data/clean" "." {
    if "`found'" == "" {
        local ok = 1
        foreach f of local need {
            cap confirm file "`cand'/`f'.dta"
            if _rc != 0 local ok = 0
        }
        if `ok' == 1 local found "`cand'"
    }
}
di as text "current folder: " c(pwd)
if "`found'" == "" {
    di as error "The datasets of qsbs2025_replication.do are not all in data/clean of this folder."
    di as error `"Type   cd "C:\Users\user\Desktop\qsbs2025_stata_package (1)"   (the folder where you ran qsbs2025_replication.do)"'
    di as error "and run this file again."
    exit 601
}
global D "`found'"
di as text "data folder: $D"
* the datasets must come from the new version of qsbs2025_replication.do (revenue cut-off USD 5 million)
use "$D/analysis_sample.dta", clear
cap confirm variable rev25
local new = (_rc == 0)
qui count if late_rev == 1 & ambig == 0
if `new' == 0 | r(N) != 954 {
    di as error "data/clean/analysis_sample.dta comes from an older run (" r(N) " offerings with revenue above USD 5 million, expected 954)."
    di as error "Run the new qsbs2025_replication.do in this folder first, then this file."
    exit 459
}
di as text "analysis_sample.dta is from the new run: 954 offerings with revenue above USD 5 million"

* show "label" coefficient t|z : b, se and the p-value the command itself reports
cap program drop show
program define show
    args lab v dist
    local b  = _b[`v']
    local se = _se[`v']
    if "`dist'" == "t" local p = 2 * ttail(e(df_r), abs(`b' / `se'))
    else local p = 2 * normal(-abs(`b' / `se'))
    di as result %-44s "`lab'" " b = " %10.5f `b' "   se = " %9.5f `se' "   p = " %7.4f `p' "   N = " %7.0f e(N)
end

*------------------------------------------------------------------------------*
di as result _n "== Table 3 (and Table A6 baseline) =="
use "$D/panel_corp_quarterly.dta", clear
qui ppmlhdfe n ep if yq >= tq(2023q1), absorb(cell yq) vce(cluster cell)
show "T3 c1 primary, 2023Q1-2026Q1 (= T8A row 1)" ep z
qui ppmlhdfe n ep, absorb(cell yq) vce(cluster cell)
show "T3 c2 broad, 2019Q1-2026Q1" ep z
use "$D/panel_main_monthly.dta", clear
qui ppmlhdfe n ep if corp == 1, absorb(cell ym) vce(cluster st_el)
show "T3 c3 C-corps narrow monthly" ep z
qui ppmlhdfe n ep if corp == 0, absorb(cell ym) vce(cluster st_el)
show "T3 c4 LLCs narrow monthly" ep z
qui ppmlhdfe n ecp, absorb(cell elig#ym corp#ym) vce(cluster st_el)
show "T3 c5 DDD monthly (= A6 baseline)" ecp z
qui ppmlhdfe n_first ecp, absorb(cell elig#ym corp#ym) vce(cluster st_el)
show "T3 c6 DDD first-time issuers" ecp z

di as result _n "== Table A6 =="
egen st = group(state)
qui ppmlhdfe n ecp, absorb(cell elig#ym corp#ym) vce(robust)
show "A6 robust" ecp z
qui ppmlhdfe n ecp, absorb(cell elig#ym corp#ym) vce(cluster st)
show "A6 cluster state" ecp z
qui ppmlhdfe n ecp, absorb(cell elig#ym corp#ym) vce(cluster cell)
show "A6 cluster cell" ecp z

di as result _n "== Table A5 =="
use "$D/panel_main_monthly.dta", clear
keep if ym < tm(2025m7)
gen trend = ym - tm(2019m1)
gen ec_trend = elig * corp * trend
qui ppmlhdfe n ec_trend, absorb(cell elig#ym corp#ym) vce(cluster st_el)
show "A5 PPML" ec_trend z
qui reghdfe ln_n ec_trend, absorb(cell elig#ym corp#ym) vce(cluster st_el)
show "A5 OLS ln(1+n)" ec_trend t

di as result _n "== Table 8, Panel A (actual estimates) =="
use "$D/panel_main_quarterly.dta", clear
qui ppmlhdfe n ecp if yq >= tq(2025q3) - 10 & yq <= tq(2025q3) + 2, absorb(cell elig#yq corp#yq) vce(cluster st_el)
show "T8A quarterly DDD" ecp z

di as result _n "== Table 4 =="
use "$D/analysis_sample.dta", clear
local A "absorb(st_gr_corp elig#ym corp#ym) vce(cluster st_gr)"
foreach y in ln_sold big_round ln_inv ln_minin first_formd {
    qui reghdfe `y' ecp if ambig == 0, `A'
    show "T4A `y'" ecp t
}
qui reghdfe ln_sold_orig ep if corp == 1, absorb(st_gr ym) vce(cluster st_gr)
show "T4B c1 C-corps vs all other C-corps" ep t
qui reghdfe ln_sold_orig ep if corp == 1 & ambig == 0, absorb(st_gr ym) vce(cluster st_gr)
show "T4B c2 C-corps vs excluded C-corps" ep t
qui reghdfe ln_sold_orig ep if corp == 0, absorb(st_gr ym) vce(cluster st_gr)
show "T4B c3 LLCs vs other LLCs" ep t
qui reghdfe ln_sold_orig ep if corp == 1 & (inlist(industry_raw, "Other Technology", "Computers", "Telecommunications") | elig == 0), absorb(st_gr ym) vce(cluster st_gr)
show "T4B c4 technology" ep t
qui reghdfe ln_sold_orig ep if corp == 1 & (inlist(industry_raw, "Biotechnology", "Pharmaceuticals") | elig == 0), absorb(st_gr ym) vce(cluster st_gr)
show "T4B c5 biotech/pharma" ep t
qui reghdfe ln_sold_orig ep if corp == 1 & (inlist(industry_raw, "Manufacturing", "Retailing", "Other Energy", "Energy Conservation", "Environmental Services") | elig == 0), absorb(st_gr ym) vce(cluster st_gr)
show "T4B c6 manuf/retail/energy" ep t
* LLC estimate quoted in Section 4.3 (window starting two years before the reform)
qui reghdfe ln_sold_orig ep if corp == 0 & ym >= tm(2023m7), absorb(st_gr ym) vce(cluster st_gr)
show "Text 4.3 LLCs, from July 2023" ep t
qui reghdfe ln_sold_orig ep if corp == 0 & ym >= tm(2023m6), absorb(st_gr ym) vce(cluster st_gr)
show "Text 4.3 LLCs, from June 2023 (variant)" ep t

di as result _n "== Table 5 =="
preserve
keep if ambig == 0
qui reghdfe ln_sold ecp if repeat == 0, `A'
show "T5A c1 first rounds" ecp t
qui reghdfe ln_sold ecp if repeat == 1, `A'
show "T5A c2 repeat rounds" ecp t
qui reghdfe ln_sold ecp if late_rev == 0, `A'
show "T5A c3 revenue <= USD 5m" ecp t
qui reghdfe ln_sold ecp if late_rev == 1, `A'
show "T5A c4 revenue > USD 5m" ecp t
qui reghdfe ln_inv ecp if repeat == 0, `A'
show "T5A c5 first rounds ln(1+investors)" ecp t
qui reghdfe ln_minin ecp if repeat == 0, `A'
show "T5A c6 first rounds ln(1+min inv)" ecp t
qui reghdfe priced_equity ecp, `A'
show "T5B c1 priced equity" ecp t
qui reghdfe safe_or_note ecp, `A'
show "T5B c2 SAFE or note" ecp t
qui reghdfe rule506c ecp, `A'
show "T5B c3 Rule 506(c)" ecp t

di as result _n "== Table 6 =="
gen ecp_conf = ecp * conform
gen ecp_ntx  = ecp * notax
local C "c.ep#c.conform c.ep#c.notax c.cp#c.conform c.cp#c.notax c.post#c.conform c.post#c.notax"
qui reghdfe ln_sold ecp ecp_conf ecp_ntx `C', `A'
show "T6 c1 baseline" ecp t
show "T6 c1 x conforming" ecp_conf t
show "T6 c1 x no-tax" ecp_ntx t
qui reghdfe ln_sold ecp ecp_conf ecp_ntx `C' if drop_in_robustness != 1, `A'
show "T6 c2 baseline" ecp t
show "T6 c2 x conforming" ecp_conf t
show "T6 c2 x no-tax" ecp_ntx t
restore

di as result _n "== Table 8, Panel B =="
use "$D/panel_corp_quarterly.dta", clear
foreach fq in 2023q3 2024q3 {
    preserve
    keep if yq >= tq(`fq') - 8 & yq < tq(2025q3) & yq <= tq(`fq') + 7
    gen fpost = yq >= tq(`fq')
    gen fep = elig * fpost
    qui ppmlhdfe n fep, absorb(cell yq) vce(cluster cell)
    show "T8B placebo `fq' primary" fep z
    restore
}
use "$D/panel_main_monthly.dta", clear
foreach fm in 2023m7 2024m7 {
    preserve
    keep if ym >= tm(`fm') - 24 & ym < tm(2025m7) & ym <= tm(`fm') + 23
    gen fpost = ym >= tm(`fm')
    gen fecp = elig * corp * fpost
    qui ppmlhdfe n fecp, absorb(cell elig#ym corp#ym) vce(cluster st_el)
    show "T8B placebo `fm' monthly DDD" fecp z
    restore
}
use "$D/analysis_sample.dta", clear
foreach fq in 2023q3 2024q3 {
    preserve
    keep if corp == 1 & ln_sold_orig < . & yq >= tq(`fq') - 8 & yq <= tq(`fq') + 3 & yq < tq(2025q3)
    gen fpost = yq >= tq(`fq')
    gen fep = elig * fpost
    qui reghdfe ln_sold_orig fep, absorb(st_gr ym) vce(cluster st_gr)
    show "T8B placebo `fq' amounts" fep t
    restore
}
qui reghdfe ln_sold ecp if ambig == 0, `A'
show "T8B baseline" ecp t
qui reghdfe ln_sold ecp, `A'
show "T8B including ambiguous" ecp t
qui reghdfe ln_sold ecp if ambig == 0 & ai_name_flag == 0, `A'
show "T8B no AI names" ecp t
qui reghdfe ln_sold ecp if ambig == 0 & state != "CA", `A'
show "T8B no California" ecp t
qui reghdfe ln_sold ecp if ambig == 0 & (inlist(industry_raw, "Biotechnology", "Pharmaceuticals", "Manufacturing") | elig == 0), `A'
show "T8B bio/pharma/manufacturing" ecp t
gen post_f = filing_date > reform
gen ecp_f  = elig * corp * post_f
gen ym_f   = mofd(filing_date)
qui reghdfe ln_sold ecp_f if ambig == 0, absorb(st_gr_corp elig#ym_f corp#ym_f) vce(cluster st_gr)
show "T8B filing date" ecp_f t
qui reghdfe ln_sold ecp if ambig == 0 & priced_equity == 1, `A'
show "T8B priced equity only" ecp t
qui reghdfe ln_sold_orig ecp if ambig == 0, `A'
show "T8B amount at original notice" ecp t
qui reghdfe ln_sold ecp if ambig == 0 & drop_in_robustness != 1, `A'
show "T8B excl. DC NJ OR WA" ecp t
qui reghdfe ln_sold ecp if ambig == 0 & ym != tm(2025m6), `A'
show "T8B excl. June 2025" ecp t
qui reghdfe ln_sold ecp if ambig == 0 & sale_date_missing == 0, `A'
show "T8B first-sale date reported" ecp t

di as result _n "== Table 7 =="
use "$D/retiming_weekly.dta", clear
qui reg n yta yt ya ta y2025 treat i.wk_id, vce(robust)
show "T7 c1 OLS" yta t
qui poisson n yta yt ya ta y2025 treat i.wk_id, vce(robust)
show "T7 c2 Poisson" yta z
qui reg n ytpre ytpost yt i.yr#i.wk_id i.group4#i.wk_id, vce(robust)
show "T7 c3 weeks -3 to -1" ytpre t
show "T7 c3 weeks 0 to 2" ytpost t
qui reg ln_n ya y2025 i.wk_id if treat == 1, vce(robust)
show "T7 c4 within eligible C-corps" ya t
qui reg ln_n ypre ypost y2025 i.wk_id if treat == 1, vce(robust)
show "T7 c5 weeks -3 to -1" ypre t
show "T7 c5 weeks 0 to 2" ypost t

di as result _n "Done. Send qsbs2025_text_numbers.smcl"
log close
