"""Combine four GitHub-only research groups without mixing overlapping equity.

Runs on GitHub-hosted runner. No market-data downloads, VPS, MT5 or orders.
"""
from __future__ import annotations
import argparse
import csv
from pathlib import Path
import json

REQUIRED = {
    "EURUSD","GBPUSD","USDJPY","AUDUSD","USDCAD",
    "EURGBP","EURJPY","XAUUSD","USOIL","US30","NAS100"}
UNAVAILABLE = ["USDCHF","NZDUSD","GBPJPY","AUDJPY","EURAUD","BTCUSD"]


def aggregate_reports(folder: Path, output: Path):
    paths = sorted(folder.glob("*/summary.json"))
    if not paths:
        raise RuntimeError("no_public_strategy_group_reports")
    combined = {}
    all_trades = []
    screening = {}
    for path in paths:
        part = json.loads(path.read_text(encoding="utf-8"))
        if (part.get("orders_sent") != 0 or part.get("production") != "WAIT"
            or part.get("actual_bid_ask_verified") is not False
            or part.get("independent_holdout") is not False):
            raise ValueError("unsafe_public_research_report")
        for market, report in part["symbols"].items():
            if market in combined or market not in REQUIRED:
                raise ValueError("duplicate_or_unexpected_market")
            if report["public_sample"]["actual_historical_bid_ask_available"]:
                raise ValueError("wrong_evidence_class")
            if report["scanner"]["status"] != "OK":
                raise ValueError("market_scan_incomplete")
            combined[market] = report
        for key, record in part.get("monthly_strategy_screen",{}).items():
            if key in screening:
                raise ValueError("duplicated_strategy_screen")
            screening[key] = record
        trades_path = path.parent/"paper_trades.csv"
        if trades_path.exists():
            with trades_path.open(newline="",encoding="utf-8") as f:
                all_trades.extend(list(csv.DictReader(f)))
    if set(combined) != REQUIRED:
        raise RuntimeError("incomplete_market_scope:"+",".join(sorted(REQUIRED-set(combined))))
    for row in all_trades:
        if row["symbol"] not in REQUIRED:
            raise ValueError("paper_trade_wrong_market")
    qualified = []
    for key,entry in screening.items():
        if entry["passed_exploratory_screen"]:
            qualified.append(key)
    result = {
        "research":"11-market 3-calendar-month hypothesis tournament",
        "period":"2026-06-01 to 2026-08-31 inclusive",
        "completed_markets":sorted(combined),
        "missing_6_priority_markets":UNAVAILABLE,
        "models":{market:{
            "m5_bars":details["public_sample"]["m5_reference_bars"],
            "all_hypothetical_trades":details["all_paper_trades"],
            "method_counts":details["method_counts"]}
            for market,details in sorted(combined.items())},
        "modeled_trade_events_across_overlapping_methods":len(all_trades),
        "methods_by_market_side_tested":len(screening),
        "exploratory_month_screen_pass":sorted(qualified),
        "separately_verified_positive_trading_edges":0,
        "production_action":"WAIT",
        "live_execution_authorized":False,
        "orders_sent":0,
        "limitations":[
            "Reference M5 market prices with HYPOTHETICAL fixed spread, NOT true BID/ASK",
            "Historical periods already exposed to prior research; NOT independent OOS",
            "Candles do not resolve stop-versus-target hit ordering within one bar",
            "Modeled trades from different strategy hypotheses overlap",
            "No actual broker tick, swap, commission, margin or execution reconciliation",
            "Any exploratory screen pass is a research lead, never trade authorization",
        ],
    }
    output.mkdir(parents=True,exist_ok=True)
    (output/"consolidated.json").write_text(
        json.dumps(result,indent=2,ensure_ascii=False,allow_nan=False)+"\n",
        encoding="utf-8")
    lines=["# KATARINA 11-market strategy research — June-August 2026",
           "",
           "**Historical exploratory / assumed spread / NOT broker validated. Production WAIT.**",
           "",
           "| Instrument | M5 bars | Modeled trades | Mean R | Profit Factor |",
           "|---|---:|---:|---:|---:|"]
    for market,details in sorted(combined.items()):
        stat=details["all_paper_trades"]
        lines.append("| {} | {} | {} | {} | {} |".format(
            market, details["public_sample"]["m5_reference_bars"],
            stat["n"], stat["avg_r"], stat["profit_factor"]))
    lines.extend(["",
                  "### Screening status",
                  f"- Candidate method/side/market groups evaluated: {len(screening)}",
                  f"- Groups passing exploratory month-screen: {len(qualified)}",
                  "- A pass is not evidence of profitable executable trading.",
                  "- Missing public priority-market data: "+", ".join(UNAVAILABLE),
                  "- Different strategies can hold hypothetical positions concurrently;"
                  " total modeled return is not an investable portfolio return.",
                  "",
                  "### Exploratory leads (no promotion)",
                 ])
    lines.extend(["- "+key for key in qualified] or ["- None met the predefined monthly screen"])
    (output/"SUMMARY.md").write_text("\n".join(lines)+"\n",encoding="utf-8")
    print("CONSOLIDATED_TOURNAMENT", json.dumps({
        "markets":len(combined),"modeled_events":len(all_trades),
        "screens":len(screening),"exploratory_passes":len(qualified),
        "production":"WAIT","orders_sent":0},ensure_ascii=False),flush=True)
    return result


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--input",type=Path,default=Path("artifacts/public_tournament_download"))
    ap.add_argument("--output",type=Path,default=Path("artifacts/consolidated_tournament"))
    args=ap.parse_args()
    aggregate_reports(args.input,args.output)


if __name__=="__main__":
    main()
