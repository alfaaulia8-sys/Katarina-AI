"""Non-executable brain -> Hands feedback with bounded TTL and duplicate IDs.

This receipt is never a broker fill or an order queue. Restart creates a new
session, so old network messages cannot be retried into a new bridge session.
"""
from hashlib import sha256
import json
import re
import time


class FeedbackInbox:
    def __init__(self):
        self._seen = {}

    def accept(self, message):
        if (not isinstance(message, dict)
                or set(message) != {'feedback_id', 'symbol', 'action', 'created_at', 'expires_at', 'plan_sha256'}
                or not isinstance(message['feedback_id'], str)
                or not re.fullmatch(r'[0-9a-f]{32}', message['feedback_id'])
                or not isinstance(message['symbol'], str) or not 1 <= len(message['symbol']) <= 128
                or message['action'] != 'WAIT_LIVE_OFF'
                or not isinstance(message['plan_sha256'], str)
                or not re.fullmatch(r'[0-9a-f]{64}', message['plan_sha256'])
                or any(type(message[k]) not in (int, float) for k in ('created_at', 'expires_at'))):
            raise ValueError('invalid_nonexecuting_feedback')
        now = time.time()
        if not (now - 30 <= message['created_at'] <= now + 2
                and now < message['expires_at'] <= message['created_at'] + 30):
            raise ValueError('feedback_expired_or_invalid_clock')
        digest = sha256(json.dumps(message, sort_keys=True, allow_nan=False).encode()).hexdigest()
        self._seen = {key: value for key, value in self._seen.items() if value[1] > now}
        prior = self._seen.get(message['feedback_id'])
        if prior is not None and prior[0] != digest:
            raise ValueError('feedback_id_conflict')
        if prior is None and len(self._seen) >= 1024:
            raise ValueError('feedback_session_capacity_reached')
        self._seen[message['feedback_id']] = (digest, message['expires_at'])
        return {'feedback_id': message['feedback_id'], 'message_sha256': digest,
                'status': 'ACKNOWLEDGED_LIVE_OFF', 'duplicate': prior is not None,
                'orders_submitted': 0, 'live_execution_authorized': False}
