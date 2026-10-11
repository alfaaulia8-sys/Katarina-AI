"""Readable audit summary of the frozen cost sensitivity report."""
import argparse
import json
from pathlib import Path

def show(data):
    for family in ("M1_M5","M5_M15"):
        experiment=data["experiments"][family]
        print("\n"+family+" original technical proposals: "+str(experiment["quoted_proposals"]))
        for candidate in experiment["grid"]:
            if candidate["threshold_spread_div_ATR"] not in (0.15,0.25,0.35,0.50,0.75,1.0):
                continue
            print("Threshold",candidate["threshold_spread_div_ATR"],"n",candidate["samples_after_cost_gate"])
            for side in ("BUY","SELL"):
                now=candidate["by_side"][side]["0.0"]
                with2=candidate["by_side"][side]["2.0"]
                with5=candidate["by_side"][side]["5.0"]
                print("  ",side,"n",now["n"],"days",now["distinct_utc_days"],
                    "mean",now["mean_net_quote_bps"],
                    "mean_plus2",with2["mean_net_quote_bps"],
                    "mean_plus5",with5["mean_net_quote_bps"],
                    "positive",now["positive_fraction"],
                    "quoted_roundtrip_spread_bps",now["observed_spread_cost_bps_mean"])
            print("  per_window",[(w["start"],w["measured"],
                w["mean_bps"]) for w in candidate["by_window"]])
            qualifying=[r for r in candidate["symbol_sides_with_30_samples"]
                        if r["descriptive_coverage_met"]]
            print("  symbol_sides_cover_30trades_10days",[(r["symbol"],r["side"],r["n"]) for r in qualifying])
def main():
    p=argparse.ArgumentParser()
    p.add_argument("report")
    args=p.parse_args()
    show(json.loads(Path(args.report).read_text(encoding="utf-8")))
if __name__=="__main__":
    main()
