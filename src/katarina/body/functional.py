from __future__ import annotations

import hashlib
import random
from dataclasses import dataclass
from enum import Enum
from typing import Any, Mapping, Sequence

from katarina.body.component import PassiveStageComponent
from katarina.persistence.canonical import canonical_json_bytes


PPM = 1_000_000


@dataclass(frozen=True, slots=True)
class MarketFeatureSnapshot:
    instrument_id: int
    observed_at_ns: int
    features: Mapping[str, int]
    source: str = "validated"

    def __post_init__(self) -> None:
        if self.instrument_id <= 0:
            raise ValueError("instrument_id must be positive")
        if self.observed_at_ns < 0:
            raise ValueError("observed_at_ns must be non-negative")
        if not self.source:
            raise ValueError("source must be non-empty")
        if any(not isinstance(v, int) for v in self.features.values()):
            raise TypeError("market features must use deterministic integer units")


class MarketIntelligenceBody(PassiveStageComponent):
    def __init__(self) -> None:
        super().__init__()
        self._latest: dict[int, MarketFeatureSnapshot] = {}

    def observe(self, snapshot: MarketFeatureSnapshot) -> None:
        previous = self._latest.get(snapshot.instrument_id)
        if previous and snapshot.observed_at_ns < previous.observed_at_ns:
            raise ValueError("market feature time cannot move backwards")
        self._latest[snapshot.instrument_id] = snapshot

    def latest(self, instrument_id: int) -> MarketFeatureSnapshot | None:
        return self._latest.get(instrument_id)


@dataclass(frozen=True, slots=True)
class TimeframeObservation:
    instrument_id: int
    timeframe_seconds: int
    open_time_ns: int
    values: Mapping[str, int]

    def __post_init__(self) -> None:
        if self.instrument_id <= 0:
            raise ValueError("instrument_id must be positive")
        if self.timeframe_seconds <= 0:
            raise ValueError("timeframe_seconds must be positive")
        if self.open_time_ns < 0:
            raise ValueError("open_time_ns must be non-negative")
        if any(not isinstance(v, int) for v in self.values.values()):
            raise TypeError("timeframe values must be integer units")


class MultiTimeframeBody(PassiveStageComponent):
    def __init__(self) -> None:
        super().__init__()
        self._latest: dict[tuple[int, int], TimeframeObservation] = {}

    @staticmethod
    def bucket_open_ns(timestamp_ns: int, timeframe_seconds: int) -> int:
        if timestamp_ns < 0 or timeframe_seconds <= 0:
            raise ValueError("invalid timestamp/timeframe")
        width = timeframe_seconds * 1_000_000_000
        return timestamp_ns - (timestamp_ns % width)

    def observe(self, observation: TimeframeObservation) -> None:
        key = (observation.instrument_id, observation.timeframe_seconds)
        previous = self._latest.get(key)
        if previous and observation.open_time_ns < previous.open_time_ns:
            raise ValueError("timeframe observation cannot move backwards")
        self._latest[key] = observation

    def latest(
        self, instrument_id: int, timeframe_seconds: int
    ) -> TimeframeObservation | None:
        return self._latest.get((instrument_id, timeframe_seconds))


@dataclass(frozen=True, slots=True)
class RegimeEvidence:
    instrument_id: int
    observed_at_ns: int
    trend_score_ppm: int
    volatility_score_ppm: int
    liquidity_score_ppm: int

    def __post_init__(self) -> None:
        for value in (
            self.trend_score_ppm,
            self.volatility_score_ppm,
            self.liquidity_score_ppm,
        ):
            if value < -PPM or value > PPM:
                raise ValueError("regime evidence score outside ppm bounds")


class MarketRegimeBody(PassiveStageComponent):
    def __init__(self) -> None:
        super().__init__()
        self._latest: dict[int, RegimeEvidence] = {}

    def observe(self, evidence: RegimeEvidence) -> str:
        self._latest[evidence.instrument_id] = evidence
        return "UNCLASSIFIED_POLICY_PENDING"

    def latest(self, instrument_id: int) -> RegimeEvidence | None:
        return self._latest.get(instrument_id)


class XAUUSDSpecialistBody(PassiveStageComponent):
    def analyze(self, _: Mapping[str, Any]) -> Mapping[str, Any]:
        return {
            "instrument": "XAUUSD",
            "signal": "NO_SIGNAL",
            "reason": "final XAUUSD strategy policy is pending",
            "live_execution_authority": False,
        }


class DecisionBody(PassiveStageComponent):
    def decide(self, _: Mapping[str, Any]) -> Mapping[str, Any]:
        return {
            "decision": "NO_TRADE",
            "reason": "strategy policy is unfinalized",
            "live_execution_authority": False,
        }


class RiskGovernorBody(PassiveStageComponent):
    def authorize(self, _: Mapping[str, Any]) -> Mapping[str, Any]:
        return {
            "approved": False,
            "reason": "risk policy is unfinalized",
            "live_risk_ready": False,
        }


class PositionSizingBody(PassiveStageComponent):
    def size(self, _: Mapping[str, Any]) -> Mapping[str, Any]:
        return {
            "quantity_units": 0,
            "approved": False,
            "reason": "risk policy is unfinalized",
        }


@dataclass(frozen=True, slots=True)
class ExecutionIntent:
    intent_id: str
    instrument_id: int
    side: str
    quantity_units: int

    def __post_init__(self) -> None:
        if not self.intent_id:
            raise ValueError("intent_id must be non-empty")
        if self.instrument_id <= 0:
            raise ValueError("instrument_id must be positive")
        if self.side not in {"BUY", "SELL"}:
            raise ValueError("side must be BUY or SELL")
        if self.quantity_units <= 0:
            raise ValueError("quantity_units must be positive")


class ExecutionBody(PassiveStageComponent):
    def __init__(self) -> None:
        super().__init__()
        self._observed_intents: dict[str, ExecutionIntent] = {}

    def stage_intent(self, intent: ExecutionIntent) -> Mapping[str, Any]:
        self._observed_intents[intent.intent_id] = intent
        return {
            "accepted_for_live_execution": False,
            "intent_id": intent.intent_id,
            "reason": "body execution path exists but broker mutation is disabled",
        }


@dataclass(frozen=True, slots=True)
class PositionObservation:
    position_id: str
    instrument_id: int
    side: str
    quantity_units: int
    price_units: int
    revision: int

    def __post_init__(self) -> None:
        if not self.position_id:
            raise ValueError("position_id must be non-empty")
        if self.revision < 0:
            raise ValueError("revision must be non-negative")


class PositionManagerBody(PassiveStageComponent):
    def __init__(self) -> None:
        super().__init__()
        self._positions: dict[str, PositionObservation] = {}

    def observe(self, position: PositionObservation) -> None:
        old = self._positions.get(position.position_id)
        if old and position.revision < old.revision:
            raise ValueError("position revision cannot decrease")
        self._positions[position.position_id] = position

    def snapshot(self) -> tuple[PositionObservation, ...]:
        return tuple(
            self._positions[key]
            for key in sorted(self._positions)
        )


@dataclass(frozen=True, slots=True)
class TradeOutcome:
    trade_id: str
    pnl_units: int


@dataclass(frozen=True, slots=True)
class EvaluationSummary:
    trade_count: int
    wins: int
    losses: int
    flat: int
    total_pnl_units: int
    max_drawdown_units: int


class TradeEvaluationBody(PassiveStageComponent):
    @staticmethod
    def summarize(outcomes: Sequence[TradeOutcome]) -> EvaluationSummary:
        equity = 0
        peak = 0
        max_drawdown = 0
        wins = losses = flat = 0
        for outcome in outcomes:
            equity += outcome.pnl_units
            peak = max(peak, equity)
            max_drawdown = max(max_drawdown, peak - equity)
            if outcome.pnl_units > 0:
                wins += 1
            elif outcome.pnl_units < 0:
                losses += 1
            else:
                flat += 1
        return EvaluationSummary(
            trade_count=len(outcomes),
            wins=wins,
            losses=losses,
            flat=flat,
            total_pnl_units=equity,
            max_drawdown_units=max_drawdown,
        )


@dataclass(frozen=True, slots=True)
class ExperimentSpec:
    experiment_id: str
    hypothesis: str
    parameters: Mapping[str, Any]


class ResearchBody(PassiveStageComponent):
    def __init__(self) -> None:
        super().__init__()
        self._experiments: dict[str, ExperimentSpec] = {}

    @staticmethod
    def deterministic_id(
        hypothesis: str,
        parameters: Mapping[str, Any],
    ) -> str:
        material = {
            "hypothesis": hypothesis,
            "parameters": dict(parameters),
        }
        return hashlib.sha256(canonical_json_bytes(material)).hexdigest()

    def register(
        self,
        hypothesis: str,
        parameters: Mapping[str, Any],
    ) -> ExperimentSpec:
        experiment_id = self.deterministic_id(hypothesis, parameters)
        spec = ExperimentSpec(
            experiment_id=experiment_id,
            hypothesis=hypothesis,
            parameters=dict(parameters),
        )
        self._experiments.setdefault(experiment_id, spec)
        return self._experiments[experiment_id]


@dataclass(frozen=True, slots=True)
class BacktestEvent:
    time_ns: int
    sequence: int
    payload: Mapping[str, Any]


class BacktestingBody(PassiveStageComponent):
    @staticmethod
    def normalize_events(
        events: Sequence[BacktestEvent],
    ) -> tuple[BacktestEvent, ...]:
        ordered = tuple(sorted(events, key=lambda x: (x.time_ns, x.sequence)))
        if len({(e.time_ns, e.sequence) for e in ordered}) != len(ordered):
            raise ValueError("duplicate backtest event time/sequence")
        return ordered


@dataclass(frozen=True, slots=True)
class WalkForwardWindow:
    train_start: int
    train_end: int
    test_start: int
    test_end: int


class WalkForwardBody(PassiveStageComponent):
    @staticmethod
    def windows(
        total_samples: int,
        *,
        train_samples: int,
        test_samples: int,
        step_samples: int | None = None,
    ) -> tuple[WalkForwardWindow, ...]:
        if min(total_samples, train_samples, test_samples) <= 0:
            raise ValueError("sample counts must be positive")
        step = test_samples if step_samples is None else step_samples
        if step <= 0:
            raise ValueError("step_samples must be positive")
        out: list[WalkForwardWindow] = []
        start = 0
        while start + train_samples + test_samples <= total_samples:
            train_end = start + train_samples
            test_end = train_end + test_samples
            out.append(
                WalkForwardWindow(
                    train_start=start,
                    train_end=train_end,
                    test_start=train_end,
                    test_end=test_end,
                )
            )
            start += step
        return tuple(out)


@dataclass(frozen=True, slots=True)
class MonteCarloSummary:
    trials: int
    min_terminal_pnl_units: int
    max_terminal_pnl_units: int
    median_terminal_pnl_units: int


class MonteCarloBody(PassiveStageComponent):
    @staticmethod
    def bootstrap(
        pnl_units: Sequence[int],
        *,
        trials: int = 100,
        seed: int = 0,
    ) -> MonteCarloSummary:
        if not pnl_units:
            raise ValueError("pnl_units must be non-empty")
        if trials <= 0:
            raise ValueError("trials must be positive")
        rng = random.Random(seed)
        terminals = []
        n = len(pnl_units)
        for _ in range(trials):
            terminals.append(sum(rng.choice(pnl_units) for _ in range(n)))
        terminals.sort()
        return MonteCarloSummary(
            trials=trials,
            min_terminal_pnl_units=terminals[0],
            max_terminal_pnl_units=terminals[-1],
            median_terminal_pnl_units=terminals[len(terminals) // 2],
        )


@dataclass(frozen=True, slots=True)
class ShadowIntent:
    intent_id: str
    payload: Mapping[str, Any]


class ShadowKatarinaBody(PassiveStageComponent):
    def __init__(self) -> None:
        super().__init__()
        self._intents: list[ShadowIntent] = []

    def record(self, intent: ShadowIntent) -> Mapping[str, Any]:
        self._intents.append(intent)
        return {
            "shadow_only": True,
            "broker_mutation": False,
            "intent_id": intent.intent_id,
        }

    def intents(self) -> tuple[ShadowIntent, ...]:
        return tuple(self._intents)


@dataclass(frozen=True, slots=True)
class LearningObservation:
    observation_id: str
    features: Mapping[str, int]
    outcome_units: int


class LearningBody(PassiveStageComponent):
    def __init__(self) -> None:
        super().__init__()
        self._observations: dict[str, LearningObservation] = {}

    def observe(self, observation: LearningObservation) -> bool:
        if observation.observation_id in self._observations:
            return False
        self._observations[observation.observation_id] = observation
        return True

    def observations(self) -> tuple[LearningObservation, ...]:
        return tuple(self._observations.values())


@dataclass(frozen=True, slots=True)
class ModelArtifact:
    model_id: str
    version: str
    digest_sha256: str
    metrics: Mapping[str, int]

    def __post_init__(self) -> None:
        if len(self.digest_sha256) != 64:
            raise ValueError("model digest must be SHA-256 hex")


class MachineLearningBody(PassiveStageComponent):
    def __init__(self) -> None:
        super().__init__()
        self._models: dict[str, ModelArtifact] = {}

    def register(self, artifact: ModelArtifact) -> None:
        self._models[artifact.model_id] = artifact

    def get(self, model_id: str) -> ModelArtifact | None:
        return self._models.get(model_id)


class ModelPromotionBody(PassiveStageComponent):
    def __init__(self) -> None:
        super().__init__()
        self._champion: str | None = None
        self._history: list[str] = []

    @property
    def champion(self) -> str | None:
        return self._champion

    def promote(self, model_id: str, *, validated: bool) -> bool:
        if not validated:
            return False
        if self._champion is not None:
            self._history.append(self._champion)
        self._champion = model_id
        return True

    def rollback(self) -> str | None:
        if not self._history:
            return None
        self._champion = self._history.pop()
        return self._champion


@dataclass(frozen=True, slots=True)
class EconomicObservation:
    series_id: str
    observed_at_ns: int
    value_units: int
    revision: int = 0


class EconomicIntelligenceBody(PassiveStageComponent):
    def __init__(self) -> None:
        super().__init__()
        self._series: dict[str, EconomicObservation] = {}

    def observe(self, observation: EconomicObservation) -> None:
        old = self._series.get(observation.series_id)
        if old and observation.revision < old.revision:
            raise ValueError("economic revision cannot decrease")
        self._series[observation.series_id] = observation


@dataclass(frozen=True, slots=True)
class PortfolioAllocation:
    weights_ppm: Mapping[str, int]

    def __post_init__(self) -> None:
        if any(v < 0 or v > PPM for v in self.weights_ppm.values()):
            raise ValueError("portfolio weights outside ppm bounds")
        if sum(self.weights_ppm.values()) > PPM:
            raise ValueError("portfolio weights exceed 100 percent")


class PortfolioBody(PassiveStageComponent):
    def validate(self, allocation: PortfolioAllocation) -> PortfolioAllocation:
        return allocation


@dataclass(frozen=True, slots=True)
class ExposureSnapshot:
    gross_units: int
    net_units: int
    by_symbol_units: Mapping[str, int]


class GlobalExposureBody(PassiveStageComponent):
    @staticmethod
    def calculate(exposures: Mapping[str, int]) -> ExposureSnapshot:
        gross = sum(abs(v) for v in exposures.values())
        net = sum(exposures.values())
        return ExposureSnapshot(
            gross_units=gross,
            net_units=net,
            by_symbol_units=dict(exposures),
        )


class DashboardBody(PassiveStageComponent):
    @staticmethod
    def compose(*sections: Mapping[str, Any]) -> Mapping[str, Any]:
        merged: dict[str, Any] = {}
        for section in sections:
            for key, value in section.items():
                if key in merged:
                    raise ValueError(f"duplicate dashboard key: {key}")
                merged[key] = value
        return merged


@dataclass(frozen=True, slots=True)
class TestGate:
    name: str
    passed: bool


class AutomatedTestingBody(PassiveStageComponent):
    @staticmethod
    def all_pass(gates: Sequence[TestGate]) -> bool:
        return bool(gates) and all(gate.passed for gate in gates)


class ConstitutionGuardBody(PassiveStageComponent):
    @staticmethod
    def evaluate(proposal: Mapping[str, Any]) -> tuple[bool, tuple[str, ...]]:
        reasons: list[str] = []
        if proposal.get("live_execution_authority") is True:
            reasons.append("LIVE_EXECUTION_AUTHORITY_FORBIDDEN")
        if proposal.get("live_risk_ready") is True:
            reasons.append("LIVE_RISK_READY_FORBIDDEN")
        if proposal.get("bypass_risk_governor") is True:
            reasons.append("RISK_GOVERNOR_BYPASS_FORBIDDEN")
        if proposal.get("mt5_discretionary_decision") is True:
            reasons.append("MT5_DISCRETIONARY_DECISION_FORBIDDEN")
        return not reasons, tuple(reasons)


@dataclass(frozen=True, slots=True)
class MT5TesterJob:
    expert_path: str
    symbol: str
    timeframe: str
    from_date: str
    to_date: str
    model: str = "real_ticks"


class MT5StrategyTesterBody(PassiveStageComponent):
    @staticmethod
    def validate_job(job: MT5TesterJob) -> bool:
        return all(
            (
                bool(job.expert_path),
                bool(job.symbol),
                bool(job.timeframe),
                bool(job.from_date),
                bool(job.to_date),
                job.model in {"real_ticks", "every_tick", "ohlc_1m"},
            )
        )


@dataclass(frozen=True, slots=True)
class PaperFill:
    order_id: str
    price_units: int
    quantity_units: int
    side: str


class PaperTradingBody(PassiveStageComponent):
    def __init__(self) -> None:
        super().__init__()
        self._fills: list[PaperFill] = []

    def simulate_fill(self, fill: PaperFill) -> None:
        if fill.side not in {"BUY", "SELL"}:
            raise ValueError("paper side must be BUY or SELL")
        if fill.quantity_units <= 0:
            raise ValueError("paper quantity must be positive")
        self._fills.append(fill)

    def fills(self) -> tuple[PaperFill, ...]:
        return tuple(self._fills)


@dataclass(frozen=True, slots=True)
class StressScenario:
    name: str
    expected_fail_closed: bool


class StressTestBody(PassiveStageComponent):
    @staticmethod
    def evaluate(
        scenarios: Sequence[StressScenario],
        observed_fail_closed: Mapping[str, bool],
    ) -> bool:
        return bool(scenarios) and all(
            observed_fail_closed.get(s.name) is s.expected_fail_closed
            for s in scenarios
        )


class LiveMicroRiskBody(PassiveStageComponent):
    def validate(self, _: Mapping[str, Any]) -> Mapping[str, Any]:
        return {
            "approved": False,
            "reason": "final risk policy and governed live validation pending",
            "live_risk_ready": False,
            "live_execution_authority": False,
        }


class PerformanceMonitoringBody(PassiveStageComponent):
    def __init__(self) -> None:
        super().__init__()
        self._counters: dict[str, int] = {}
        self._gauges: dict[str, int] = {}

    def increment(self, name: str, amount: int = 1) -> None:
        if amount < 0:
            raise ValueError("counter increment must be non-negative")
        self._counters[name] = self._counters.get(name, 0) + amount

    def gauge(self, name: str, value: int) -> None:
        self._gauges[name] = value

    def snapshot(self) -> Mapping[str, Mapping[str, int]]:
        return {
            "counters": dict(self._counters),
            "gauges": dict(self._gauges),
        }


class EvolutionStatus(str, Enum):
    PROPOSED = "proposed"
    VALIDATED = "validated"
    REJECTED = "rejected"


@dataclass(frozen=True, slots=True)
class EvolutionProposal:
    proposal_id: str
    description: str
    status: EvolutionStatus = EvolutionStatus.PROPOSED


class ContinuousEvolutionBody(PassiveStageComponent):
    def __init__(self) -> None:
        super().__init__()
        self._proposals: dict[str, EvolutionProposal] = {}

    def propose(self, proposal_id: str, description: str) -> EvolutionProposal:
        if not proposal_id or not description:
            raise ValueError("proposal id and description are required")
        proposal = EvolutionProposal(proposal_id, description)
        self._proposals[proposal_id] = proposal
        return proposal

    def mark_validated(
        self,
        proposal_id: str,
        *,
        tests_passed: bool,
        constitution_passed: bool,
    ) -> EvolutionProposal:
        current = self._proposals[proposal_id]
        status = (
            EvolutionStatus.VALIDATED
            if tests_passed and constitution_passed
            else EvolutionStatus.REJECTED
        )
        updated = EvolutionProposal(
            proposal_id=current.proposal_id,
            description=current.description,
            status=status,
        )
        self._proposals[proposal_id] = updated
        return updated


__all__ = (
    "AutomatedTestingBody",
    "BacktestEvent",
    "BacktestingBody",
    "ConstitutionGuardBody",
    "ContinuousEvolutionBody",
    "DashboardBody",
    "DecisionBody",
    "EconomicIntelligenceBody",
    "EconomicObservation",
    "EvaluationSummary",
    "EvolutionProposal",
    "EvolutionStatus",
    "ExecutionBody",
    "ExecutionIntent",
    "ExperimentSpec",
    "ExposureSnapshot",
    "GlobalExposureBody",
    "LearningBody",
    "LearningObservation",
    "LiveMicroRiskBody",
    "MT5StrategyTesterBody",
    "MT5TesterJob",
    "MachineLearningBody",
    "MarketFeatureSnapshot",
    "MarketIntelligenceBody",
    "MarketRegimeBody",
    "ModelArtifact",
    "ModelPromotionBody",
    "MonteCarloBody",
    "MonteCarloSummary",
    "MultiTimeframeBody",
    "PPM",
    "PaperFill",
    "PaperTradingBody",
    "PerformanceMonitoringBody",
    "PortfolioAllocation",
    "PortfolioBody",
    "PositionManagerBody",
    "PositionObservation",
    "PositionSizingBody",
    "RegimeEvidence",
    "ResearchBody",
    "RiskGovernorBody",
    "ShadowIntent",
    "ShadowKatarinaBody",
    "StressScenario",
    "StressTestBody",
    "TestGate",
    "TimeframeObservation",
    "TradeEvaluationBody",
    "TradeOutcome",
    "WalkForwardBody",
    "WalkForwardWindow",
    "XAUUSDSpecialistBody",
)
