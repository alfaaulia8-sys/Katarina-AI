"""Compact unranked read-only summaries of the fixed TP/SL tick-path grid."""
import argparse
import json
from pathlib import Path

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--report",required=True)
    p.add_argument("--spread-limit",type=float,default=.35)
    p.add_argument("--extra-bps",type=float,default=0.)
    a=p.parse_args()
    source=json.loads(Path(a.report).read_text(encoding="utf-8"))
    if source.get("model_promotion_allowed") is not False:
        raise ValueError("not_a_read_only_report")
    print("Family / Side / TP ATR / SL ATR / n valid / n missing / TP / SL / TIME / expectancy R / profit factor / coverage")
    for g in source["groups"]:
        if (g["spread_atr_limit"]!=a.spread_limit or
            g["extra_bps"]!=a.extra_bps):continue
        exits=g.get("exits",{})
        print("{} {} {:g} {:g} {} {} {} {} {} {} {} {}".format(
            g["family"],g["side"],g["tp_atr"],g["sl_atr"],
            g["n_closed"],g["n_candidates"]-g["n_closed"],
            exits.get("TP",0),exits.get("SL",0),exits.get("TIME",0),
            "NA" if g["expectancy_r"] is None else round(g["expectancy_r"],3),
            "NA" if g["profit_factor"] is None else round(g["profit_factor"],3),
            "NA" if "outcome_coverage_fraction" not in g else round(g["outcome_coverage_fraction"],3)))
    print("All results descriptive only. No live permission, no broker commission calibration.")
if __name__=="__main__":
    main()
