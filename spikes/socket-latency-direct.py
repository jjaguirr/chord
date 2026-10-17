#!/usr/bin/env python3
"""C6 spike 6b: AeroSpace request latency over its Unix socket, no process spawn per request.

Wire format, read from AeroSpace 0.20.3-Beta (6dde91ba) Sources/AppBundle/server.swift
and Sources/Cli/_main.swift:
  socket  /tmp/bobko.aerospace-<USER>.sock (AF_UNIX, SOCK_STREAM)
  request one bare JSON object, no length prefix:
          {"args":[...],"stdin":"","windowId":null,"workspace":null}
  answer  one bare JSON object: {"exitCode","stdout","stderr","serverVersionAndHash"}
  the server loops per connection, so one connection serves many requests.
Newer releases (0.21+) add a handshake and length prefix; this probe targets the
installed 0.20.3 framing and reports FAIL on any answer it cannot parse.
Read-only query only: list-windows. Never enables, disables, or mutates AeroSpace.
"""
import getpass
import json
import math
import socket
import sys
import time

THRESHOLD_MS = 16.67
SAMPLES = 100
ARGS = ["list-windows", "--all", "--format", "%{window-id}"]
PATH = "/tmp/bobko.aerospace-%s.sock" % getpass.getuser()
TIMEOUT_S = 5.0


def fail(why, remedy):
    print("FAIL: %s; threshold p95 <= %sms over %d samples; fail path: %s" % (why, THRESHOLD_MS, SAMPLES, remedy))
    sys.exit(1)


def request(sock):
    """Send one query and return the decoded ServerAnswer."""
    payload = json.dumps({"args": ARGS, "stdin": "", "windowId": None, "workspace": None}).encode()
    sock.sendall(payload)
    data = b""
    decoder = json.JSONDecoder()
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            raise ConnectionError("server closed the connection")
        data += chunk
        try:
            ans, _ = decoder.raw_decode(data.decode("utf-8"))
            return ans
        except ValueError:
            continue  # partial answer; keep reading


def main():
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(TIMEOUT_S)
    try:
        sock.connect(PATH)
    except OSError as e:
        fail("cannot connect to %s (%s)" % (PATH, e), "start AeroSpace.app (pinned version) and rerun")
    try:
        ans = request(sock)  # uncounted preflight
    except (OSError, ValueError) as e:
        fail("preflight request failed (%s)" % e, "check server/protocol version matches 0.20.3-Beta framing")
    if not isinstance(ans, dict) or ans.get("exitCode") != 0:
        err = (ans.get("stderr", "") if isinstance(ans, dict) else str(ans)).strip().splitlines()
        why = "server rejected query: %s" % (err[0] if err else "unknown")
        remedy = "run 'aerospace enable on' (alters machine-level behavior; captain decision) then rerun" \
            if "disabled" in why else "inspect server/socket configuration"
        fail(why, remedy)

    lat = []
    for _ in range(SAMPLES):
        start = time.monotonic()
        try:
            ans = request(sock)
        except (OSError, ValueError) as e:
            fail("request failed mid-run (%s)" % e, "inspect server/socket configuration")
        lat.append((time.monotonic() - start) * 1000.0)
        if not isinstance(ans, dict) or ans.get("exitCode") != 0:
            fail("server returned a non-success answer mid-run (%s)" % (ans.get("exitCode") if isinstance(ans, dict) else ans), "inspect server state")
    lat.sort()
    p95 = lat[math.ceil(SAMPLES * 0.95) - 1]
    if p95 <= THRESHOLD_MS:
        print("PASS: direct-socket p95 %.3fms <= %sms over %d samples (min %.3f, max %.3f)" % (p95, THRESHOLD_MS, SAMPLES, lat[0], lat[-1]))
        sys.exit(0)
    fail("direct-socket p95 %.3fms > %sms (min %.3f, max %.3f)" % (p95, THRESHOLD_MS, lat[0], lat[-1]),
         "server-side latency exceeds budget; investigate AeroSpace main-thread load or move reads off the socket")


if __name__ == "__main__":
    main()
