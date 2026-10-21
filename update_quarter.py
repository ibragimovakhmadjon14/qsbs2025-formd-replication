#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
update_quarter.py - extend data/clean/offerings.dta with one further quarterly SEC Form D archive
without re-reading the full history.

Usage
    python update_quarter.py --archive data/raw/2026q3_d.zip [--data data/clean] [--table1 data/clean/table1_sample_construction.csv]

What it does (the same rules as prep.py, applied incrementally)
    1. reads the new archive (original notices and amendments filed in that quarter);
    2. applies the sample restrictions of Table 1 to the new original notices and derives the
       35 variables with prep.derive();
    3. round numbers: for issuers already in offerings.dta the count continues from their last
       notice; issuers that appear for the first time start at 1 (an issuer whose earlier notices
       were all outside the sample, e.g. before 2019 or as a fund, would be understated; in the
       September 2026 build this concerned about 2.6% of newly appearing issuers in a quarter);
    4. amendments filed in the new quarter raise amount_sold_180d and n_investors_180d of the
       originals they amend when they fall within 180 days of the original notice. Amendments are
       linked to originals through the file number (within the archive) and through the chain of
       previous accession numbers; when the chain leads to an amendment that is not in the archive,
       the original is identified as the issuer's only original notice filed in the preceding
       180 days;
    5. appends the new in-sample notices, writes offerings.dta and offerings.xlsx, and updates the
       counts of table1_sample_construction.csv (notice counts are exact; issuer counts of the
       intermediate steps add issuers not seen in the sample before).
The previous files are kept as offerings_before_<quarter>.dta / .csv.
"""
import argparse
import os
import sys
from datetime import timedelta

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prep  # noqa: E402

OUT_COLS = ["accessionnumber", "cik", "state", "qsbs_group", "industry_raw", "entity", "in_sample",
            "filing_date", "sale_date", "event_date", "sale_date_missing", "rev_range",
            "amount_sold", "amount_sold_180d", "n_investors", "n_investors_180d", "min_investment",
            "offering_amount", "round_no", "first_formd", "priced_equity", "safe_flag",
            "convertible_flag", "sec_equity", "sec_debt", "sec_other", "rule506b", "rule506c",
            "rule504", "inc_within_5y", "inc_year", "delaware_inc", "ai_name_flag", "is_fund",
            "bus_combination"]
INT_COLS = ["in_sample", "sale_date_missing", "round_no", "first_formd", "priced_equity", "safe_flag",
            "convertible_flag", "sec_equity", "sec_debt", "sec_other", "rule506b", "rule506c", "rule504",
            "inc_within_5y", "delaware_inc", "ai_name_flag", "is_fund", "bus_combination"]
LABELS = {
    "qsbs_group": "eligible / excluded / ambiguous (Table A1)",
    "in_sample": "1 = operating corp/LLC in a US state, first sale from 2019",
    "event_date": "first-sale date (filing date if missing)",
    "amount_sold_180d": "max amount sold reported within 180 days",
    "round_no": "number of the issuer's Form D notices since 2008",
}


def log(msg):
    print(msg, flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--archive", required=True, help="the new quarterly archive, e.g. data/raw/2026q3_d.zip")
    ap.add_argument("--data", default="data/clean", help="folder with offerings.dta")
    ap.add_argument("--table1", default=None, help="table1_sample_construction.csv to update (default: in --data)")
    ap.add_argument("--no-xlsx", action="store_true")
    args = ap.parse_args()

    quarter = os.path.basename(args.archive).split("_")[0].lower()        # e.g. 2026q3
    dta = os.path.join(args.data, "offerings.dta")
    tab1_path = args.table1 or os.path.join(args.data, "table1_sample_construction.csv")

    old = pd.read_stata(dta)
    for c in ["filing_date", "sale_date", "event_date"]:
        old[c] = pd.to_datetime(old[c])
    log(f"existing offerings.dta: {len(old):,} notices, filings up to {old['filing_date'].max().date()}")
    if old["filing_date"].max() >= pd.Timestamp(int(quarter[:4]), 3 * int(quarter[-1]) - 2, 1):
        sys.exit(f"offerings.dta already contains filings from {quarter}; nothing to do")

    # ---- 1. the new quarter
    tmpdir = os.path.dirname(os.path.abspath(args.archive))
    allf = prep.read_archives(tmpdir) if len([f for f in os.listdir(tmpdir) if f.lower().endswith(".zip")]) == 1 \
        else prep.read_archives_files([args.archive])
    is_orig = ~allf["isamendment"]
    orig = allf[is_orig].copy()
    amend = allf[~is_orig].copy()
    log(f"{quarter}: {len(allf):,} submissions, {len(orig):,} original notices, {len(amend):,} amendments")

    sale = orig["sale_date"].where(~orig["yettooccur"], pd.NaT)
    orig["sale_date"] = sale
    orig["sale_date_missing"] = sale.isna().astype(int)
    orig["event_date"] = sale.fillna(orig["filing_date"])

    # ---- 2. round numbers: continue each issuer's count from the existing file
    base = old.groupby("cik")["round_no"].max()
    orig = orig.sort_values(["cik", "event_date", "filing_date", "accessionnumber"])
    orig["round_no"] = orig["cik"].map(base).fillna(0).astype(int) + orig.groupby("cik").cumcount() + 1
    orig["first_formd"] = (orig["round_no"] == 1).astype(int)

    # ---- 3. amendments within the archive -> new originals (file number)
    key = orig[["accessionnumber", "file_num", "filing_date"]].rename(
        columns={"accessionnumber": "orig_accession", "filing_date": "orig_filing"})
    am = amend.merge(key, on="file_num", how="inner")
    am = am[(am["filing_date"] >= am["orig_filing"]) & (am["filing_date"] <= am["orig_filing"] + timedelta(days=180))]
    agg = am.groupby("orig_accession").agg(amount_sold_180d=("amount_sold", "max"), n_investors_180d=("n_investors", "max"))
    orig = orig.merge(agg, left_on="accessionnumber", right_index=True, how="left")
    orig["amount_sold_180d"] = np.fmax(orig["amount_sold"], orig["amount_sold_180d"])
    orig["n_investors_180d"] = np.fmax(orig["n_investors"], orig["n_investors_180d"])

    # ---- 4. amendments in the archive -> originals already in offerings.dta
    old_acc = set(old["accessionnumber"])
    new_orig_acc = set(orig["accessionnumber"])
    prev = dict(zip(amend["accessionnumber"], amend["prev_accession"]))
    amend_acc = set(amend["accessionnumber"])
    old_by_cik = old.groupby("cik")

    def root_of(acc, depth=0):
        p = prev.get(acc, "")
        if p in old_acc:
            return p
        if p in new_orig_acc:
            return None            # handled through the file number above
        if p in amend_acc and depth < 50:
            return root_of(p, depth + 1)
        return "?"                 # chain leaves the archive

    amend["root"] = amend["accessionnumber"].map(root_of)
    unresolved = amend["root"] == "?"
    resolved_by_cik = 0
    for idx in amend.index[unresolved]:
        cik = amend.at[idx, "cik"]; fd = amend.at[idx, "filing_date"]
        if cik not in old_by_cik.groups:
            amend.at[idx, "root"] = None; continue
        cand = old_by_cik.get_group(cik)
        cand = cand[(cand["filing_date"] <= fd) & (cand["filing_date"] >= fd - timedelta(days=180))]
        if len(cand) == 1:
            amend.at[idx, "root"] = cand["accessionnumber"].iloc[0]; resolved_by_cik += 1
        else:
            amend.at[idx, "root"] = None
    link = amend[amend["root"].isin(old_acc)].merge(
        old[["accessionnumber", "filing_date"]].rename(columns={"accessionnumber": "root", "filing_date": "orig_filing"}),
        on="root", how="inner")
    link = link[(link["filing_date"] >= link["orig_filing"]) & (link["filing_date"] <= link["orig_filing"] + timedelta(days=180))]
    upd = link.groupby("root").agg(a=("amount_sold", "max"), n=("n_investors", "max"))
    old = old.set_index("accessionnumber")
    before_a = old.loc[upd.index, "amount_sold_180d"].copy()
    old.loc[upd.index, "amount_sold_180d"] = np.fmax(old.loc[upd.index, "amount_sold_180d"], upd["a"])
    old.loc[upd.index, "n_investors_180d"] = np.fmax(old.loc[upd.index, "n_investors_180d"], upd["n"])
    n_changed = int((old.loc[upd.index, "amount_sold_180d"] != before_a).sum())
    old = old.reset_index()
    log(f"amendments linked to earlier originals: {len(upd):,} originals ({resolved_by_cik} linked through the issuer), "
        f"amount_sold_180d raised for {n_changed:,} of them; "
        f"{int((amend['root'].isna()).sum()):,} amendments could not be linked to an earlier original")

    # ---- 5. sample restrictions and variables for the new originals (Table 1 steps)
    steps = []
    d = orig[orig["event_date"] >= prep.SAMPLE_START].copy()
    steps.append(("First sale on or after 1 January 2019", d))
    d["is_fund"] = ((d["industry_raw"] == "Pooled Investment Fund") |
                    d["fundtype"].notna() & (d["fundtype"].astype(str).str.strip() != "")).astype(int)
    d = d[d["is_fund"] == 0]; steps.append(("Excluding pooled investment funds", d))
    d = d[d["bus_combination"] == 0]; steps.append(("Excluding business-combination offerings", d))
    d = d[d["state"].isin(prep.US_STATES)]; steps.append(("Issuers located in the 50 states and DC", d))
    d["entity"] = d["entitytype"].map({"Corporation": "corp", "Limited Liability Company": "llc"})
    d = d[d["entity"].notna()]; steps.append(("Corporations and LLCs only", d))
    d = prep.derive(d)
    new = d[OUT_COLS].copy()
    log(f"new in-sample notices from {quarter}: {len(new):,}; first-sale months: "
        + ", ".join(f"{k}: {v}" for k, v in new["event_date"].dt.to_period("M").value_counts().sort_index().items()))

    # ---- 6. append and write
    out = pd.concat([old[OUT_COLS], new], ignore_index=True).sort_values(["event_date", "accessionnumber"]).reset_index(drop=True)
    assert out["accessionnumber"].is_unique
    for c in INT_COLS:
        out[c] = out[c].astype("int32")
    os.replace(dta, os.path.join(args.data, f"offerings_before_{quarter}.dta"))
    out.to_stata(dta, write_index=False, version=118,
                 convert_dates={"filing_date": "td", "sale_date": "td", "event_date": "td"}, variable_labels=LABELS)
    log(f"written {dta}: {len(out):,} notices, {out['cik'].nunique():,} issuers")
    if not args.no_xlsx:
        x = out.copy()
        for c in ["filing_date", "sale_date", "event_date"]:
            x[c] = x[c].dt.strftime("%Y-%m-%d")
        x.to_excel(os.path.join(args.data, "offerings.xlsx"), sheet_name="offerings", index=False)
        log("written offerings.xlsx")

    # ---- 7. Table 1 counts: notices exact; issuers of intermediate steps add issuers not seen in the sample before
    tab1 = pd.read_csv(tab1_path)
    os.replace(tab1_path, tab1_path.replace(".csv", f"_before_{quarter}.csv"))
    old_in_sample_ciks = set(old["cik"])
    def new_issuers(df):
        return int(df.loc[~df["cik"].isin(old_in_sample_ciks), "cik"].nunique())
    def prev(label_start, col):
        m = tab1["step"].str.lower().str.startswith(label_start)
        return int(tab1.loc[m, col].iloc[0]) if m.any() and pd.notna(tab1.loc[m, col].iloc[0]) else None
    rows = []
    rows.append(("All Form D submissions (original notices and amendments)", (prev("all form d", "notices") or 763014) + len(allf), None))
    rows.append(("Original notices", (prev("original notices", "notices") or 467925) + len(orig), None))
    first_labels = {"First sale on or after 1 January 2019": ("new notices from sample start", "first sale on or after")}
    for label, df in steps:
        starts = first_labels.get(label, (label.lower()[:25],))
        pn = pi = None
        for st in starts:
            pn = pn or prev(st, "notices"); pi = pi or prev(st, "issuers")
        rows.append((label, (pn or 0) + len(df), (pi or 0) + new_issuers(df)))
    main = out[out["qsbs_group"].isin(["eligible", "excluded"])]
    rows.append(("Classifiable industry group (eligible or excluded)", len(main), int(main["cik"].nunique())))
    tab1 = pd.DataFrame(rows, columns=["step", "notices", "issuers"])
    tab1["issuers"] = tab1["issuers"].astype("Int64")
    tab1.to_csv(tab1_path, index=False)
    log("Table 1 counts (increments from this quarter: " + ", ".join(f"{len(df):,}" for _, df in steps) + "):\n" + tab1.to_string(index=False))


if __name__ == "__main__":
    main()
