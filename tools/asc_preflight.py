#!/usr/bin/env python3
"""Checks that an App Store Connect key works, before anything long uses it.

The release workflow spends eight minutes archiving before it ever talks to
Apple, and a key Apple refuses produces `401` from a provisioning call buried a
thousand log lines in, under the heading "Communication with Apple failed" —
which reads like a network fault and is not one. This asks the same question in
two seconds and says which of the three values is wrong.

Reads ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH from the environment; prints
nothing on success beyond a line naming the team, and exits non-zero otherwise.
No third-party modules: a runner has none, and this must not be the step that
needs pip.
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request


def fail(message: str) -> "None":
    print(f"asc-preflight: {message}", file=sys.stderr)
    sys.exit(1)


def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """ECDSA-Sig-Value ::= SEQUENCE { r INTEGER, s INTEGER } -> r||s."""
    if not der or der[0] != 0x30:
        raise ValueError("openssl did not return a DER signature")
    index = 2 if der[1] < 0x80 else 3 + (der[1] & 0x7F) - 1

    def read_int(pos):
        if der[pos] != 0x02:
            raise ValueError("expected an INTEGER in the signature")
        length = der[pos + 1]
        return der[pos + 2:pos + 2 + length].lstrip(b"\x00").rjust(32, b"\x00"), pos + 2 + length

    r, index = read_int(index)
    s, _ = read_int(index)
    return r + s


key_id = (os.environ.get("ASC_KEY_ID") or "").strip()
issuer = (os.environ.get("ASC_ISSUER_ID") or "").strip()
path = (os.environ.get("ASC_KEY_PATH") or "").strip()

if not key_id:
    fail("ASC_KEY_ID is empty.")
if not issuer:
    fail("ASC_ISSUER_ID is empty.")
if not path or not os.path.exists(path):
    fail(f"ASC_KEY_PATH does not name a file: {path!r}")

# The shapes are fixed and the mistakes are ordinary — a pasted value carrying a
# space, or the two identifiers entered into each other's box. Saying so here
# beats letting Apple answer 401 and calling it a network problem.
if len(key_id) != 10:
    fail(f"ASC_KEY_ID should be ten characters, this one is {len(key_id)}. "
         "It is the Key ID column in Users and Access → Integrations.")
if len(issuer) != 36 or issuer.count("-") != 4:
    fail(f"ASC_ISSUER_ID should be a 36-character UUID, this one is {len(issuer)} "
         "characters. It is the Issuer ID shown above the key list, not the key's own id.")

with open(path, "rb") as handle:
    material = handle.read()
if b"BEGIN PRIVATE KEY" not in material:
    fail(f"{path} does not look like a .p8 private key — it holds "
         f"{len(material)} bytes and no PEM header.")

now = int(time.time())
header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
payload = {"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
signing_input = f"{b64(json.dumps(header).encode())}.{b64(json.dumps(payload).encode())}"

signed = subprocess.run(
    ["openssl", "dgst", "-sha256", "-sign", path],
    input=signing_input.encode(), capture_output=True,
)
if signed.returncode != 0:
    fail(f"openssl could not sign with this key: {signed.stderr.decode().strip()[:200]}")

token = f"{signing_input}.{b64(der_to_raw(signed.stdout))}"
request = urllib.request.Request(
    "https://api.appstoreconnect.apple.com/v1/apps?limit=1&fields[apps]=name")
request.add_header("Authorization", f"Bearer {token}")

try:
    with urllib.request.urlopen(request, timeout=30) as response:
        json.load(response)
except urllib.error.HTTPError as error:
    if error.code == 401:
        fail("Apple refused the key (401). The key id, the issuer id and the .p8 "
             "have to belong to one another — re-check all three, and that the key "
             "has not been revoked in Users and Access → Integrations.")
    fail(f"Apple answered {error.code}: {error.read().decode()[:300]}")
except urllib.error.URLError as error:
    fail(f"could not reach App Store Connect: {error.reason}")

print(f"asc-preflight: the key answers for team {os.environ.get('ASC_TEAM_ID', '(unnamed)')}.")
