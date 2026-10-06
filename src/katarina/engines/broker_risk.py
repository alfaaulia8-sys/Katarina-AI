from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
import json
from math import isfinite
from typing import Any, Mapping


@dataclass(frozen=True, slots=True)
class BrokerRiskRequest:
    request_id: str
    exposure_id: str
    side: str
    instrument_id: int
    spec_revision: int
    volume: float
    current_price: float
    stop_loss: float


@dataclass(frozen=True, slots=True)
class BrokerRiskEvidence:
    exposure_id: str
    loss_native: float
    valid: bool
    reason: str


class BrokerNativeRiskBook:
    """Correlates KAT1 BROKER_CALC reports with exposure ids."""

    def __init__(self):
        self._bindings: dict[str,str]={}
        self._loss: dict[str,float]={}

    @staticmethod
    def deterministic_request_id(exposure_id:str,side:str,volume:float,current_price:float,stop_loss:float)->str:
        raw=json.dumps([exposure_id,side,volume,current_price,stop_loss],separators=(",",":"))
        return sha256(raw.encode()).hexdigest()[:32]

    def register(self,request:BrokerRiskRequest)->None:
        if not request.request_id or not request.exposure_id: raise ValueError("binding")
        self._bindings[request.request_id]=request.exposure_id

    def observe_report(self,payload:Mapping[str,Any],*,money_scale:int)->BrokerRiskEvidence:
        request_id=str(payload.get("calc_request_id",""))
        exposure=self._bindings.get(request_id)
        if exposure is None:
            return BrokerRiskEvidence("",0.0,False,"unknown_calc_request")
        if int(payload.get("profit_valid",0)) != 1:
            return BrokerRiskEvidence(exposure,0.0,False,"profit_calc_invalid")
        units=int(payload.get("profit_units",0))
        profit=float(units)*(10.0**(-int(money_scale)))
        if not isfinite(profit):
            return BrokerRiskEvidence(exposure,0.0,False,"non_finite_profit")
        loss=max(0.0,-profit)
        self._loss[exposure]=loss
        return BrokerRiskEvidence(exposure,loss,True,"broker_ordercalcprofit")

    def loss_for(self,exposure_id:str)->float|None:
        return self._loss.get(exposure_id)

    def snapshot_state(self)->dict[str,Any]:
        return {"bindings":dict(self._bindings),"loss":dict(self._loss)}

    def restore_state(self,state:Mapping[str,Any])->None:
        self._bindings={str(k):str(v) for k,v in state.get("bindings",{}).items()}
        self._loss={str(k):float(v) for k,v in state.get("loss",{}).items()}
