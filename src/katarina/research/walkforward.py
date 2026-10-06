from __future__ import annotations
from dataclasses import dataclass
from typing import Sequence

@dataclass(frozen=True, slots=True)
class WalkForwardFold:
    train: tuple[float,...]
    test: tuple[float,...]
@dataclass(frozen=True, slots=True)
class WalkForwardResult:
    folds: tuple[WalkForwardFold,...]
    mean_test: float
    stability: float

class WalkForwardEngine:
    def split(self, values: Sequence[float], *, train_size: int, test_size: int) -> WalkForwardResult:
        if train_size<=0 or test_size<=0: raise ValueError("window")
        folds=[]; i=0; means=[]
        while i+train_size+test_size<=len(values):
            tr=tuple(values[i:i+train_size]); te=tuple(values[i+train_size:i+train_size+test_size])
            folds.append(WalkForwardFold(tr,te)); means.append(sum(te)/len(te)); i+=test_size
        mean=sum(means)/len(means) if means else 0.0
        stability=0.0 if not means else sum(1 for x in means if x>=0)/len(means)
        return WalkForwardResult(tuple(folds),mean,stability)
