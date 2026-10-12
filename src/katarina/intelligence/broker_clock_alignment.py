"""Research-only detection of MT5 tick clock displacement from UTC.

MT5 documentation and broker implementations may disagree on timestamps.
This detects a CURRENT consistent integer-hour displacement from several
independent fresh quotes; it does NOT establish historical DST or certify
latency. No trading is permitted based on this detection.
"""
from __future__ import annotations
from collections import Counter
from dataclasses import dataclass
from math import isfinite
from typing import Mapping

@dataclass(frozen=True)
class ClockFinding:
    observed_hours_shift: int | None
    samples_considered: int
    confirming_symbols: int
    confidence_fraction: float
    suitable_for_readonly_snapshot: bool
    historical_dst_verified: bool = False
    live_execution_authorized: bool = False

def infer_clock_shift(tick_epoch_by_symbol:Mapping[str,int],
                      observed_utc_epoch:float,
                      *,min_symbols:int=3,majority_fraction:float=.70) -> ClockFinding:
    if not isfinite(observed_utc_epoch) or min_symbols<3:
        raise ValueError("invalid_clock_inputs")
    considered=0;votes=Counter()
    for sym,ts in tick_epoch_by_symbol.items():
        if not sym or not isinstance(ts,int) or ts<=0:continue
        considered+=1
        delta=ts-observed_utc_epoch
        hours=int(round(delta/3600))
        if not (-12<=hours<=14):continue
        age=observed_utc_epoch-(ts-hours*3600)
        if -15<=age<=180:
            votes[hours]+=1
    if considered<min_symbols or not votes:
        return ClockFinding(None,considered,0,0.,False)
    hours,count=votes.most_common(1)[0]
    frac=count/considered
    valid=count>=min_symbols and frac>=majority_fraction
    return ClockFinding(hours if valid else None,considered,count,
                        round(frac,4),valid)