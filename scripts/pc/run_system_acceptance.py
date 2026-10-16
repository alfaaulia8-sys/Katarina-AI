"""Reproducible full software gate with a separate, honest host evidence check.

No order API, source mutation, strategy approval, package install or server start.
Run on a source checkout. Test databases are isolated from the active brain.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'src'))
from katarina.host import state_directory

GROUPS = ('unit', 'static', 'integration')


def snapshot_check(root):
    try:
        def read(name):
            path = Path(root)/name
            if path.stat().st_size > 16*1024*1024:
                raise ValueError()
            return json.loads(path.read_text(encoding='utf-8'))
        runtime, report = read('continuous-status.json'), read('latest.json')
        now = datetime.now(timezone.utc)
        clocks = [datetime.fromisoformat(value.replace('Z','+00:00')) for value in
                  (runtime['heartbeat_utc'], report['observed_at_utc'], report['market_snapshot_tick_utc'])]
        fresh = all(value.tzinfo is not None and 0 <= (now-value).total_seconds() <= 180 for value in clocks)
        safe = all(value.get('orders_submitted') == 0
                   and value.get('live_execution_authorized') is False
                   and value.get('production_execution') is False for value in (runtime, report))
        count = report.get('received_market_data_symbols',0)
        valid = (fresh and safe and type(count) is int and count > 0
                 and runtime.get('status') in ('WAITING','OBSERVING')
                 and runtime.get('successful_cycles',0) > 0
                 and all(not any(str(r).startswith('sensor_error:') for r in card.get('blocking_reasons',[]))
                         for card in report['symbols'].values()))
        return dict(status='FRESH_READONLY_SNAPSHOT' if valid else 'BLOCKED',
                    received_market_data_symbols=count, process_liveness_independently_verified=False,
                    source_process_binding_verified=False, snapshot_is_execution_clearance=False)
    except (OSError,ValueError,TypeError,KeyError,AttributeError):
        return dict(status='BLOCKED',reason='MISSING_INVALID_OR_STALE_OBSERVER_SNAPSHOT')


def run(root, *, observer_state=None, timeout=300):
    work = Path(root)/'full-system-test'/uuid.uuid4().hex
    work.mkdir(parents=True)
    env = dict(os.environ)
    env['PYTHONPATH'] = os.pathsep.join((str(ROOT/'src'),str(ROOT),env.get('PYTHONPATH','')))
    # Do not let a host's live/private configuration leak into synthetic subprocesses.
    for name in ('KATARINA_CONNECTION_CONFIG','KATARINA_STATE_DIR','KATARINA_OWNER_TOKEN','KATARINA_MODEL_TOKEN'):
        env.pop(name,None)
    report = dict(schema_version=1, observed_utc=datetime.now(timezone.utc).isoformat(),
        scope='SOFTWARE_ACCEPTANCE_NOT_ALPHA_OR_BROKER_EXECUTION',groups=[],
        orders_submitted=0,live_execution_authorized=False,production_ready=False,
        remaining_destination_checks=['configured real model quality and Fast/Deep latency',
          'Owner credentials and trusted HTTPS from phone',
          'own trading model validation on causal broker data',
          'version-approved demo execution and fill/cost reconciliation',
          'authorized intervention learning and multi-account isolation on actual Hands'])
    try:
        report['source_commit'] = subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True,timeout=15).strip()
        report['source_clean'] = not subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True,timeout=15).strip()
    except (OSError,subprocess.SubprocessError):
        report['source_commit']=None;report['source_clean']=False
    for group in GROUPS:
        log = work/(group+'.log')
        try:
            with log.open('w',encoding='utf-8') as stream:
                result = subprocess.run([sys.executable,'-m','unittest','discover','-s','tests/'+group,'-v'],
                    cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=timeout)
            status = 'PASS' if result.returncode == 0 else 'FAIL'
        except (OSError,subprocess.TimeoutExpired):
            status = 'BLOCKED_TIMEOUT_OR_RUNTIME'
        report['groups'].append(dict(name=group,status=status,private_log=log.name))
    report['broker_snapshot'] = snapshot_check(observer_state) if observer_state else dict(status='NOT_TESTED')
    report['software_pass'] = all(g['status']=='PASS' for g in report['groups'])
    report['status'] = 'PASS_SOFTWARE_ONLY_DESTINATION_GATES_REMAIN' if report['software_pass'] else 'BLOCKED'
    target = work/'report.json'
    target.write_text(json.dumps(report,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    return report,target


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--state-dir')
    parser.add_argument('--observer-state',help='Read only the active broker snapshot; never acquire its DB or lock')
    args=parser.parse_args()
    report,path=run(state_directory(args.state_dir),observer_state=args.observer_state)
    print(report['status']);print('Report:',path)
    return 0 if report['software_pass'] else 2


if __name__=='__main__':
    raise SystemExit(main())
