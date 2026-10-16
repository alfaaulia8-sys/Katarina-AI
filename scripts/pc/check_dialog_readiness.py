"""Configuration-only model/Owner preflight. No sockets, provider calls or writes."""
import argparse
import ipaddress
import json
import os
from pathlib import Path
import ssl
import sys
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[2]/'src'))
from katarina.adapters.dialog_model import ModelConfig
from katarina.adapters.owner_access import load_access


def inspect(*, model_config=None, bind='127.0.0.1', cert=None, key=None,
            access_config=None, environ=None):
    environ = os.environ if environ is None else environ
    model_blockers, ui_blockers = [], []
    try:
        config = ModelConfig.load(model_config)
        if any('REPLACE_' in value.upper() for value in (config.fast_model, config.deep_model)):
            model_blockers.append('MODEL_ID_IS_PLACEHOLDER')
        if urlsplit(config.endpoint).scheme == 'https' and not environ.get(config.token_env):
            model_blockers.append('MODEL_CREDENTIAL_MISSING')
    except (ValueError, TypeError):
        model_blockers.append('MODEL_CONFIG_MISSING_OR_INVALID')
    if access_config:
        try:
            load_access(access_config)
        except ValueError:
            ui_blockers.append('OWNER_ACCESS_CONFIG_INVALID')
    else:
        token = environ.get('KATARINA_OWNER_TOKEN', '')
        if not isinstance(token, str) or len(token) < 32 or not token.isascii() or any(c.isspace() for c in token):
            ui_blockers.append('OWNER_CREDENTIAL_MISSING_OR_INVALID')
    try:
        loopback = bind == 'localhost' or ipaddress.ip_address(bind).is_loopback
    except ValueError:
        loopback = False
    if not loopback and not (cert and key):
        ui_blockers.append('REMOTE_TLS_CERT_AND_KEY_REQUIRED')
    if cert or key:
        try:
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.minimum_version = ssl.TLSVersion.TLSv1_2
            context.load_cert_chain(cert, key, password=lambda: '')
        except (OSError, ValueError, TypeError):
            ui_blockers.append('TLS_CERT_KEY_UNUSABLE')
    return dict(schema_version=1,
        result='BLOCKED_CONFIGURATION' if model_blockers or ui_blockers else 'CONFIGURED_NOT_NETWORK_VERIFIED',
        model_blockers=model_blockers, owner_ui_blockers=ui_blockers,
        remote_binding=not loopback, provider_calls=0, live_clearance=False,
        model_quality_verified=False, phone_tls_verified=False,
        remaining=['real model tasks', 'certificate expiry, hostname and phone trust',
                   'authorized network reachability', 'same-brain Owner surface on target host'])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('model-config', 'cert', 'key', 'access-config'):
        parser.add_argument('--'+name)
    parser.add_argument('--bind', default='127.0.0.1')
    args = parser.parse_args(argv)
    result = inspect(**vars(args))
    print(json.dumps(result, sort_keys=True))
    return 2 if result['result'] == 'BLOCKED_CONFIGURATION' else 0


if __name__ == '__main__':
    raise SystemExit(main())
