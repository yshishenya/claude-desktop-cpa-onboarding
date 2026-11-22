#!/usr/bin/env python3
"""Test scripts/sync-cpa-main-models.py against a fake CPA management API.

Nothing here touches a real server: a tiny HTTP server keeps aliases and keys in
memory and accepts one made-up management token. The test checks that

- the plan (no --apply) changes nothing;
- --apply --key-name changes only that key and creates only the missing aliases;
- other keys, existing aliases and the key's old models stay as they were;
- a second run changes nothing;
- the management token never appears in the script's output.
"""
import copy
import json
import os
import stat
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(REPO, "scripts", "sync-cpa-main-models.py")
TOKEN = "ci-management-token"
PREFIX = "/v0/management/plugins/cpa-key-policy"


def route(alias, target_model, provider="openai"):
    return {
        "alias": alias,
        "targets": [{"provider": provider, "target_model": target_model}],
        "dispatch": "round-robin",
        "billing_mode": "tokens",
    }


def entry(alias, target_model, provider="openai"):
    return {"alias": alias, "provider": provider, "target_model": target_model, "billing_mode": "tokens"}


STATE = {
    "aliases": [
        route("gpt-6.2-astra", "gpt-6.2-astra"),
        route("gpt-6.2-sol", "gpt-6.2-sol"),
        route("gpt-6.1-terra", "gpt-6.1-terra"),
        route("gpt-6-luna", "gpt-6-luna"),
        route("claude-opus-5-5", "claude-opus-5-5", "anthropic"),
        route("claude-sonnet-5-5", "claude-sonnet-5-5", "anthropic"),
        route("claude-haiku-5-5", "claude-haiku-5-5", "anthropic"),
        route("sonnet-6-2-sol-cpa", "gpt-6.2-sol"),  # an older alias that must stay untouched
    ],
    "keys": [
        {
            "id": "k1", "name": "[P4]a.duduts", "enabled": True, "rpm": 60,
            "daily_limit_usd": 5, "weekly_limit_usd": 20, "allow_models_endpoint": True,
            "models": [
                entry("claude-sonnet-5-5", "claude-sonnet-5-5", "anthropic"),
                entry("claude-haiku-5-5", "claude-haiku-5-5", "anthropic"),
                entry("sonnet-6-2-sol-cpa", "gpt-6.2-sol"),
            ],
            "aliases": [{"alias": "claude-sonnet-5-5"}, {"alias": "claude-haiku-5-5"}, {"alias": "sonnet-6-2-sol-cpa"}],
        },
        {
            "id": "k2", "name": "other-user", "enabled": True, "rpm": 0,
            "daily_limit_usd": 0, "weekly_limit_usd": 0, "allow_models_endpoint": True,
            "models": [entry("sonnet-6-2-sol-cpa", "gpt-6.2-sol")],
            "aliases": [{"alias": "sonnet-6-2-sol-cpa"}],
        },
    ],
}
CALLS = []
FAULTS = {"reset_rpm": False}  # makes the fake server misbehave on PATCH, to test the read-back


class Handler(BaseHTTPRequestHandler):
    def _auth(self):
        if self.headers.get("Authorization") != "Bearer " + TOKEN:
            self._send(401, {"error": "unauthorized"})
            return False
        return True

    def _send(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        length = int(self.headers.get("content-length") or 0)
        return json.loads(self.rfile.read(length) or b"{}")

    def do_GET(self):
        if not self._auth():
            return
        CALLS.append(("GET", self.path))
        if self.path == PREFIX + "/aliases":
            return self._send(200, {"aliases": STATE["aliases"]})
        if self.path == PREFIX + "/keys":
            return self._send(200, {"keys": STATE["keys"]})
        self._send(404, {})

    def do_POST(self):
        if not self._auth():
            return
        CALLS.append(("POST", self.path))
        if self.path == PREFIX + "/aliases":
            STATE["aliases"].append(self._body())
            return self._send(200, {})
        self._send(404, {})

    def do_PATCH(self):
        if not self._auth():
            return
        CALLS.append(("PATCH", self.path))
        if self.path == PREFIX + "/keys":
            payload = self._body()
            for i, key in enumerate(STATE["keys"]):
                if key["id"] == payload["id"]:
                    merged = {**key, **payload}
                    if FAULTS["reset_rpm"]:
                        merged["rpm"] = 0  # the server silently resets a limit
                    if "aliases" not in payload:
                        # The defect documented for the real Key Policy: a PATCH that
                        # does not carry `aliases` is reported as a success, but the
                        # stored rights are rolled back to the previous state.
                        merged["models"] = key["models"]
                    STATE["keys"][i] = merged
                    return self._send(200, {})
        self._send(404, {})

    def log_message(self, *args):
        pass


def fail(message):
    print("FAIL: " + message, file=sys.stderr)
    sys.exit(1)


def run(url, *args, backup):
    env = {**os.environ, "CPA_MANAGEMENT_KEY": TOKEN}
    done = subprocess.run(
        [sys.executable, "-I", SCRIPT, "--url", url, "--backup-dir", backup, *args],
        capture_output=True, text=True, env=env, timeout=60,
    )
    output = done.stdout + done.stderr
    if TOKEN in output:
        fail("the management token appeared in the script output")
    return done.returncode, output


def main():
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = "http://127.0.0.1:%d" % server.server_address[1]
    backup = tempfile.mkdtemp()
    names = lambda items: [i["alias"] for i in items]  # noqa: E731
    before = copy.deepcopy(STATE)

    # 1. The plan changes nothing.
    code, out = run(url, "--key-name", "[P4]a.duduts", backup=backup)
    if code != 0:
        fail("the plan failed: " + out)
    if STATE != before:
        fail("the plan (no --apply) changed the server")
    if any(method != "GET" for method, _ in CALLS):
        fail("the plan sent a request that is not a read")
    for alias in ("opus-astra-6-2-claude-code", "sonnet-sol-6-2-claude-code",
                  "sonnet-terra-6-1-claude-code", "haiku-luna-6-claude-code"):
        if "+ alias " + alias not in out:
            fail("the plan does not announce the new alias " + alias)
    if os.listdir(backup):
        fail("the plan wrote a backup although it changed nothing")

    # 2. --apply for one key.
    code, out = run(url, "--apply", "--key-name", "[P4]a.duduts", backup=backup)
    if code != 0:
        fail("apply failed: " + out)
    new_aliases = {
        "opus-astra-6-2-claude-code": "gpt-6.2-astra",
        "sonnet-sol-6-2-claude-code": "gpt-6.2-sol",
        "sonnet-terra-6-1-claude-code": "gpt-6.1-terra",
        "haiku-luna-6-claude-code": "gpt-6-luna",
    }
    by_alias = {a["alias"]: a for a in STATE["aliases"]}
    for alias, source in new_aliases.items():
        if alias not in by_alias:
            fail("alias not created: " + alias)
        if by_alias[alias]["targets"] != by_alias[source]["targets"]:
            fail("alias %s does not use the targets of %s" % (alias, source))
    if "sonnet-6-2-sol-cpa" not in by_alias or by_alias["sonnet-6-2-sol-cpa"] != before["aliases"][-1]:
        fail("an existing alias was changed")
    for old in before["aliases"]:
        if by_alias[old["alias"]] != old:
            fail("global alias changed: " + old["alias"])

    k1 = next(k for k in STATE["keys"] if k["id"] == "k1")
    k2 = next(k for k in STATE["keys"] if k["id"] == "k2")
    if k2 != before["keys"][1]:
        fail("another key was changed")
    have = names(k1["models"])
    for old in names(before["keys"][0]["models"]):
        if old not in have:
            fail("the key lost its old model " + old)
    for wanted in ("claude-opus-5-5", *new_aliases):
        if wanted not in have:
            fail("the key did not get " + wanted)
        if wanted not in names(k1["aliases"]):
            fail("the key's `aliases` field does not list " + wanted)
    if set(names(k1["aliases"])) != set(have):
        fail("the key's `aliases` and `models` fields are not consistent")
    if len(have) != len(set(have)):
        fail("the key has duplicate models")
    for field in ("name", "enabled", "rpm", "daily_limit_usd", "weekly_limit_usd", "allow_models_endpoint"):
        if k1[field] != before["keys"][0][field]:
            fail("the key field %s changed" % field)

    backups = os.listdir(backup)
    if len(backups) != 1:
        fail("expected one policy snapshot, found %d" % len(backups))
    mode = stat.S_IMODE(os.stat(os.path.join(backup, backups[0])).st_mode)
    if mode != 0o600:
        fail("the snapshot must be readable only by its owner, mode is %o" % mode)
    snapshot = json.load(open(os.path.join(backup, backups[0]), encoding="utf-8"))
    if snapshot["keys"] != before["keys"] or snapshot["aliases"] != before["aliases"]:
        fail("the snapshot is not the state before the change")

    # 3. A second run changes nothing.
    after_first = copy.deepcopy(STATE)
    patches = [c for c in CALLS if c[0] in ("POST", "PATCH")]
    code, out = run(url, "--apply", "--key-name", "[P4]a.duduts", backup=backup)
    if code != 0:
        fail("the second run failed: " + out)
    if STATE != after_first:
        fail("the second run changed the server")
    if [c for c in CALLS if c[0] in ("POST", "PATCH")] != patches:
        fail("the second run sent writes")

    # 4. Revoking old aliases from one key.
    legacy = "sonnet-6-2-sol-cpa"
    before_revoke = copy.deepcopy(STATE)
    writes = len([c for c in CALLS if c[0] in ("POST", "PATCH")])

    code, out = run(url, "--key-name", "[P4]a.duduts", "--revoke-alias", "claude-opus-5-5", "--apply", backup=backup)
    if code == 0 or "управляемый набор" not in out:
        fail("revoking an alias of the managed set must be refused: " + out)
    code, out = run(url, "--all-keys", "--revoke-alias", legacy, "--apply", backup=backup)
    if code == 0:
        fail("revoking without --key-name (with --all-keys) must be refused")
    code, out = run(url, "--revoke-alias", legacy, "--apply", backup=backup)
    if code == 0:
        fail("revoking without any key must be refused")
    code, out = run(url, "--key-name", "[P4]a.duduts", "--revoke-alias", legacy, backup=backup)
    if code != 0 or "убрать " + legacy not in out:
        fail("the revoke plan failed: " + out)
    if STATE != before_revoke or len([c for c in CALLS if c[0] in ("POST", "PATCH")]) != writes:
        fail("a refused or plan-only revoke changed the server")

    snapshots_before = len(os.listdir(backup))
    code, out = run(url, "--key-name", "[P4]a.duduts", "--revoke-alias", legacy, "--apply", backup=backup)
    if code != 0:
        fail("the revoke failed: " + out)
    k1 = next(k for k in STATE["keys"] if k["id"] == "k1")
    k2 = next(k for k in STATE["keys"] if k["id"] == "k2")
    if legacy in names(k1["models"]) or legacy in names(k1["aliases"]):
        fail("the alias is still on the key (models or aliases)")
    old_k1 = next(k for k in before_revoke["keys"] if k["id"] == "k1")
    if set(names(k1["models"])) != set(names(old_k1["models"])) - {legacy}:
        fail("revoke changed other models of the key")
    if set(names(k1["aliases"])) != set(names(k1["models"])):
        fail("models and aliases of the key are not consistent after the revoke")
    if k2 != next(k for k in before_revoke["keys"] if k["id"] == "k2"):
        fail("revoke changed another key")
    if STATE["aliases"] != before_revoke["aliases"]:
        fail("revoke changed global aliases")
    if len(os.listdir(backup)) != snapshots_before + 1:
        fail("the revoke must save its own snapshot")
    after_revoke = copy.deepcopy(STATE)
    code, out = run(url, "--key-name", "[P4]a.duduts", "--revoke-alias", legacy, "--apply", backup=backup)
    if code != 0 or STATE != after_revoke:
        fail("a second revoke must change nothing: " + out)

    # 5. The revoke read-back catches a change other than the revoked alias.
    k2 = next(k for k in STATE["keys"] if k["id"] == "k2")
    k2["rpm"] = 30
    FAULTS["reset_rpm"] = True
    code, out = run(url, "--key-name", "other-user", "--revoke-alias", legacy, "--apply", backup=backup)
    FAULTS["reset_rpm"] = False
    if code == 0 or "изменилось что-то кроме" not in out:
        fail("the revoke read-back must notice a reset limit: " + out)

    # 6. A wrong token is refused and nothing is written.
    env = {**os.environ, "CPA_MANAGEMENT_KEY": "wrong-token"}
    done = subprocess.run([sys.executable, "-I", SCRIPT, "--url", url, "--key-name", "x"],
                          capture_output=True, text=True, env=env, timeout=60)
    if done.returncode == 0 or "wrong-token" in done.stdout + done.stderr:
        fail("a wrong token must be refused without echoing it")

    print("sync script tests OK")


if __name__ == "__main__":
    main()
