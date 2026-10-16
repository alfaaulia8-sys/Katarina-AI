"""Local Owner credential administration. Run only on the private host console."""
import argparse
from hashlib import sha256
import json
from pathlib import Path
import secrets
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]/'src'))
from katarina.adapters.owner_access import load_access


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('issue', 'revoke'))
    parser.add_argument('--config', required=True)
    parser.add_argument('--id', required=True)
    parser.add_argument('--role', choices=('owner', 'analyst'), default='owner')
    args = parser.parse_args()
    path = Path(args.config)
    rows = load_access(path) if path.exists() else []
    old = next((r for r in rows if r['id'] == args.id), None)
    token = None
    if args.action == 'issue':
        if old:
            raise ValueError('existing_principal_requires_explicit_revoke_and_new_id')
        token = secrets.token_urlsafe(36)
        rows.append(dict(id=args.id, role=args.role, token_sha256=sha256(token.encode()).hexdigest(), enabled=True))
    else:
        if old is None:
            raise ValueError('unknown_principal')
        old['enabled'] = False
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name+'.tmp')
    try:
        temp.write_text(json.dumps(dict(schema_version=1, principals=rows), indent=2)+'\n', encoding='utf-8')
        load_access(temp)
        temp.chmod(0o600)
        temp.replace(path)
    finally:
        temp.unlink(missing_ok=True)
    if token:
        print('TOKEN (private console only, displayed once): '+token)
    print('Access policy updated; no risk settings or strategies changed.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError):
        print('ACCESS_CHANGE_BLOCKED', file=sys.stderr)
        raise SystemExit(2)
