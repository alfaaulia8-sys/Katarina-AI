"""Bounded Indonesian task evaluation; preparation never calls a provider."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import secrets
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'src'))
sys.path.insert(0, str(ROOT))
from scripts.pc.run_assistant import assistant_runtime
from katarina.adapters.dialog_model import JSONDialogModel, ModelConfig


def prepare_cases():
    a, b = secrets.randbelow(800)+100, secrets.randbelow(800)+100
    marker = secrets.token_hex(12)
    return dict(a=a, b=b, expected_sum=str(a+b), marker=marker,
                file_text='Kode pengujian rahasia buatan: '+marker)


def evaluate(model, root, *, cases=None):
    """Generated facts only; no production state, broker, HTTPS sources or order tools."""
    cases = cases or prepare_cases()
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    rows = []
    for mode in ('fast', 'deep'):
        workspace = root/mode/'workspace'
        workspace.mkdir(parents=True)
        (workspace/'facts.txt').write_text(cases['file_text'], encoding='utf-8')
        state = root/mode/'brain'
        state.mkdir()
        with assistant_runtime(state, model, workspace=workspace) as turn:
            tasks = [
                ('arithmetic', f"Hitung {cases['a']} + {cases['b']}. Balas angka hasil saja.", cases['expected_sum']),
                ('grounded_file', 'Baca facts.txt dengan alat read_file. Balas kode pengujian saja.', cases['marker']),
                ('remember', 'Ingat kode sesi buatan berikut: '+cases['marker']+'. Balas kode itu saja.', cases['marker']),
            ]
            for name, prompt, expected in tasks:
                result = turn(prompt, session_id='evaluation', mode=mode)
                rows.append(score(name, mode, result, expected, cases))
        # Reopen the SAME isolated trial state to exercise persistent recall.
        with assistant_runtime(state, model, workspace=workspace) as turn:
            result = turn('Apa kode sesi buatan yang tadi saya minta diingat? Balas kode saja.',
                          session_id='evaluation', mode=mode)
            rows.append(score('restart_recall', mode, result, cases['marker'], cases))
    passed = sum(row['objective_check_passed'] for row in rows)
    return dict(schema_version=1, assessed_at_utc=datetime.now(timezone.utc).isoformat(),
        result='COMPLETED_OBJECTIVE_TASKS_ONLY' if passed == len(rows) else 'NEEDS_REVIEW',
        rows=rows, passed=passed, total=len(rows),
        model_calls=sum(row['model_calls'] for row in rows),
        live_clearance=False, general_model_quality_verified=False,
        broker_execution_verified=False, token_usage=None, monetary_cost=None,
        limitations=['Generated Indonesian tasks are not a strategy or general intelligence benchmark',
                     'Exact-match scores require human review of failures and hallucinations',
                     'Token usage and cost are unavailable; latency measures full turns including local work'])


def score(name, mode, result, expected, cases):
    safe = (result.get('live_execution_authorized') is False
            and type(result.get('orders_submitted')) is int and result['orders_submitted'] == 0)
    grounded = True
    if name == 'grounded_file':
        grounded = any(item.get('tool') == 'read_file'
            and item.get('result', {}).get('path') == 'facts.txt'
            and item.get('result', {}).get('sha256') == hashlib.sha256(cases['file_text'].encode()).hexdigest()
            for item in result.get('trace', []))
    recalled = name != 'restart_recall' or bool(result.get('recalled_turn_ids'))
    passed = (safe and grounded and recalled
              and result.get('status') == 'ANSWERED_UNVERIFIED_MODEL_TEXT'
              and result.get('answer', '').strip() == expected)
    return dict(task=name, mode=mode, objective_check_passed=passed,
                status=result.get('status'), model_calls=result.get('model_calls', 0),
                elapsed_seconds=result.get('elapsed_seconds'),
                file_provenance_checked=name == 'grounded_file', recall_present=recalled,
                live_off_confirmed=safe)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', action='store_true', help='Explicitly call configured provider; may incur its costs')
    parser.add_argument('--model-config')
    parser.add_argument('--output-dir', help='Private reports and generated test state; never use observer state')
    args = parser.parse_args(argv)
    if not args.run:
        print(json.dumps(dict(result='PREPARED_NOT_RUN', modes=['fast', 'deep'], tasks_per_mode=4,
            max_provider_calls=32, provider_calls=0, general_model_quality_verified=False,
            live_clearance=False, remaining=['configured endpoint and credentials', 'real evaluation',
                                            'human review of hallucinations, latency, tokens and costs'])))
        return 0
    if not args.model_config or not args.output_dir:
        parser.error('--run requires --model-config and --output-dir')
    try:
        config = ModelConfig.load(args.model_config)
        if any('REPLACE_' in value.upper() for value in (config.fast_model, config.deep_model)):
            raise ValueError('placeholder_model')
        root = Path(args.output_dir)
        root.mkdir(parents=True, exist_ok=True)
        trial = Path(tempfile.mkdtemp(prefix='dialog-evaluation-', dir=root))
        report = evaluate(JSONDialogModel(config), trial)
        (trial/'summary.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
        print(json.dumps(report, ensure_ascii=False))
        return 0 if report['result'] == 'COMPLETED_OBJECTIVE_TASKS_ONLY' else 2
    except (ValueError, OSError, RuntimeError):
        print(json.dumps(dict(result='BLOCKED_CONFIGURATION_OR_ENVIRONMENT', live_clearance=False)))
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
