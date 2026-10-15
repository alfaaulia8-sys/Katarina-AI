"""CI-only fault injection on an extracted test kit, never an operator environment."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys


def verify(package,state):
    package,state=Path(package).resolve(),Path(state).resolve()
    base=package/'.katarina-envs'
    pointer=base/'active.json'
    before=json.loads(pointer.read_text())['active']
    python=base/before/('Scripts/python.exe' if os.name=='nt' else 'bin/python')
    backup=python.with_name(python.name+'.ci-unavailable')
    python.rename(backup)
    try:
        subprocess.run([sys.executable,str(package/'katarina_pc.py'),'test',
                        '--state-dir',str(state)],check=True)
        after=json.loads(pointer.read_text())['active']
        assert after!=before,'broken environment remained active'
        assert backup.exists(),'old environment was deleted'
        report=json.loads((state/'latest-pc-test.json').read_text())
        assert report['status']=='PASS_SYNTHETIC_PC_ONLY'
        assert report['orders_sent']==0 and report['live_authorized'] is False
        print('PC_ENVIRONMENT_AUTO_REPAIR_PASS old_preserved=True live=False')
    finally:
        if backup.exists():backup.rename(python)


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('package')
    parser.add_argument('state')
    args=parser.parse_args()
    verify(args.package,args.state)
