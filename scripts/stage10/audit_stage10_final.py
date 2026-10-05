from __future__ import annotations

import argparse
import json
import pathlib
import sys
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()

    root = args.repo_root.resolve()
    sys.path.insert(0, str(root / "src"))

    from katarina.contracts.runtime import EventEnvelope, MessagePriority
    from katarina.persistence import (
        DurableRecord,
        PersistenceBundle,
    )

    config_path = root / "config" / "database_memory_v1_draft.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))

    step_keys = (
        "01_define_durable_event_memory_boundaries",
        "02_append_only_records_deterministic_ids",
        "03_separate_operational_and_experience_memory",
        "04_idempotent_writes_restart_recovery",
        "05_schema_migrations_integrity_checks",
    )

    checks: dict[str, bool] = {
        "stage09_freeze_present": (
            root / "docs" / "reviews" / "STAGE_09_FREEZE_RECORD.md"
        ).is_file(),
        "step01_05_local_pass": all(
            config["steps"].get(key) == "PASS_LOCAL" for key in step_keys
        ),
        "live_risk_false_in_config": config.get("live_risk_ready") is False,
        "boundary_source_present": (
            root / "src" / "katarina" / "persistence" / "boundaries.py"
        ).is_file(),
        "journal_source_present": (
            root / "src" / "katarina" / "persistence" / "sqlite_journal.py"
        ).is_file(),
        "separate_stores_source_present": (
            root / "src" / "katarina" / "persistence" / "stores.py"
        ).is_file(),
        "recovery_source_present": (
            root / "src" / "katarina" / "persistence" / "recovery.py"
        ).is_file(),
        "migration_integrity_source_present": (
            root / "src" / "katarina" / "persistence" / "sqlite_common.py"
        ).is_file(),
        "github_prior_art_recorded": (
            root
            / "docs"
            / "research"
            / "STAGE10_STEP03_05_GITHUB_REFERENCES.md"
        ).is_file(),
    }

    with tempfile.TemporaryDirectory() as temp:
        with PersistenceBundle(temp) as bundle:
            journal_event = EventEnvelope(
                topic="risk.state",
                payload={"revision": 1, "blocked": True},
                priority=MessagePriority.RISK_STATE,
                sequence=1,
                source_time_ns=1000,
                trace_id="stage10-final",
                source="audit",
            )
            journal_record = DurableRecord.from_event(journal_event)

            first, inserted_first = bundle.journal.append_idempotent(
                journal_record,
                committed_at_ns=1100,
            )
            second, inserted_second = bundle.journal.append_idempotent(
                journal_record,
                committed_at_ns=1200,
            )

            experience_event = EventEnvelope(
                topic="experience.trade_episode",
                payload={"episode": 1, "outcome": "observed"},
                priority=MessagePriority.ADVISORY,
                sequence=1,
                source_time_ns=1300,
                trace_id="stage10-exp",
                source="audit",
            )
            experience_record = DurableRecord.from_event(experience_event)
            exp_first, exp_inserted_first = (
                bundle.experience.append_idempotent(
                    experience_record,
                    committed_at_ns=1400,
                )
            )
            exp_second, exp_inserted_second = (
                bundle.experience.append_idempotent(
                    experience_record,
                    committed_at_ns=1500,
                )
            )

            bundle.operational.put(
                "runtime",
                {"projection": "recovering"},
                source_journal_ordinal=first.ordinal,
                updated_at_ns=1600,
            )

            plan = bundle.recovery_plan()
            integrity = bundle.integrity_report()

            checks.update(
                {
                    "three_physical_store_paths": len(
                        {
                            bundle.journal_path.resolve(),
                            bundle.operational_path.resolve(),
                            bundle.experience_path.resolve(),
                        }
                    )
                    == 3,
                    "journal_first_inserted": inserted_first,
                    "journal_replay_idempotent": (
                        not inserted_second
                        and first.ordinal == second.ordinal
                        and first.committed_at_ns == second.committed_at_ns
                    ),
                    "experience_first_inserted": exp_inserted_first,
                    "experience_replay_idempotent": (
                        not exp_inserted_second
                        and exp_first.ordinal == exp_second.ordinal
                        and exp_first.committed_at_ns
                        == exp_second.committed_at_ns
                    ),
                    "recovery_snapshot_usable": plan.snapshot_usable,
                    "recovery_replay_cursor_valid": (
                        plan.replay_after_ordinal == first.ordinal
                        and plan.journal_tail_ordinal >= first.ordinal
                    ),
                    "recovery_live_risk_false": not plan.live_risk_ready,
                    "recovery_execution_authority_false": (
                        not plan.live_execution_authority
                    ),
                    "all_sqlite_integrity_pass": bool(
                        integrity["all_passed"]
                    ),
                }
            )

    persistence_source = "\n".join(
        p.read_text(encoding="utf-8")
        for p in (
            root / "src" / "katarina" / "persistence"
        ).glob("*.py")
    )
    checks["no_order_send_in_persistence"] = "OrderSend(" not in persistence_source
    checks["no_live_authority_literal_true"] = (
        "live_execution_authority=True" not in persistence_source
        and "live_risk_ready=True" not in persistence_source
    )

    passed = all(checks.values())
    evidence = {
        "schema_version": 1,
        "stage": "10",
        "proof_type": "KATARINA_STAGE10_LOCAL_FINAL_CLEARANCE",
        "checks": checks,
        "live_risk_ready": False,
        "live_execution_authority": False,
        "ready_for_stage11": passed,
        "governed_freeze": False,
        "status": (
            "LOCAL_FREEZE_CANDIDATE"
            if passed
            else "IMPLEMENTATION_ACTIVE"
        ),
        "result": (
            "PASS_STAGE10_LOCAL_FINAL_CLEARANCE"
            if passed
            else "FAIL_STAGE10_LOCAL_FINAL_CLEARANCE"
        ),
    }

    output = args.output
    if not output.is_absolute():
        output = root / output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(evidence, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(evidence, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
