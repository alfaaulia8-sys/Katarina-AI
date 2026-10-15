"""Dependency-free entry point for a private PC test environment; no background work."""
from pathlib import Path
import argparse
import json
import os
import platform
import subprocess
import sys
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT))
from scripts.pc.environment_recovery import EnvironmentManager, RecoveryBlocked


def main(argv=None):
    parser=argparse.ArgumentParser(description='Katarina PC test kit — LIVE OFF')
    parser.add_argument('action',choices=['setup','repair','repair-status','test','doctor','observe'],nargs='?',default='test')
    parser.add_argument('--no-auto-repair',action='store_true',help='Block instead of installing a replacement environment')
    parser.add_argument('--mt5',action='store_true',help='Install optional native Windows MT5 package during setup')
    parser.add_argument('--state-dir')
    parser.add_argument('--connection-config')
    args=parser.parse_args(argv)
    if sys.version_info[:2]!=(3,12):
        parser.error('Python 3.12 diperlukan. Install Python 3.12 64-bit lalu ulangi.')
    if args.mt5 and args.action not in ('setup','repair'):
        parser.error('--mt5 hanya untuk setup/repair')
    manager=EnvironmentManager(ROOT)
    if args.action=='repair-status':
        print(json.dumps(manager.status(),sort_keys=True),flush=True)
        return 0
    print('Memeriksa environment privat Katarina; pemulihan terbatas, LIVE OFF ...',flush=True)
    python=manager.ensure(mt5=args.mt5,explicit=args.action in ('setup','repair'),
                          force=args.action=='repair',auto=not args.no_auto_repair)
    if args.action in ('setup','repair'):
        print('SETUP_OK. Environment lulus uji sintetis. Jalankan START_KATARINA.bat. LIVE OFF.',flush=True)
        return 0
    # Disable accidental inheritance of a different checkout's Python import path.
    env=dict(os.environ)
    env.pop('PYTHONHOME',None)
    env['PYTHONPATH']=str(ROOT/'src')+os.pathsep+str(ROOT)
    if args.action=='doctor':
        command=[str(python),str(ROOT/'scripts/ai/run_contextual_market_observer.py'),'--doctor']
    else:
        command=[str(python),str(ROOT/'scripts/pc/run_pc_acceptance.py'),
                 '--mode','observe' if args.action=='observe' else 'demo']
    if args.state_dir:
        command+=['--state-dir',args.state_dir]
    if args.connection_config and args.action=='observe':
        command+=['--connection-config',args.connection_config]
    result=subprocess.run(command,cwd=ROOT,env=env)
    if result.returncode:
        print('Uji belum lulus. Periksa pesan di atas; ulangi setup bila dependensi belum lengkap.',file=sys.stderr)
    return result.returncode


if __name__=='__main__':
    try:
        raise SystemExit(main())
    except RecoveryBlocked as exc:
        print("PC_RECOVERY_BLOCKED:",str(exc),"Environment lama dan memori dipertahankan.",file=sys.stderr)
        raise SystemExit(2)
    except (OSError,ValueError,subprocess.CalledProcessError):
        print('PC_SETUP_OR_LAUNCH_FAILED: lihat pesan pemasangan; tidak ada trading/unggahan otomatis.',file=sys.stderr)
        raise SystemExit(2)
