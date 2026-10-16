import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from scripts.pc.check_dialog_readiness import inspect
from scripts.pc.evaluate_dialog_model import evaluate, main, score


class DialogReadinessKitTests(unittest.TestCase):
    def test_preparation_makes_no_provider_calls(self):
        with patch('scripts.pc.evaluate_dialog_model.JSONDialogModel', side_effect=AssertionError('no provider')):
            with contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(main([]), 0)
        result = json.loads(output.getvalue())
        self.assertEqual(result['provider_calls'], 0)
        self.assertEqual(result['result'], 'PREPARED_NOT_RUN')
        self.assertFalse(result['general_model_quality_verified'])

    def test_configuration_reports_missing_prerequisites_without_secrets(self):
        result = inspect(bind='0.0.0.0', environ={'KATARINA_OWNER_TOKEN': 'short-secret'})
        self.assertIn('MODEL_CONFIG_MISSING_OR_INVALID', result['model_blockers'])
        self.assertIn('REMOTE_TLS_CERT_AND_KEY_REQUIRED', result['owner_ui_blockers'])
        self.assertNotIn('short-secret', json.dumps(result))

    def test_placeholder_and_missing_https_token_are_separate_blockers(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root)/'config.json'
            path.write_text(json.dumps(dict(endpoint='https://example.test/v1/chat/completions',
                fast_model='REPLACE_WITH_INSTALLED_MODEL_ID', deep_model='actual-model')))
            result = inspect(model_config=path, environ={'KATARINA_OWNER_TOKEN':'a'*32})
            self.assertEqual(set(result['model_blockers']), {'MODEL_ID_IS_PLACEHOLDER', 'MODEL_CREDENTIAL_MISSING'})

    def test_configured_is_not_phone_or_model_verification(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root)/'config.json'
            path.write_text(json.dumps(dict(endpoint='http://127.0.0.1:1234/chat', fast_model='small', deep_model='large')))
            result = inspect(model_config=path, environ={'KATARINA_OWNER_TOKEN':'a'*32})
            self.assertEqual(result['result'], 'CONFIGURED_NOT_NETWORK_VERIFIED')
            self.assertFalse(result['phone_tls_verified'])
            self.assertFalse(result['model_quality_verified'])
            self.assertEqual(result['provider_calls'], 0)

    def test_unusable_tls_and_revoked_access_fail_closed(self):
        result = inspect(cert='missing-cert.pem', key='missing-key.pem', access_config='missing-access.json', environ={})
        self.assertIn('TLS_CERT_KEY_UNUSABLE', result['owner_ui_blockers'])
        self.assertIn('OWNER_ACCESS_CONFIG_INVALID', result['owner_ui_blockers'])

    def test_actual_brain_file_provenance_and_restart_under_both_modes(self):
        cases = dict(a=101, b=202, expected_sum='303', marker='nonce123', file_text='Generated nonce123')
        replies = []
        for mode in ('fast', 'deep'):
            replies.extend([{'answer':'303'}, {'tool':'read_file','arguments':{'path':'facts.txt'}},
                            {'answer':'nonce123'}, {'answer':'nonce123'}, {'answer':'nonce123'}])
        class ScriptedModel:
            def __init__(self):
                self.replies = iter(replies)
                self.modes = []
            def complete(self, messages, *, mode):
                self.modes.append(mode)
                return next(self.replies)
        model = ScriptedModel()
        with tempfile.TemporaryDirectory() as root:
            result = evaluate(model, root, cases=cases)
        self.assertEqual(result['passed'], 8)
        self.assertEqual(result['model_calls'], 10)
        self.assertEqual(model.modes, ['fast']*5+['deep']*5)
        self.assertFalse(result['general_model_quality_verified'])
        self.assertFalse(result['live_clearance'])
        self.assertNotIn('nonce123', json.dumps(result))

    def test_correct_text_without_tool_evidence_cannot_pass_grounding(self):
        report = dict(status='ANSWERED_UNVERIFIED_MODEL_TEXT', answer='nonce', trace=[],
                      orders_submitted=0, live_execution_authorized=False)
        result = score('grounded_file', 'fast', report, 'nonce', {'file_text':'nonce'})
        self.assertFalse(result['objective_check_passed'])

    def test_provider_failure_is_reported_without_raw_exception(self):
        class Broken:
            def complete(self, *args, **kwargs):
                raise RuntimeError('PRIVATE_ENDPOINT_AND_TOKEN')
        with tempfile.TemporaryDirectory() as root:
            result = evaluate(Broken(), root)
        self.assertEqual(result['passed'], 0)
        self.assertEqual(result['result'], 'NEEDS_REVIEW')
        self.assertNotIn('PRIVATE_ENDPOINT_AND_TOKEN', json.dumps(result))
