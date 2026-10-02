import unittest

from katarina.contracts.runtime import EventEnvelope, MessagePriority, RuntimeMode
from katarina.core.component import (
    ComponentGraphError,
    ComponentPhase,
    resolve_component_order,
)
from katarina.core.lifecycle import LifecycleError, LifecycleMachine, LifecycleState
from katarina.core.message_bus import EventBus
from katarina.core.orchestrator import (
    KatarinaOrchestrator,
    OrchestratorConfig,
    OrchestratorFault,
)
from katarina.core.queue import CriticalIngressOverflow, IngressQueue
from katarina.core.readiness import ReadinessGate, ReadinessSignal


class _Component:
    def __init__(
        self,
        name,
        phase=ComponentPhase.RUNTIME,
        deps=(),
        log=None,
        fail_start=False,
    ):
        self.name = name
        self.phase = phase
        self.dependencies = tuple(deps)
        self.log = log if log is not None else []
        self.fail_start = fail_start

    async def initialize(self):
        self.log.append(f"init:{self.name}")

    async def start(self):
        self.log.append(f"start:{self.name}")
        if self.fail_start:
            raise RuntimeError("boom")

    async def stop(self):
        self.log.append(f"stop:{self.name}")

    async def dispose(self):
        self.log.append(f"dispose:{self.name}")


class LifecycleTests(unittest.TestCase):
    def test_valid_path(self):
        machine = LifecycleMachine()
        for state in (
            LifecycleState.INITIALIZING,
            LifecycleState.STARTING,
            LifecycleState.RECOVERING,
            LifecycleState.READY,
            LifecycleState.STARTING,
            LifecycleState.RUNNING,
            LifecycleState.STOPPING,
            LifecycleState.STOPPED,
            LifecycleState.DISPOSING,
            LifecycleState.DISPOSED,
        ):
            machine.transition(state)
        self.assertEqual(machine.state, LifecycleState.DISPOSED)

    def test_invalid_transition_rejected(self):
        with self.assertRaises(LifecycleError):
            LifecycleMachine().transition(LifecycleState.RUNNING)


class ComponentGraphTests(unittest.TestCase):
    def test_dependency_order(self):
        a = _Component("a", ComponentPhase.BOOTSTRAP)
        b = _Component("b", deps=("a",))
        c = _Component("c", deps=("b",))
        self.assertEqual(
            [x.name for x in resolve_component_order([c, b, a])],
            ["a", "b", "c"],
        )

    def test_cycle_rejected(self):
        a = _Component("a", deps=("b",))
        b = _Component("b", deps=("a",))
        with self.assertRaises(ComponentGraphError):
            resolve_component_order([a, b])

    def test_bootstrap_cannot_depend_on_runtime(self):
        runtime = _Component("runtime", ComponentPhase.RUNTIME)
        boot = _Component(
            "boot",
            ComponentPhase.BOOTSTRAP,
            deps=("runtime",),
        )
        with self.assertRaises(ComponentGraphError):
            resolve_component_order([runtime, boot])


class QueueTests(unittest.TestCase):
    def test_noncritical_full_queue_is_observable_rejection(self):
        queue = IngressQueue(1)
        self.assertTrue(
            queue.put_nowait(
                EventEnvelope("tick", 1, MessagePriority.MARKET)
            )
        )
        self.assertFalse(
            queue.put_nowait(
                EventEnvelope("tick", 2, MessagePriority.MARKET)
            )
        )

    def test_critical_full_queue_raises(self):
        queue = IngressQueue(1)
        queue.put_nowait(
            EventEnvelope("tick", 1, MessagePriority.MARKET)
        )
        with self.assertRaises(CriticalIngressOverflow):
            queue.put_nowait(
                EventEnvelope("trade", 2, MessagePriority.CRITICAL)
            )


class ReadinessTests(unittest.TestCase):
    def test_live_requires_bootstrap_and_explicit_execution_readiness(self):
        gate = ReadinessGate(RuntimeMode.LIVE)
        bootstrap = (
            ReadinessSignal.TRANSPORT,
            ReadinessSignal.PROTOCOL,
            ReadinessSignal.IDENTITY,
            ReadinessSignal.SNAPSHOT,
            ReadinessSignal.JOURNAL,
            ReadinessSignal.EVENT_CURSOR,
            ReadinessSignal.RECONCILED,
        )
        for signal in bootstrap:
            gate.set(signal, True)
        self.assertTrue(gate.core_ready)
        self.assertFalse(gate.live_execution_ready)

        for signal in (
            ReadinessSignal.DATA_FRESH,
            ReadinessSignal.HEALTH,
            ReadinessSignal.RISK,
            ReadinessSignal.EXECUTION_ARMED,
        ):
            gate.set(signal, True)
        self.assertTrue(gate.live_execution_ready)

        gate.reset_live_arming()
        self.assertFalse(gate.live_execution_ready)

    def test_research_has_no_transport_bootstrap_requirement(self):
        gate = ReadinessGate(RuntimeMode.RESEARCH)
        self.assertTrue(gate.core_ready)
        self.assertFalse(gate.live_execution_ready)


class EventBusTests(unittest.IsolatedAsyncioTestCase):
    async def test_handlers_are_serial_and_emitted_children_are_returned(self):
        bus = EventBus()
        seen = []

        def first(event):
            seen.append("first")
            return EventEnvelope("child", 1)

        async def second(event):
            seen.append("second")

        bus.subscribe("root", first)
        bus.subscribe("root", second)

        children = await bus.dispatch(
            EventEnvelope("root", None)
        )
        self.assertEqual(seen, ["first", "second"])
        self.assertEqual(
            [event.topic for event in children],
            ["child"],
        )


class OrchestratorTests(unittest.IsolatedAsyncioTestCase):
    async def test_bootstrap_activate_and_reverse_shutdown(self):
        log = []
        core = KatarinaOrchestrator(
            OrchestratorConfig(
                RuntimeMode.LIVE,
                ingress_capacity=16,
            )
        )
        core.register_component(
            _Component(
                "transport",
                ComponentPhase.BOOTSTRAP,
                log=log,
            )
        )
        core.register_component(
            _Component(
                "decision",
                ComponentPhase.RUNTIME,
                deps=("transport",),
                log=log,
            )
        )

        await core.bootstrap()
        self.assertEqual(
            core.lifecycle.state,
            LifecycleState.RECOVERING,
        )

        for signal in (
            ReadinessSignal.TRANSPORT,
            ReadinessSignal.PROTOCOL,
            ReadinessSignal.IDENTITY,
            ReadinessSignal.SNAPSHOT,
            ReadinessSignal.JOURNAL,
            ReadinessSignal.EVENT_CURSOR,
            ReadinessSignal.RECONCILED,
        ):
            core.set_readiness(signal, True)

        self.assertEqual(
            core.lifecycle.state,
            LifecycleState.READY,
        )

        await core.activate()
        self.assertEqual(
            core.lifecycle.state,
            LifecycleState.RUNNING,
        )
        self.assertFalse(core.new_live_risk_allowed)

        for signal in (
            ReadinessSignal.DATA_FRESH,
            ReadinessSignal.HEALTH,
            ReadinessSignal.RISK,
            ReadinessSignal.EXECUTION_ARMED,
        ):
            core.set_readiness(signal, True)
        self.assertTrue(core.new_live_risk_allowed)

        await core.stop()
        self.assertEqual(
            log[-2:],
            ["stop:decision", "stop:transport"],
        )
        await core.dispose()
        self.assertEqual(
            log[-2:],
            ["dispose:decision", "dispose:transport"],
        )

    async def test_child_event_is_not_recursively_dispatched(self):
        core = KatarinaOrchestrator(
            OrchestratorConfig(
                RuntimeMode.RESEARCH,
                ingress_capacity=16,
            )
        )
        order = []

        def first(event):
            order.append("first-root")
            return EventEnvelope("child", None)

        def second(event):
            order.append("second-root")

        def child(event):
            order.append("child")

        core.bus.subscribe("root", first)
        core.bus.subscribe("root", second)
        core.bus.subscribe("child", child)

        await core.bootstrap()
        await core.activate()
        await core.submit(EventEnvelope("root", None))
        await core.run_until_idle()

        self.assertEqual(
            order,
            ["first-root", "second-root", "child"],
        )

    async def test_runtime_start_failure_faults_and_cleans_started_components(self):
        log = []
        core = KatarinaOrchestrator(
            OrchestratorConfig(
                RuntimeMode.RESEARCH,
                ingress_capacity=16,
            )
        )
        core.register_component(
            _Component(
                "transport",
                ComponentPhase.BOOTSTRAP,
                log=log,
            )
        )
        core.register_component(
            _Component(
                "runtime",
                ComponentPhase.RUNTIME,
                deps=("transport",),
                log=log,
                fail_start=True,
            )
        )

        await core.bootstrap()
        with self.assertRaises(OrchestratorFault):
            await core.activate()

        self.assertEqual(
            core.lifecycle.state,
            LifecycleState.FAULTED,
        )
        self.assertIn("stop:runtime", log)
        self.assertIn("stop:transport", log)

    async def test_readiness_loss_closes_live_risk_without_killing_core(self):
        core = KatarinaOrchestrator(
            OrchestratorConfig(
                RuntimeMode.LIVE,
                ingress_capacity=8,
            )
        )
        await core.bootstrap()

        for signal in (
            ReadinessSignal.TRANSPORT,
            ReadinessSignal.PROTOCOL,
            ReadinessSignal.IDENTITY,
            ReadinessSignal.SNAPSHOT,
            ReadinessSignal.JOURNAL,
            ReadinessSignal.EVENT_CURSOR,
            ReadinessSignal.RECONCILED,
        ):
            core.set_readiness(signal, True)
        await core.activate()

        for signal in (
            ReadinessSignal.DATA_FRESH,
            ReadinessSignal.HEALTH,
            ReadinessSignal.RISK,
            ReadinessSignal.EXECUTION_ARMED,
        ):
            core.set_readiness(signal, True)

        self.assertTrue(core.new_live_risk_allowed)
        core.set_readiness(
            ReadinessSignal.RECONCILED,
            False,
        )
        self.assertEqual(
            core.lifecycle.state,
            LifecycleState.RUNNING,
        )
        self.assertFalse(core.new_live_risk_allowed)

    async def test_critical_overflow_faults_fail_closed(self):
        core = KatarinaOrchestrator(
            OrchestratorConfig(
                RuntimeMode.RESEARCH,
                ingress_capacity=1,
            )
        )
        await core.bootstrap()
        await core.activate()
        await core.submit(
            EventEnvelope(
                "market",
                1,
                MessagePriority.MARKET,
            )
        )

        with self.assertRaises(OrchestratorFault):
            await core.submit(
                EventEnvelope(
                    "trade",
                    2,
                    MessagePriority.CRITICAL,
                )
            )

        self.assertEqual(
            core.lifecycle.state,
            LifecycleState.FAULTED,
        )


if __name__ == "__main__":
    unittest.main()
