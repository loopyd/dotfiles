#!/usr/bin/env python3
"""Latch or stop the native EasyLlama stack for the systemd unit.

The stack's own ``run.sh`` owns creation/removal, while this helper makes the
user unit a first-class owner of an *already-running* stack:

* ``latch``   adopts a running orchestrator container without recreating it, or
              starts the stack through ``run.sh start``; it then holds the
              foreground on the orchestrator so the unit stays active while the
              stack runs (and exits non-zero if the stack dies on its own).
* ``stop``    delegates to ``run.sh stop`` (idempotent).
* ``status``  reports the orchestrator container state.

``run.sh start|stop|restart`` remains usable directly; the latch is compatible
with containers it started.
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from urllib.request import urlopen

ORCHESTRATOR = 'easyllama-server-swap'
PROXY_HEALTH = 'http://127.0.0.1:8080/health'


def root() -> Path:
    """Return the EasyLlama checkout that owns ``run.sh``."""
    value = os.environ.get('EASYLLAMA_ROOT', '').strip()
    if not value:
        raise SystemExit('EASYLLAMA_ROOT must point at the EasyLlama checkout')
    path = Path(value).resolve()
    if not (path / 'run.sh').is_file():
        raise SystemExit(f'run.sh not found under {path}')
    return path


def run_script(*arguments: str) -> subprocess.CompletedProcess[str]:
    """Run the stack's own lifecycle script from its checkout."""
    return subprocess.run([str(root() / 'run.sh'), *arguments], cwd=root(), text=True)


def inspect(name: str = ORCHESTRATOR) -> dict | None:
    """Return the orchestrator container metadata, or ``None`` when absent."""
    result = subprocess.run(['docker', 'inspect', name], capture_output=True, text=True)
    if result.returncode:
        return None
    return json.loads(result.stdout)[0]


def running(name: str = ORCHESTRATOR) -> bool:
    """Return whether the orchestrator container is running."""
    container = inspect(name)
    return bool(container and container['State'].get('Running'))


def healthy(timeout: float = 1800.0) -> bool:
    """Wait until the published proxy answers its health endpoint."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with urlopen(PROXY_HEALTH, timeout=5) as response:
                if response.status == 200:
                    return True
        except Exception:
            pass
        time.sleep(2)
    return False


def ensure() -> None:
    """Adopt a running stack, or start it, and wait for the proxy."""
    if running():
        print('latching onto the running EasyLlama stack', flush=True)
        return
    print('starting the EasyLlama stack via run.sh', flush=True)
    if run_script('start').returncode:
        raise SystemExit('run.sh start failed')
    if not healthy():
        raise SystemExit('EasyLlama proxy did not become healthy')


def latch() -> int:
    """Hold the foreground on the orchestrator until the unit is stopped."""
    ensure()
    stopping = threading.Event()

    def handler(_signum: int, _frame: object) -> None:
        stopping.set()

    signal.signal(signal.SIGTERM, handler)
    signal.signal(signal.SIGINT, handler)

    def stopper() -> None:
        if stopping.wait():
            run_script('stop')

    threading.Thread(target=stopper, daemon=True).start()
    subprocess.run(['docker', 'start', '--attach', ORCHESTRATOR])
    if stopping.is_set():
        return 0
    raise SystemExit('EasyLlama orchestrator stopped unexpectedly')


def stop() -> int:
    """Stop the stack through ``run.sh`` when it is present."""
    if inspect() is None:
        return 0
    return run_script('stop').returncode


def main() -> int:
    """Dispatch the systemd-facing commands."""
    parser = argparse.ArgumentParser(description='Latch or stop the native EasyLlama stack for systemd')
    parser.add_argument('command', choices=['latch', 'stop', 'status'])
    args = parser.parse_args()
    if args.command == 'latch':
        return latch()
    if args.command == 'stop':
        return stop()
    container = inspect()
    state = container['State'] if container else {}
    print(json.dumps({'orchestrator': ORCHESTRATOR, 'present': container is not None, 'running': bool(state.get('Running'))}))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as error:
        print(f'EasyLlama latch failed: {type(error).__name__}: {error}', file=sys.stderr)
        raise SystemExit(1)
