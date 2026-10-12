"""Consolidated multi-market proof-gate tests. No network or VPS writes."""
from __future__ import annotations
import json
import tempfile
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"scripts"/"research"))
from summarize_public_tournament import aggregate_reports, REQUIRED


def mock_summary(symbols,*,orders=0):
    return {
        "orders_sent":orders,"production":"WAIT",
        "actual_bid_ask_verified":False,"independent_holdout":False,
        "symbols":{symbol:{
            "public_sample":{
                "actual_historical_bid_ask_available":False,
                "m5_reference_bars":12000},
            "scanner":{"status":"OK"},
            "all_paper_trades":{"n":0,"avg_r":None,"profit_factor":None},
            "method_counts":{}}
            for symbol in symbols},
        "monthly_strategy_screen":{}}


class PublicTournamentSummaryTests(unittest.TestCase):
    def test_complete_scope_produces_nonpromotion_report(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)/"groups";root.mkdir()
            for index,symbol in enumerate(sorted(REQUIRED)):
                group=root/f"part{index}";group.mkdir()
                (group/"summary.json").write_text(
                    json.dumps(mock_summary([symbol])),encoding="utf-8")
            output=Path(d)/"combined"
            report=aggregate_reports(root,output)
            self.assertEqual(len(report["completed_markets"]),11)
            self.assertEqual(report["separately_verified_positive_trading_edges"],0)
            self.assertFalse(report["live_execution_authorized"])
            self.assertEqual(report["production_action"],"WAIT")
            self.assertTrue((output/"SUMMARY.md").is_file())

    def test_missing_market_fails_closed(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)/"groups";group=root/"single";group.mkdir(parents=True)
            (group/"summary.json").write_text(
                json.dumps(mock_summary(["EURUSD"])),encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError,"incomplete_market_scope"):
                aggregate_reports(root,Path(d)/"out")

    def test_duplicate_market_fails_closed(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)/"groups"
            for i in range(2):
                group=root/f"part{i}";group.mkdir(parents=True)
                (group/"summary.json").write_text(
                    json.dumps(mock_summary(["EURUSD"])),encoding="utf-8")
            with self.assertRaisesRegex(ValueError,"duplicate_or_unexpected_market"):
                aggregate_reports(root,Path(d)/"out")

    def test_any_order_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)/"groups";group=root/"bad";group.mkdir(parents=True)
            (group/"summary.json").write_text(
                json.dumps(mock_summary(["EURUSD"],orders=1)),encoding="utf-8")
            with self.assertRaisesRegex(ValueError,"unsafe_public_research_report"):
                aggregate_reports(root,Path(d)/"out")


if __name__=="__main__":
    unittest.main()
