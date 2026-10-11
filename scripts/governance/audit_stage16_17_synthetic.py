#!/usr/bin/env python3
"""Synthetic Stage 16/17 evidence only; no broker access, no trade send."""
from pathlib import Path
import argparse
import json

from katarina.engines.broker_aware_sizing import (
    AccountFacts, BrokerFacts, TradingCosts, ResearchCostMarginGate)
from katarina.engines.risk import RiskGovernor


def audit(repo):
    gate = ResearchCostMarginGate(
        RiskGovernor.from_config(repo / "config/risk_governor_v2.json"))
    spec = BrokerFacts("USD", 1, 100, .01, 50, .01, 1000, verified=True)
    costs = TradingCosts(.02, .03, .5, verified=True)
    rows = []
    for balance in (100, 1000, 10000):
        account = AccountFacts("USD", balance, balance, balance, balance,
                               uncertainty=.1, expected_rr=2, verified=True)
        result = gate.qualify(account=account, broker=spec, costs=costs,
                              side="BUY", entry=4200, stop=4190)
        rows.append({
            "capital_usd_synthetic": balance,
            "research_eligible": result.eligible_for_research,
            "reason": result.reason,
            "mock_volume": result.volume,
            "risk_fraction": result.fraction,
            "budget_native": result.budget_native,
            "worst_case_loss_native": result.buffered_loss_native,
            "margin_native": result.margin_native,
            "live_execution_authorized": result.live_execution_authorized,
        })
    assert not rows[0]["research_eligible"]
    assert all(x["research_eligible"] for x in rows[1:])
    assert all(not x["live_execution_authorized"] for x in rows)
    return {
        "result": "PASS_STAGE16_17_SYNTHETIC_COST_MARGIN",
        "source": "SYNTHETIC_NOT_BROKER_VERIFIED",
        "real_trading_data_verified": False,
        "stage14_15_policy_finalized": False,
        "stage16_17_policy_finalized": False,
        "windows_stage35_36_38_validated": False,
        "live_execution_enabled": False,
        "samples": rows,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--output", type=Path,
                        default=Path("build/validation/stage16-17-synthetic.json"))
    args = parser.parse_args()
    report = audit(args.repo_root.resolve())
    output = args.output if args.output.is_absolute() else args.repo_root / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(report["result"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
