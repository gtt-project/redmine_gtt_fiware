#!/usr/bin/env python3
"""Header-echo fake FIWARE broker for verifying the plugin's auth modes.

Logs every request (method, path, headers) as a JSON line to stdout, answers
subscription POSTs with 201 + a Location header, and speaks enough CORS for a
cross-origin browser-mode fetch (including exposing Location, which
publish.js.erb reads). No state, no dependencies beyond the standard library.

Usage (any container runtime; the port must be reachable both by the Redmine
server for stored/relayed mode and by the operator's browser for browser mode):

    podman run -d --name fakebroker --network <redmine-network> -p 9999:9999 \
      -v $(pwd)/plugins/redmine_gtt_fiware/doc/scripts/fake_broker.py:/srv/broker.py:ro \
      docker.io/library/python:3-alpine python /srv/broker.py

    podman logs fakebroker        # the request log

Environment:
    PORT        listen port (default 9999)
    BROKER_LOG  optional file to append the JSON lines to as well
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    counter = 0

    def _cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PATCH, DELETE, OPTIONS')
        # Authorization is excluded from the '*' wildcard, so list explicitly.
        self.send_header('Access-Control-Allow-Headers',
                         'Authorization, Content-Type, X-Api-Key, X-Auth-Token, '
                         'Fiware-Service, Fiware-ServicePath, NGSILD-Tenant')
        self.send_header('Access-Control-Expose-Headers', 'Location')

    def _log(self):
        line = json.dumps({'method': self.command, 'path': self.path,
                           'headers': dict(self.headers)})
        print(line, flush=True)
        log_file = os.environ.get('BROKER_LOG')
        if log_file:
            with open(log_file, 'a') as f:
                f.write(line + '\n')

    def do_OPTIONS(self):
        self._log()
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_POST(self):
        # A malformed Content-Length must not crash the verification server.
        try:
            length = int(self.headers.get('Content-Length', 0))
        except (TypeError, ValueError):
            length = 0
        self.rfile.read(length)
        self._log()
        Handler.counter += 1
        self.send_response(201)
        self._cors()
        self.send_header('Location', '/v2/subscriptions/fake-sub-%d' % Handler.counter)
        self.end_headers()

    def do_DELETE(self):
        self._log()
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        self._log()
        body = json.dumps({'status': 'active'}).encode()
        self.send_response(200)
        self._cors()
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == '__main__':
    port = int(os.environ.get('PORT', '9999'))
    print('fake broker listening on :%d' % port, file=sys.stderr, flush=True)
    HTTPServer(('0.0.0.0', port), Handler).serve_forever()
