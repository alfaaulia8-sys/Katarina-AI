"""Authenticated HTTPS sensor bridge v1, separate from frozen KAT1 execution.

No order API, login operation, redirects, TLS bypass or discovery scan exists.
A bridge must be explicitly installed/configured; this is not an existing Cloud
Hands production deployment. Responses bind request nonce and bridge session.
"""
from __future__ import annotations

from datetime import datetime, timezone
import json
import secrets
import ssl
import time
from types import SimpleNamespace
from urllib.parse import urlsplit
from urllib.request import Request, build_opener, HTTPSHandler, HTTPRedirectHandler, ProxyHandler

from katarina.adapters.automatic_connection import (
    CONSTANTS, METHODS, ConnectionUnavailable, verify_identity,
)

PROTOCOL = 'KATARINA_READONLY_SENSOR_V1'
MAX_BYTES = 4 * 1024 * 1024


def validate_endpoint(url):
    try:
        parsed = urlsplit(url)
        if (parsed.scheme != 'https' or not parsed.hostname or parsed.username
                or parsed.password or parsed.query or parsed.fragment
                or parsed.path not in ('', '/', '/sensor-v1')
                or parsed.port == 0):
            raise ValueError()
    except (ValueError, TypeError, AttributeError):
        raise ValueError('invalid_cloud_https_endpoint') from None
    return url.rstrip('/') if parsed.path == '/sensor-v1' else url.rstrip('/') + '/sensor-v1'


def pack(value):
    if isinstance(value,datetime):
        if value.tzinfo is None:
            raise ValueError('aware_datetime_required')
        return {'__utc__':value.astimezone(timezone.utc).isoformat()}
    if hasattr(value,'_asdict'):
        return {'__record__':{k:pack(v) for k,v in value._asdict().items()}}
    if isinstance(value,SimpleNamespace):
        return {'__record__':{k:pack(v) for k,v in vars(value).items()}}
    if isinstance(value,dict):
        return {k:pack(v) for k,v in value.items()}
    if isinstance(value,(tuple,list)):
        return [pack(v) for v in value]
    if getattr(getattr(value,'dtype',None),'names',None):
        if getattr(value,'ndim',0)>0:
            return [pack(row) for row in value]
        return {k:pack(value[k]) for k in value.dtype.names}
    if hasattr(value,'tolist'):
        return pack(value.tolist())
    return value


def unpack(value):
    if isinstance(value,list):
        return [unpack(x) for x in value]
    if isinstance(value,dict):
        if set(value)=={'__utc__'}:
            result=datetime.fromisoformat(value['__utc__'])
            if result.tzinfo is None:
                raise ValueError('invalid_wire_clock')
            return result
        if set(value)=={'__record__'}:
            return SimpleNamespace(**{k:unpack(v) for k,v in value['__record__'].items()})
        return {k:unpack(v) for k,v in value.items()}
    return value


def _fresh(value):
    return type(value) in (int,float) and abs(time.time()-value)<=30


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ConnectionUnavailable('CLOUD_REDIRECT_REJECTED')


class CloudReadOnlyBroker:
    def __init__(self,url,token,config,*,exchange=None):
        self._url=validate_endpoint(url)
        if not isinstance(token,str) or len(token)<32 or not token.isascii() or any(c.isspace() for c in token):
            raise ConnectionUnavailable('CLOUD_CREDENTIAL_UNAVAILABLE')
        self._token,self._config=token,config
        self._exchange=exchange or self._https
        self._session=None
        self._constants={}
        self._failed=False
        self._faulted=False

    @property
    def connection_failed(self):
        return self._faulted

    def _https(self, payload):
        raw=json.dumps(payload,allow_nan=False).encode()
        request=Request(self._url,data=raw,headers={
            'Authorization':'Bearer '+self._token,'Content-Type':'application/json'},method='POST')
        opener=build_opener(ProxyHandler({}),HTTPSHandler(context=ssl.create_default_context()),_NoRedirect())
        with opener.open(request,timeout=5) as response:
            if response.status!=200:
                raise ConnectionUnavailable('CLOUD_HTTP_REJECTED')
            data=response.read(MAX_BYTES+1)
        if len(data)>MAX_BYTES:
            raise ConnectionUnavailable('CLOUD_RESPONSE_TOO_LARGE')
        return json.loads(data,parse_constant=lambda x:(_ for _ in ()).throw(ValueError()))

    def _request(self, method, args=()):
        if self._failed:
            raise ConnectionUnavailable('CLOUD_SESSION_FAULTED')
        nonce=secrets.token_hex(16)
        try:
            response=self._exchange({'protocol':PROTOCOL,'request_id':nonce,
                'session':self._session,'sent_at':time.time(),'method':method,'args':pack(args)})
            if (response['protocol']!=PROTOCOL or response['request_id']!=nonce
                    or not _fresh(response['sent_at']) or response.get('error')
                    or not isinstance(response['session'],str) or not response['session']
                    or (self._session is not None and response['session']!=self._session)):
                raise ValueError()
            if method=='hello':
                self._session=response['session']
            return unpack(response['result'])
        except Exception:
            self._failed=True
            self._faulted=True
            raise ConnectionUnavailable('CLOUD_SESSION_REJECTED') from None

    def initialize(self):
        self._failed=False
        self._faulted=False
        self._session=None
        hello=self._request('hello')
        if (not isinstance(hello,dict) or hello.get('read_only') is not True
                or set(hello.get('constants',{}))!=set(CONSTANTS)
                or any(type(v) is not int for v in hello['constants'].values())):
            raise ConnectionUnavailable('CLOUD_CAPABILITIES_REJECTED')
        self._constants=hello['constants']
        verify_identity(self,self._config)
        return True

    def brain_feedback(self, message):
        if self._session is None:
            raise ConnectionUnavailable('CLOUD_NOT_CONNECTED')
        # The bridge validates the account before and after the nonexecuting ACK.
        return self._request('brain_feedback', (message,))

    def shutdown(self):
        self._session=None
        self._constants={}
        self._failed=True

    def __getattr__(self,name):
        if name in CONSTANTS:
            if name not in self._constants:
                raise ConnectionUnavailable('CLOUD_NOT_CONNECTED')
            return self._constants[name]
        if name not in METHODS:
            raise AttributeError(name)
        def read(*args,**kwargs):
            if kwargs or self._session is None:
                raise ConnectionUnavailable('CLOUD_READ_REJECTED')
            return self._request(name,args)
        return read


class ReadOnlySensorBridge:
    """Server-side dispatcher: read-only binding checked before every operation."""
    def __init__(self,broker,config):
        self._broker,self._config=broker,config
        self.session=secrets.token_hex(24)
        from katarina.adapters.brain_feedback import FeedbackInbox
        self._feedback = FeedbackInbox()

    def dispatch(self,request):
        if (not isinstance(request,dict) or request.get('protocol')!=PROTOCOL
                or not isinstance(request.get('request_id'),str)
                or len(request['request_id'])!=32 or not _fresh(request.get('sent_at'))):
            raise ValueError('invalid_sensor_request')
        method=request.get('method')
        if method!='hello' and (method not in METHODS | {'brain_feedback'} or request.get('session')!=self.session):
            raise ValueError('sensor_operation_rejected')
        args=unpack(request.get('args'))
        self._validate_args(method,args)
        verify_identity(self._broker,self._config)
        if method=='hello':
            result={'read_only':True,'constants':{k:getattr(self._broker,k) for k in CONSTANTS}}
        elif method == 'brain_feedback':
            result = self._feedback.accept(args[0])
        else:
            result=getattr(self._broker,method)(*args)
        verify_identity(self._broker,self._config)
        return {'protocol':PROTOCOL,'request_id':request['request_id'],'session':self.session,
                'sent_at':time.time(),'result':pack(result)}

    def _validate_args(self,method,args):
        arity={'brain_feedback':1,'hello':0,'terminal_info':0,'account_info':0,'positions_get':0,'orders_get':0,
               'symbols_get':0,'symbol_info_tick':1,'symbol_info':1,'symbol_select':2,
               'copy_ticks_range':4,'copy_rates_from_pos':4,'history_deals_get':2}
        if method not in arity or not isinstance(args,list) or len(args)!=arity[method]:
            raise ValueError('invalid_sensor_arguments')
        if method in ('symbol_info_tick','symbol_info','symbol_select','copy_ticks_range','copy_rates_from_pos'):
            if not isinstance(args[0],str) or not 1<=len(args[0])<=128:
                raise ValueError('invalid_symbol')
        if method=='symbol_select' and args[1] is not True:
            raise ValueError('invalid_marketwatch_selection')
        if method=='copy_rates_from_pos':
            if (any(type(x) is not int for x in args[1:])
                    or args[1] not in [getattr(self._broker,k) for k in CONSTANTS[:3]]
                    or not 0<=args[2]<=10000 or not 1<=args[3]<=10000):
                raise ValueError('invalid_bar_window')
        if method in ('copy_ticks_range','history_deals_get'):
            start,end=args[1:3] if method=='copy_ticks_range' else args
            if (not isinstance(start,datetime) or not isinstance(end,datetime)
                    or start.tzinfo is None or end.tzinfo is None
                    or not 0<(end-start).total_seconds()<=30*86400):
                raise ValueError('invalid_history_window')
            if method=='copy_ticks_range' and args[3]!=self._broker.COPY_TICKS_INFO:
                raise ValueError('invalid_tick_flags')
