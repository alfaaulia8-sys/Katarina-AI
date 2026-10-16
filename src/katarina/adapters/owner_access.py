"""Revocable scoped Owner/analyst bearer credentials; never model-controlled."""
from hashlib import sha256
import hmac
import json
from pathlib import Path
import re


def load_access(path):
    try:
        path = Path(path)
        if path.stat().st_size > 65536:
            raise ValueError()
        data = json.loads(path.read_text(encoding='utf-8'))
        if set(data) != {'schema_version', 'principals'} or data['schema_version'] != 1:
            raise ValueError()
        rows = data['principals']
        if not isinstance(rows, list) or not 1 <= len(rows) <= 64:
            raise ValueError()
        seen_ids, seen_tokens = set(), set()
        for row in rows:
            if (not isinstance(row, dict) or set(row) != {'id', 'role', 'token_sha256', 'enabled'}
                    or not isinstance(row['id'], str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,48}', row['id'])
                    or row['role'] not in ('owner', 'analyst') or type(row['enabled']) is not bool
                    or not isinstance(row['token_sha256'], str)
                    or not re.fullmatch(r'[a-f0-9]{64}', row['token_sha256'])
                    or row['id'] in seen_ids or row['token_sha256'] in seen_tokens):
                raise ValueError()
            seen_ids.add(row['id']); seen_tokens.add(row['token_sha256'])
        if not any(row['role'] == 'owner' and row['enabled'] for row in rows):
            raise ValueError()
        return rows
    except (OSError, ValueError, TypeError, KeyError):
        raise ValueError('owner_access_config_invalid') from None


def authenticate(path, authorization):
    if (not isinstance(authorization, str) or not authorization.startswith('Bearer ')
            or not 32 <= len(authorization[7:]) <= 256
            or not authorization[7:].isascii() or any(c.isspace() for c in authorization[7:])):
        return None
    hashed = sha256(authorization[7:].encode()).hexdigest()
    # Re-read on every request: revocation takes effect without another brain.
    rows = load_access(path)
    match = None
    for row in rows:
        if hmac.compare_digest(hashed, row['token_sha256']) and row['enabled']:
            match = {'id': row['id'], 'role': row['role']}
    return match


def scoped_session(principal, session):
    if not isinstance(session, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,64}', session):
        raise ValueError('invalid_session')
    return sha256((principal['id'] + ':' + session).encode()).hexdigest()
