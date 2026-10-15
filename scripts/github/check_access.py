"""Read-only GitHub CLI readiness check. Never prints credentials or tests writes."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def assess(identity, repository, checks):
    permissions = repository.get('permissions', {})
    role_ready = bool(permissions.get('push') and permissions.get('admin'))
    expected_owner = repository['full_name'].split('/')[0]
    return {
        'repository': repository['full_name'],
        'authenticated_login': identity.get('login'),
        'expected_owner': expected_owner,
        'owner_matches': identity.get('login') == expected_owner,
        'repository_role': {key: bool(permissions.get(key)) for key in ('pull', 'push', 'admin')},
        'read_checks': checks,
        'owner_role_available': role_ready and identity.get('login') == expected_owner,
        'write_operations_verified': False,
        'credentials_exported': False,
        'live_execution_enabled': False,
        'result': 'READ_ACCESS_VERIFIED_WRITE_UNTESTED' if all(checks.values()) else 'READ_ACCESS_INCOMPLETE',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', default=json.loads((ROOT/'config/project_identity.json').read_text())['canonical_repository'])
    args = parser.parse_args()
    if args.repo.count('/') != 1 or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_/.' for c in args.repo):
        parser.error('use owner/repository')
    if not shutil.which('gh'):
        print(json.dumps({'result': 'BLOCKED_GITHUB_CLI_NOT_INSTALLED', 'write_operations_verified': False}))
        return 2
    def api(path):
        result = subprocess.run(['gh', 'api', '--hostname', 'github.com', path],
                                capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise RuntimeError('GITHUB_API_ACCESS_DENIED_OR_UNAVAILABLE')
        return json.loads(result.stdout)
    try:
        user = api('user')
        repo = api('repos/'+args.repo)
        checks = {'repository': True}
        for name, endpoint in {
            'main': '/branches/main',
            'pull_requests': '/pulls?state=open&per_page=1',
            'actions': '/actions/workflows?per_page=1',
            'protection_administration_read': '/branches/main/protection',
        }.items():
            try:
                api('repos/'+args.repo+endpoint)
                checks[name] = True
            except (RuntimeError, ValueError, subprocess.TimeoutExpired):
                checks[name] = False
        report = assess(user, repo, checks)
        print(json.dumps(report, indent=2))
        return 0 if all(checks.values()) and report['owner_matches'] else 1
    except (RuntimeError, ValueError, subprocess.TimeoutExpired):
        print(json.dumps({'result': 'BLOCKED_AUTHENTICATION_OR_ACCESS', 'write_operations_verified': False}))
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
