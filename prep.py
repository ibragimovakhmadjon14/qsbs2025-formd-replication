#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
prep.py - build data/clean/offerings.dta from the SEC Form D Data Sets.

Replication package for: "Did the 2025 expansion of Qualified Small Business Stock relief
move start-up fundraising? Early evidence from Form D notices" (Ibragimov and Ruzieva, 2026).

Input
    data/raw/*.zip      the quarterly Form D Data Sets published by the SEC
                        (https://www.sec.gov/data-research/sec-markets-data/form-d-data-sets),
                        e.g. 2008q1_d.zip ... 2026q2_d.zip. Each archive contains the tab-separated
                        files FORMDSUBMISSION.tsv, ISSUERS.tsv and OFFERING.tsv (the files
                        RECIPIENTS, RELATEDPERSONS and SIGNATURES are not used).
Output
    data/clean/offerings.dta                 one row per original Form D notice in the broad sample
    data/clean/offerings.xlsx                the same data as an Excel workbook (sheet "offerings")
    data/clean/table1_sample_construction.csv  counts behind Table 1 of the paper

Sample construction (Table 1 of the paper)
    1. all submissions in the archives (original notices and amendments)
    2. original notices only (ISAMENDMENT = false)
    3. first sale on or after 1 January 2019; the date of first sale is OFFERING.SALE_DATE and
       the filing date when no sale date is reported
    4. drop pooled investment funds (industry group "Pooled Investment Fund" or an investment
       fund type reported)
    5. drop offerings related to a business combination
    6. keep issuers located in the 50 states and the District of Columbia
    7. keep issuers organised as corporations or limited liability companies
The end-of-sample filter (first sale on or before 15 September 2026 in the submitted version;
15 June 2026 in the June 2026 data vintage) and the classification into eligible,
excluded and ambiguous industry groups (Table A1) are applied by qsbs2025_replication.do,
which also drops one notice whose reported sale date lies after the end of the data.

Variables are documented in Table A3 of the paper; the full list is at the end of this file.

Usage
    python prep.py                      build from data/raw into data/clean
    python prep.py --raw PATH --out PATH
    python prep.py --check              build to data/clean/offerings_rebuilt.dta and compare it with the
                                        existing data/clean/offerings.dta (which is left untouched)
    python prep.py --no-xlsx            skip the Excel copy (faster)

Requires Python 3.10+, pandas >= 2.0, openpyxl (Excel output only). Runtime: about 5-15 minutes
for 74 quarterly archives; memory use peaks at about 4 GB.
"""
import argparse
import csv
import io
import os
import re
import sys
import zipfile
from datetime import timedelta

import numpy as np
import pandas as pd

SAMPLE_START = pd.Timestamp("2019-01-01")
AMENDMENT_WINDOW_DAYS = 180

US_STATES = {
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", "HI", "ID", "IL", "IN", "IA",
    "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM",
    "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA",
    "WV", "WI", "WY",
}

# Form D industry groups (Item 4) -> Section 1202(e)(3) classification (Table A1 of the paper)
QSBS_GROUP = {
    # eligible
    "Computers": "eligible", "Telecommunications": "eligible", "Other Technology": "eligible",
    "Biotechnology": "eligible", "Pharmaceuticals": "eligible",
    "Manufacturing": "eligible", "Retailing": "eligible",
    "Electric Utilities": "eligible", "Energy Conservation": "eligible",
    "Environmental Services": "eligible", "Other Energy": "eligible",
    "Airlines and Airports": "eligible", "Tourism and Travel Services": "eligible", "Other Travel": "eligible",
    # excluded
    "Commercial Banking": "excluded", "Insurance": "excluded", "Investing": "excluded",
    "Investment Banking": "excluded", "Other Banking and Financial Services": "excluded",
    "Health Insurance": "excluded", "Hospitals and Physicians": "excluded",
    "Restaurants": "excluded", "Lodging and Conventions": "excluded",
    "Agriculture": "excluded", "Oil and Gas": "excluded", "Coal Mining": "excluded",
    # ambiguous
    "Business Services": "ambiguous", "Other Health Care": "ambiguous", "Other": "ambiguous",
    "Commercial": "ambiguous", "Residential": "ambiguous", "REITS and Finance": "ambiguous",
    "Other Real Estate": "ambiguous", "Construction": "ambiguous",
    # not an operating company
    "Pooled Investment Fund": "fund",
}

# logical field -> candidate column names in the SEC files (matched case-insensitively)
COLS = {
    "submission": {
        "accession": ["ACCESSIONNUMBER"],
        "file_num": ["FILE_NUM", "FILENUM"],
        "filing_date": ["FILING_DATE", "FILINGDATE"],
        "submissiontype": ["SUBMISSIONTYPE", "SUBMISSION_TYPE"],
    },
    "issuers": {
        "accession": ["ACCESSIONNUMBER"],
        "is_primary": ["IS_PRIMARYISSUER_FLAG", "ISPRIMARYISSUERFLAG"],
        "seq": ["ISSUER_SEQ_KEY", "ISSUERSEQKEY"],
        "cik": ["CIK"],
        "name": ["ENTITYNAME", "ISSUERNAME"],
        "state": ["STATEORCOUNTRY", "STATE_OR_COUNTRY"],
        "jurisdiction": ["JURISDICTIONOFINC", "JURISDICTION_OF_INC"],
        "entitytype": ["ENTITYTYPE", "ENTITY_TYPE"],
        "inc_span": ["YEAROFINC_TIMESPAN_CHOICE", "YEAROFINC_TIMESPAN", "YEAROFINCTIMESPANCHOICE"],
        "inc_year": ["YEAROFINC_VALUE_ENTERED", "YEAROFINC_VALUE", "YEAROFINCVALUEENTERED"],
    },
    "offering": {
        "accession": ["ACCESSIONNUMBER"],
        "industry": ["INDUSTRYGROUPTYPE", "INDUSTRY_GROUP_TYPE"],
        "fundtype": ["INVESTMENTFUNDTYPE", "INVESTMENT_FUND_TYPE"],
        "revenue": ["REVENUERANGE", "REVENUE_RANGE"],
        "exemptions": ["FEDERALEXEMPTIONS_ITEMS_LIST", "FEDERALEXEMPTIONS_ITEMS", "FEDERAL_EXEMPTIONS_ITEMS_LIST"],
        "isamendment": ["ISAMENDMENT", "IS_AMENDMENT"],
        "prev_accession": ["PREVIOUSACCESSIONNUMBER", "PREVIOUS_ACCESSION_NUMBER"],
        "sale_date": ["SALE_DATE", "SALEDATE"],
        "yettooccur": ["YETTOOCCUR", "YET_TO_OCCUR"],
        "is_equity": ["ISEQUITYTYPE"],
        "is_debt": ["ISDEBTTYPE"],
        "is_other": ["ISOTHERTYPE"],
        "other_desc": ["DESCRIPTIONOFOTHERTYPE", "DESCRIPTION_OF_OTHER_TYPE"],
        "is_buscomb": ["ISBUSINESSCOMBINATIONTRANS", "ISBUSINESSCOMBINATIONTRANSACTION", "IS_BUSINESS_COMBINATION_TRANS"],
        "min_investment": ["MINIMUMINVESTMENTACCEPTED", "MINIMUM_INVESTMENT_ACCEPTED"],
        "offering_amount": ["TOTALOFFERINGAMOUNT", "TOTAL_OFFERING_AMOUNT"],
        "amount_sold": ["TOTALAMOUNTSOLD", "TOTAL_AMOUNT_SOLD"],
        "n_investors": ["TOTALNUMBERALREADYINVESTED", "TOTAL_NUMBER_ALREADY_INVESTED"],
    },
}
FILES = {"submission": "FORMDSUBMISSION", "issuers": "ISSUERS", "offering": "OFFERING"}


# ----------------------------------------------------------------------------- helpers
def log(msg):
    print(msg, flush=True)


def find_member(zf, stem):
    """Return the archive member whose file name starts with `stem` (case-insensitive), or None."""
    for name in zf.namelist():
        base = os.path.basename(name).lower()
        if base.startswith(stem.lower()) and base.endswith((".tsv", ".txt", ".csv")):
            return name
    return None


def read_tsv(zf, member):
    raw = zf.read(member)
    for enc in ("utf-8", "latin-1"):
        try:
            text = raw.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    df = pd.read_csv(io.StringIO(text), sep="\t", dtype=str, quoting=csv.QUOTE_NONE,
                     keep_default_na=False, na_values=[""], engine="python", on_bad_lines="warn")
    df.columns = [c.strip().upper().lstrip("﻿") for c in df.columns]
    return df


def pick(df, candidates, required=True, what=""):
    for c in candidates:
        if c.upper() in df.columns:
            return df[c.upper()]
    if required:
        raise KeyError(f"none of {candidates} found for {what}; columns are {list(df.columns)[:12]}...")
    return pd.Series([np.nan] * len(df), index=df.index, dtype="object")


def to_bool(s):
    return s.astype(str).str.strip().str.lower().isin(["true", "t", "1", "y", "yes"])


def to_date(s):
    """Parse the date formats used in the SEC files (DD-MON-YYYY, YYYY-MM-DD, MM/DD/YYYY, YYYYMMDD)."""
    s = s.astype(str).str.strip()
    s = s.where(~s.str.lower().isin(["", "nan", "none", "null"]), None)
    sample = s.dropna().head(200)
    fmt = None
    for f in ("%d-%b-%Y", "%Y-%m-%d", "%m/%d/%Y", "%Y%m%d", "%d-%b-%y"):
        try:
            pd.to_datetime(sample, format=f)
            fmt = f
            break
        except (ValueError, TypeError):
            continue
    if fmt:
        out = pd.to_datetime(s, format=fmt, errors="coerce")
    else:
        out = pd.to_datetime(s, errors="coerce")
    return out


def to_num(s):
    return pd.to_numeric(s.astype(str).str.replace(",", "", regex=False).str.strip(), errors="coerce")


def clean_cik(s):
    s = s.astype(str).str.strip().str.replace(r"\.0$", "", regex=True)
    return s.str.zfill(10)


# ----------------------------------------------------------------------------- read all archives
def read_archives(raw_dir):
    """Read every quarterly archive in a folder."""
    zips = sorted(f for f in os.listdir(raw_dir) if f.lower().endswith(".zip"))
    if not zips:
        sys.exit(f"no .zip archives found in {raw_dir}")
    return read_archives_files([os.path.join(raw_dir, z) for z in zips])


def read_archives_files(paths):
    """Read the given quarterly archives (full paths) into one frame, one row per submission."""
    parts = []
    for path in paths:
        z = os.path.basename(path)
        with zipfile.ZipFile(path) as zf:
            members = {k: find_member(zf, v) for k, v in FILES.items()}
            missing = [k for k, m in members.items() if m is None]
            if missing:
                log(f"  {z}: missing {missing}, skipped")
                continue
            sub = read_tsv(zf, members["submission"])
            iss = read_tsv(zf, members["issuers"])
            off = read_tsv(zf, members["offering"])
        C = COLS["submission"]
        s = pd.DataFrame({
            "accessionnumber": pick(sub, C["accession"], what="submission accession").str.strip(),
            "file_num": pick(sub, C["file_num"], required=False).astype(str).str.strip(),
            "filing_date": to_date(pick(sub, C["filing_date"], what="filing date")),
            "submissiontype": pick(sub, C["submissiontype"], required=False).astype(str).str.strip(),
        })
        C = COLS["issuers"]
        i = pd.DataFrame({
            "accessionnumber": pick(iss, C["accession"], what="issuer accession").str.strip(),
            "is_primary": to_bool(pick(iss, C["is_primary"], required=False)),
            "seq": to_num(pick(iss, C["seq"], required=False)),
            "cik": clean_cik(pick(iss, C["cik"], what="cik")),
            "name": pick(iss, C["name"], required=False).astype(str),
            "state": pick(iss, C["state"], what="state").astype(str).str.strip().str.upper(),
            "jurisdiction": pick(iss, C["jurisdiction"], required=False).astype(str).str.strip().str.upper(),
            "entitytype": pick(iss, C["entitytype"], what="entity type").astype(str).str.strip(),
            "inc_span": pick(iss, C["inc_span"], required=False).astype(str).str.strip(),
            "inc_year": to_num(pick(iss, C["inc_year"], required=False)),
        })
        # one row per filing: the primary issuer (flag), else the first issuer listed
        if i["is_primary"].any():
            prim = i[i["is_primary"]]
            rest = i[~i["accessionnumber"].isin(prim["accessionnumber"])].sort_values(["accessionnumber", "seq"])
            i = pd.concat([prim, rest.drop_duplicates("accessionnumber")], ignore_index=True)
        else:
            i = i.sort_values(["accessionnumber", "seq"])
        i = i.drop_duplicates("accessionnumber")
        C = COLS["offering"]
        o = pd.DataFrame({
            "accessionnumber": pick(off, C["accession"], what="offering accession").str.strip(),
            "industry_raw": pick(off, C["industry"], what="industry").astype(str).str.strip(),
            "fundtype": pick(off, C["fundtype"], required=False),
            "rev_range": pick(off, C["revenue"], required=False).astype(str).str.strip(),
            "exemptions": pick(off, C["exemptions"], required=False).astype(str),
            "isamendment": to_bool(pick(off, C["isamendment"], what="isamendment")),
            "prev_accession": pick(off, C["prev_accession"], required=False).astype(str).str.strip(),
            "sale_date": to_date(pick(off, C["sale_date"], what="sale date")),
            "yettooccur": to_bool(pick(off, C["yettooccur"], required=False)),
            "sec_equity": to_bool(pick(off, C["is_equity"], what="equity flag")).astype(int),
            "sec_debt": to_bool(pick(off, C["is_debt"], what="debt flag")).astype(int),
            "sec_other": to_bool(pick(off, C["is_other"], what="other flag")).astype(int),
            "other_desc": pick(off, C["other_desc"], required=False).astype(str),
            "bus_combination": to_bool(pick(off, C["is_buscomb"], what="business combination")).astype(int),
            "min_investment": to_num(pick(off, C["min_investment"], required=False)),
            "offering_amount": to_num(pick(off, C["offering_amount"], required=False)),  # "Indefinite" -> missing
            "amount_sold": to_num(pick(off, C["amount_sold"], what="amount sold")),
            "n_investors": to_num(pick(off, C["n_investors"], what="number of investors")),
        }).drop_duplicates("accessionnumber")
        d = s.merge(i, on="accessionnumber", how="left").merge(o, on="accessionnumber", how="left")
        d["source_archive"] = z
        parts.append(d)
        log(f"  {z}: {len(d):>7,} submissions")
    allf = pd.concat(parts, ignore_index=True)
    before = len(allf)
    allf = allf.sort_values(["accessionnumber", "source_archive"]).drop_duplicates("accessionnumber", keep="last")
    if len(allf) < before:
        log(f"  {before - len(allf):,} duplicate accession numbers across archives removed")
    return allf.reset_index(drop=True)


def derive(d):
    """Add the variables of offerings.dta to a frame of original notices (after the sample restrictions)."""
    d["qsbs_group"] = d["industry_raw"].map(QSBS_GROUP).fillna("ambiguous")
    d["in_sample"] = 1
    d["priced_equity"] = ((d["sec_equity"] == 1) & (d["sec_debt"] == 0) & (d["sec_other"] == 0)).astype(int)
    desc = d["other_desc"].fillna("").astype(str)
    d["safe_flag"] = ((d["sec_other"] == 1) &
                      (desc.str.contains(r"\bSAFE\b|\bSAFEs\b", regex=True) |
                       desc.str.contains(r"simple agreement", case=False, regex=True))).astype(int)
    d["convertible_flag"] = ((d["sec_other"] == 1) &
                             desc.str.contains(r"convertible|conv\.?\s*note", case=False, regex=True)).astype(int)
    ex = d["exemptions"].fillna("").astype(str)
    d["rule506b"] = ex.str.contains(r"06b", case=False, regex=True).astype(int)
    d["rule506c"] = ex.str.contains(r"06c", case=False, regex=True).astype(int)
    d["rule504"] = ex.str.contains(r"(?<!\d)04(?!\d)", regex=True).astype(int)
    d["inc_within_5y"] = d["inc_span"].str.lower().str.contains("within", na=False).astype(int)
    d.loc[d["inc_within_5y"] == 0, "inc_year"] = np.nan
    d["delaware_inc"] = d["jurisdiction"].isin(["DELAWARE", "DE"]).astype(int)
    name = d["name"].fillna("").astype(str)
    d["ai_name_flag"] = (name.str.contains(r"(?<![A-Za-z])A\.?I\.?(?![A-Za-z])", regex=True) |
                         name.str.contains(r"artificial intelligence", case=False, regex=True) |
                         name.str.lower().str.endswith(".ai")).astype(int)
    d["min_investment"] = d["min_investment"].fillna(0)
    d["n_investors"] = d["n_investors"].fillna(0)
    d["amount_sold"] = d["amount_sold"].fillna(0)
    return d


# ----------------------------------------------------------------------------- build
def build(raw_dir, out_dir, write_xlsx=True, suffix=""):
    log(f"Reading archives from {raw_dir}")
    allf = read_archives(raw_dir)
    counts = []

    def step(label, df, issuers=True):
        n_iss = df["cik"].nunique() if issuers else None
        counts.append((label, len(df), n_iss))
        log(f"  {label:<70} {len(df):>9,}" + (f"  {n_iss:>8,}" if issuers else ""))

    step("All Form D submissions (original notices and amendments)", allf, issuers=False)

    # amendments: amount sold and number of investors reported within 180 days of the original
    is_orig = ~allf["isamendment"]
    if allf["submissiontype"].str.upper().isin(["D", "D/A"]).any():
        is_orig = is_orig & ~allf["submissiontype"].str.upper().eq("D/A")
    orig = allf[is_orig].copy()
    amend = allf[~is_orig].copy()
    step("Original notices", orig, issuers=False)

    # date of first sale: sale date, filing date when missing or yet to occur
    sale = orig["sale_date"].where(~orig["yettooccur"], pd.NaT)
    orig["sale_date"] = sale
    orig["sale_date_missing"] = sale.isna().astype(int)
    orig["event_date"] = sale.fillna(orig["filing_date"])

    # round number: the issuer's original notices since 2008 in order of first sale
    orig = orig.sort_values(["cik", "event_date", "filing_date", "accessionnumber"])
    orig["round_no"] = orig.groupby("cik").cumcount() + 1
    orig["first_formd"] = (orig["round_no"] == 1).astype(int)

    # link amendments to originals through the offering file number; fall back to the chain of
    # previous accession numbers when the file number is missing
    key_orig = orig[["accessionnumber", "file_num", "filing_date"]].rename(
        columns={"accessionnumber": "orig_accession", "filing_date": "orig_filing"})
    key_orig = key_orig[key_orig["file_num"].notna() & ~key_orig["file_num"].isin(["", "nan", "None"])]
    if amend["file_num"].replace({"nan": None, "": None}).notna().mean() > 0.9:
        am = amend[~amend["file_num"].isin(["", "nan", "None"])].merge(key_orig, on="file_num", how="inner")
    else:
        root = dict(zip(orig["accessionnumber"], orig["accessionnumber"]))
        prev = dict(zip(amend["accessionnumber"], amend["prev_accession"]))
        def find_root(a, depth=0):
            if a in root:
                return root[a]
            p = prev.get(a)
            if p is None or depth > 50:
                return None
            r = find_root(p, depth + 1)
            root[a] = r
            return r
        amend["orig_accession"] = amend["accessionnumber"].map(find_root)
        am = amend.dropna(subset=["orig_accession"]).merge(
            key_orig[["orig_accession", "orig_filing"]], on="orig_accession", how="inner")
    am = am[(am["filing_date"] >= am["orig_filing"]) &
            (am["filing_date"] <= am["orig_filing"] + timedelta(days=AMENDMENT_WINDOW_DAYS))]
    agg = am.groupby("orig_accession").agg(amount_sold_180d=("amount_sold", "max"),
                                           n_investors_180d=("n_investors", "max"))
    orig = orig.merge(agg, left_on="accessionnumber", right_index=True, how="left")
    orig["amount_sold_180d"] = np.fmax(orig["amount_sold"], orig["amount_sold_180d"])
    orig["n_investors_180d"] = np.fmax(orig["n_investors"], orig["n_investors_180d"])

    # sample restrictions (Table 1)
    d = orig[orig["event_date"] >= SAMPLE_START].copy()
    step("First sale on or after 1 January 2019", d)
    d["is_fund"] = ((d["industry_raw"] == "Pooled Investment Fund") |
                    d["fundtype"].notna() & (d["fundtype"].astype(str).str.strip() != "")).astype(int)
    d = d[d["is_fund"] == 0]
    step("Excluding pooled investment funds", d)
    d = d[d["bus_combination"] == 0]
    step("Excluding business-combination offerings", d)
    d = d[d["state"].isin(US_STATES)]
    step("Issuers located in the 50 states and DC", d)
    d["entity"] = d["entitytype"].map({"Corporation": "corp", "Limited Liability Company": "llc"})
    d = d[d["entity"].notna()]
    step("Corporations and LLCs only", d)

    d = derive(d)

    out_cols = ["accessionnumber", "cik", "state", "qsbs_group", "industry_raw", "entity", "in_sample",
                "filing_date", "sale_date", "event_date", "sale_date_missing", "rev_range",
                "amount_sold", "amount_sold_180d", "n_investors", "n_investors_180d", "min_investment",
                "offering_amount", "round_no", "first_formd", "priced_equity", "safe_flag",
                "convertible_flag", "sec_equity", "sec_debt", "sec_other", "rule506b", "rule506c",
                "rule504", "inc_within_5y", "inc_year", "delaware_inc", "ai_name_flag", "is_fund",
                "bus_combination"]
    out = d[out_cols].sort_values(["event_date", "accessionnumber"]).reset_index(drop=True)
    for c in ["in_sample", "sale_date_missing", "round_no", "first_formd", "priced_equity", "safe_flag",
              "convertible_flag", "sec_equity", "sec_debt", "sec_other", "rule506b", "rule506c", "rule504",
              "inc_within_5y", "delaware_inc", "ai_name_flag", "is_fund", "bus_combination"]:
        out[c] = out[c].astype("int32")

    # classification count for information (the do-file applies the end-of-sample cut-off first)
    main = out[out["qsbs_group"].isin(["eligible", "excluded"])]
    counts.append(("Classifiable industry group (eligible or excluded)", len(main), main["cik"].nunique()))

    os.makedirs(out_dir, exist_ok=True)
    labels = {
        "qsbs_group": "eligible / excluded / ambiguous (Table A1)",
        "in_sample": "1 = operating corp/LLC in a US state, first sale from 2019",
        "event_date": "first-sale date (filing date if missing)",
        "amount_sold_180d": "max amount sold reported within 180 days",
        "round_no": "number of the issuer's Form D notices since 2008",
    }
    dta = os.path.join(out_dir, f"offerings{suffix}.dta")
    out.to_stata(dta, write_index=False, version=118,
                 convert_dates={"filing_date": "td", "sale_date": "td", "event_date": "td"},
                 variable_labels=labels)
    log(f"written {dta}: {len(out):,} rows, {out.shape[1]} variables")
    tab1 = pd.DataFrame(counts, columns=["step", "notices", "issuers"])
    tab1["issuers"] = tab1["issuers"].astype("Int64")
    tab1.to_csv(os.path.join(out_dir, f"table1_sample_construction{suffix}.csv"), index=False)
    if write_xlsx:
        x = out.copy()
        for c in ["filing_date", "sale_date", "event_date"]:
            x[c] = x[c].dt.strftime("%Y-%m-%d")
        x.to_excel(os.path.join(out_dir, f"offerings{suffix}.xlsx"), sheet_name="offerings", index=False)
        log(f"written offerings{suffix}.xlsx")
    return out


# ----------------------------------------------------------------------------- check
def check(new, ref_path):
    ref = pd.read_stata(ref_path)
    log(f"\nComparison with {ref_path}")
    log(f"  rows: new {len(new):,}  reference {len(ref):,}")
    common = set(new["accessionnumber"]) & set(ref["accessionnumber"])
    log(f"  accession numbers in common: {len(common):,} "
        f"(only new: {len(set(new['accessionnumber']) - common):,}; only reference: {len(set(ref['accessionnumber']) - common):,})")
    a = new.set_index("accessionnumber").loc[sorted(common)]
    b = ref.set_index("accessionnumber").loc[sorted(common)]
    for c in new.columns:
        if c == "accessionnumber" or c not in b.columns:
            continue
        x, y = a[c], b[c]
        if pd.api.types.is_datetime64_any_dtype(x) or pd.api.types.is_datetime64_any_dtype(y):
            xd, yd = pd.to_datetime(x, errors="coerce"), pd.to_datetime(y, errors="coerce")
            same = (xd.dt.normalize() == yd.dt.normalize()) | (xd.isna() & yd.isna())
        elif pd.api.types.is_numeric_dtype(x) and pd.api.types.is_numeric_dtype(y):
            same = np.isclose(x.astype(float), y.astype(float), equal_nan=True, rtol=0, atol=1e-6)
        else:
            same = (x.astype(str).fillna("") == y.astype(str).fillna(""))
        log(f"  {c:<20} identical in {np.mean(same) * 100:6.2f}% of common rows")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--raw", default="data/raw", help="folder with the quarterly SEC archives")
    ap.add_argument("--out", default="data/clean", help="output folder")
    ap.add_argument("--no-xlsx", action="store_true", help="do not write offerings.xlsx")
    ap.add_argument("--check", action="store_true", help="compare the result with an existing offerings.dta in --out")
    args = ap.parse_args()
    ref = os.path.join(args.out, "offerings.dta")
    if args.check and os.path.exists(ref):
        # the existing file is left untouched; the rebuilt data are written with the suffix _rebuilt
        new = build(args.raw, args.out, write_xlsx=not args.no_xlsx, suffix="_rebuilt")
        check(new, ref)
    else:
        if args.check:
            log(f"{ref} not found: nothing to compare with; building normally")
        build(args.raw, args.out, write_xlsx=not args.no_xlsx)
