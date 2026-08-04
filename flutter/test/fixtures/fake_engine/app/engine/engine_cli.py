"""Fake engine_cli.py — hermetic stand-in for app/engine/engine_cli.py used by
EngineClient unit tests (flutter/test/engine_client_test.dart).

EngineClient always spawns `python -m app.engine.engine_cli <subcommand>` with
its working directory set, so this fixture lives at
test/fixtures/fake_engine/app/engine/engine_cli.py and the tests pass
`cwd: <fixture root>` to EngineClient.

Behaviour is driven entirely by environment variables (passed via the
EngineClient `environment` parameter):

  FAKE_ENGINE_EVENTS   JSON array of event objects, emitted one per line.
  FAKE_ENGINE_EXIT     Exit code for the process (default 0).
  FAKE_ENGINE_BAD_LINE When "1", a non-JSON line is printed before the events
                       (the client must surface it as an error event, not crash).
  FAKE_ENGINE_SLEEP    Seconds to sleep after emitting events (lets tests
                       exercise cancel() mid-run).

The request on stdin is read and validated like the real engine; a malformed
request yields an error event and exit code 1.
"""

import json
import os
import sys
import time


def main() -> int:
    events = json.loads(os.environ.get("FAKE_ENGINE_EVENTS", "[]"))
    exit_code = int(os.environ.get("FAKE_ENGINE_EXIT", "0"))
    sleep = float(os.environ.get("FAKE_ENGINE_SLEEP", "0"))

    raw = sys.stdin.read()
    try:
        json.loads(raw or "{}")
    except json.JSONDecodeError as exc:
        print(json.dumps({"type": "error", "message": f"Malformed JSON request: {exc}"}))
        return 1

    if os.environ.get("FAKE_ENGINE_BAD_LINE") == "1":
        print("this is not json", flush=True)

    for event in events:
        print(json.dumps(event, separators=(",", ":")), flush=True)

    if sleep > 0:
        time.sleep(sleep)

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
