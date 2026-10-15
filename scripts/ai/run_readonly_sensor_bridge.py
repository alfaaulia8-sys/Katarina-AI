"""Explicit HTTPS read-only sensor sidecar; never starts on import or by discovery."""
from pathlib import Path
import argparse
import hmac
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
import ssl
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'src'))
from katarina.adapters.automatic_connection import BoundLocalBroker, ConnectionConfig
from katarina.adapters.readonly_cloud import ReadOnlySensorBridge, MAX_BYTES


def handler_type(bridge,token):
    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(5)

        def log_message(self,*args):
            pass

        def do_POST(self):
            if self.path!='/sensor-v1' or not hmac.compare_digest(
                    self.headers.get('Authorization',''),'Bearer '+token):
                self.send_error(403); return
            try:
                if self.headers.get('Transfer-Encoding') is not None:
                    raise ValueError()
                length=int(self.headers.get('Content-Length','0'))
                if not 0<length<=65536:
                    raise ValueError()
                request=json.loads(self.rfile.read(length))
                response=bridge.dispatch(request)
                body=json.dumps(response,allow_nan=False).encode()
                if len(body)>MAX_BYTES:
                    raise ValueError()
            except Exception:
                self.send_error(400,'SENSOR_REQUEST_REJECTED'); return
            self.send_response(200)
            self.send_header('Content-Type','application/json')
            self.send_header('Content-Length',str(len(body)))
            self.send_header('Cache-Control','no-store')
            self.end_headers()
            self.wfile.write(body)
    return Handler


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--connection-config',required=True)
    parser.add_argument('--cert',required=True)
    parser.add_argument('--key',required=True)
    parser.add_argument('--bind',default='127.0.0.1')
    parser.add_argument('--port',type=int,default=8743)
    args=parser.parse_args()
    config=ConnectionConfig.load(args.connection_config)
    token=os.environ.get(config.cloud_token_env,'')
    if len(token)<32 or not token.isascii() or any(c.isspace() for c in token):
        parser.error('CLOUD_CREDENTIAL_UNAVAILABLE')
    import MetaTrader5
    broker=BoundLocalBroker(MetaTrader5,config)
    server=None
    try:
        broker.initialize()
        context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version=ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(args.cert,args.key)
        server=HTTPServer((args.bind,args.port),handler_type(ReadOnlySensorBridge(broker,config),token))
        server.socket=context.wrap_socket(server.socket,server_side=True)
        print('KATARINA_READONLY_SENSOR_V1 READY LIVE_OFF',flush=True)
        server.serve_forever()
    finally:
        if server is not None:
            server.server_close()
        broker.shutdown()


if __name__=='__main__':
    main()
