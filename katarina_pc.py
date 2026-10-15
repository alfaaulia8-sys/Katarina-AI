"""Dependency-free entry point for a private PC test environment; no background work."""
from pathlib import Path
import argparse
import json
import os
import platform
import subprocess
import sys
import venv

ROOT=Path(__file__).resolve().parent
ENV=ROOT/'.venv-pc'


def environment_python():
    return ENV/('Scripts/python.exe' if os.name=='nt' else 'bin/python')


def main(argv=None):
    parser=argparse.ArgumentParser(description='Katarina PC test kit — LIVE OFF')
    parser.add_argument('action',choices=['setup','test','doctor','observe'],nargs='?',default='test')
    parser.add_argument('--mt5',action='store_true',help='Install optional native Windows MT5 package during setup')
    parser.add_argument('--state-dir')
    parser.add_argument('--connection-config')
    args=parser.parse_args(argv)
    if sys.version_info[:2]!=(3,12):
        parser.error('Python 3.12 diperlukan. Install Python 3.12 64-bit lalu ulangi.')
    python=environment_python()
    if args.action=='setup':
        if args.mt5 and (platform.system()!='Windows' or sys.maxsize<=2**32):
            parser.error('Native MT5 requires Windows 64-bit; offline/cloud client needs no MT5 package.')
        if not python.is_file():
            print('Membuat environment privat .venv-pc ...',flush=True)
            venv.EnvBuilder(with_pip=True).create(ENV)
        subprocess.run([str(python),'-c',
                        'import sys; assert sys.version_info[:2] == (3, 12), "Existing .venv-pc requires Python 3.12"'],check=True)
        subprocess.run([str(python),'-m','pip','install','--disable-pip-version-check',
                        '-r',str(ROOT/'requirements-pc.txt')],check=True,cwd=ROOT)
        if args.mt5:
            version=json.loads((ROOT/'config/runtime_dependencies_v1.json').read_text())['packages']['MetaTrader5']
            subprocess.run([str(python),'-m','pip','install','--disable-pip-version-check',
                            'MetaTrader5=='+version],check=True,cwd=ROOT)
        print('SETUP_OK. Jalankan START_KATARINA.bat atau python katarina_pc.py test. LIVE OFF.',flush=True)
        return 0
    if args.mt5:
        parser.error('--mt5 hanya untuk setup')
    if not python.is_file():
        print('SETUP_REQUIRED: jalankan SETUP_KATARINA.bat atau python katarina_pc.py setup.',file=sys.stderr)
        return 2
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
    except (OSError,subprocess.CalledProcessError):
        print('PC_SETUP_OR_LAUNCH_FAILED: lihat pesan pemasangan; tidak ada trading/unggahan otomatis.',file=sys.stderr)
        raise SystemExit(2)
