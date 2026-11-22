#!/usr/bin/env python3
"""A tiny fake CPA for the Windows end-to-end test.

It listens on 127.0.0.1 only, accepts one made-up key and never talks to the
network. Usage: mock-cpa-server.py PORT LOGFILE

Requests are appended to LOGFILE as JSON lines: the HTTP method, path, the
requested model, whether the x-api-key header held the expected key, which
auth headers were present, the key length and the first 30 characters of the
User-Agent. The key itself is never written.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

KEY = "ci-test-key"
CLAUDE = ["claude-sonnet-5-5", "claude-opus-5-5", "claude-haiku-5-5"]
# Only these two main-model aliases are open to the key; the other two
# answer 401, so the installer must skip them.
ALIASES = {"sonnet-sol-6-2-claude-code", "haiku-luna-6-claude-code"}


class Handler(BaseHTTPRequestHandler):
    server_version = "mock-cpa"

    def _record(self, model=""):
        sent = self.headers.get("x-api-key")
        ok = sent == KEY
        auth = [h for h in ("x-api-key", "authorization") if self.headers.get(h) is not None]
        entry = {
            "method": self.command, "path": self.path, "model": model, "key_ok": ok,
            "auth": "+".join(auth) or "none", "key_len": len(sent or ""),
            "ua": (self.headers.get("user-agent") or "")[:30],
        }
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")
        return ok

    def _send(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _denied(self):
        self._send(401, {"type": "error", "error": {"type": "authentication_error", "message": "invalid key"}})

    def do_GET(self):
        if not self._record():
            return self._denied()
        if self.path.startswith("/v1/models"):
            ids = CLAUDE + sorted(ALIASES)
            return self._send(200, {"data": [{"id": i, "type": "model"} for i in ids]})
        self._send(404, {"type": "error", "error": {"type": "not_found_error", "message": "not found"}})

    def do_POST(self):
        length = int(self.headers.get("content-length") or 0)
        try:
            model = json.loads(self.rfile.read(length) or b"{}").get("model", "")
        except Exception:
            model = ""
        ok = self._record(model)
        if ok and (model in CLAUDE or model in ALIASES):
            return self._send(200, {
                "id": "msg_ci", "type": "message", "role": "assistant", "model": model,
                "content": [{"type": "text", "text": "pong"}],
                "stop_reason": "end_turn",
                "usage": {"input_tokens": 1, "output_tokens": 1},
            })
        self._denied()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    LOG = sys.argv[2]
    ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
