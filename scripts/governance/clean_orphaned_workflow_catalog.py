"""Disable orphaned Actions registrations only on the verified current main SHA.

Never deletes workflow runs, artifacts, branches, source or GitHub dynamic jobs.
Default is dry-run. The main-only maintenance job explicitly enables execution.
"""
import argparse
import json
import os
from pathlib import Path
from urllib.request import Request, urlopen

REPOSITORY = 'alfaauliau-katarinaAI/Katarina-AI'


def cleanup(api, root, expected_sha, *, execute=False):
    root = Path(root).resolve()
    if not expected_sha or api('/branches/main')['commit']['sha'] != expected_sha:
        raise RuntimeError('current_main_sha_required')
    workflows = []
    for page in range(1, 101):
        batch = api('/actions/workflows?per_page=100&page=' + str(page))['workflows']
        workflows.extend(batch)
        if len(batch) < 100:
            break
    else:
        raise RuntimeError('workflow_catalog_pagination_incomplete')
    report = {'dry_run':not execute, 'source_commit':expected_sha,
              'examined':len(workflows), 'candidates':[], 'disabled':[],
              'workflow_runs_deleted':0, 'source_modified':False}
    for item in workflows:
        path = item.get('path', '')
        if (not isinstance(path, str) or not path.startswith('.github/workflows/')
                or '..' in Path(path).parts or not path.endswith(('.yml', '.yaml'))
                or (root/path).is_file() or item.get('state') != 'active'):
            continue
        if type(item.get('id')) is not int or item['id'] <= 0:
            raise RuntimeError('invalid_orphan_workflow_identity')
        record = {'id':item['id'], 'path':path}
        report['candidates'].append(record)
        if not execute:
            continue
        if api('/branches/main')['commit']['sha'] != expected_sha:
            raise RuntimeError('main_changed_during_catalog_cleanup')
        if (root/path).is_file():
            continue
        api('/actions/workflows/' + str(item['id']) + '/disable', method='PUT')
        report['disabled'].append(record)
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args()
    if (os.environ.get('GITHUB_REPOSITORY') != REPOSITORY
            or os.environ.get('GITHUB_REF') != 'refs/heads/main'):
        raise RuntimeError('canonical_main_only')
    token = os.environ.get('GITHUB_TOKEN', '')
    if not token:
        raise RuntimeError('actions_token_required')
    def api(path, *, method='GET'):
        request = Request('https://api.github.com/repos/' + REPOSITORY + path,
            method=method, headers={'Authorization':'Bearer ' + token,
                                   'Accept':'application/vnd.github+json',
                                   'X-GitHub-Api-Version':'2022-11-28'})
        with urlopen(request, timeout=20) as response:
            return None if response.status == 204 else json.load(response)
    report = cleanup(api, Path(__file__).resolve().parents[2],
                     os.environ.get('GITHUB_SHA'), execute=args.execute)
    output = Path('build/validation/workflow-catalog-hygiene.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n')
    print('WORKFLOW_CATALOG_HYGIENE', 'disabled', len(report['disabled']),
          'runs_deleted', report['workflow_runs_deleted'])


if __name__ == '__main__':
    main()
