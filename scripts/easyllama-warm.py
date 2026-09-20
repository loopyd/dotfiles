#!/usr/bin/env python3
"""Keep the published EasyLlama search backends awake.

Models marked ``publish: true`` get their lifecycle port bound to host loopback
(embeddings 9010, reranker 9011). Their ``POST /run`` blocks for as long as the
model runs, so holding that request keeps the model loaded even though nothing
routes it through the swap proxy — which is what Hindsight's direct embedding and
rerank calls need. Re-issue the request whenever it returns.
"""

from __future__ import annotations

import os
import threading
import time
from urllib.request import Request, urlopen

DEFAULT_PORTS = (9010, 9011)
STOP = threading.Event()


def configured_ports() -> tuple[int, ...]:
    """Return the lifecycle ports to keep awake."""
    raw = os.environ.get('EASYLLAMA_WARM_PORTS', '').strip()
    if not raw:
        return DEFAULT_PORTS
    return tuple(int(item) for item in raw.split(',') if item.strip())


def hold(port: int) -> None:
    """Hold one backend awake until the unit stops."""
    while not STOP.is_set():
        try:
            urlopen(Request(f'http://127.0.0.1:{port}/run', method='POST'), timeout=3600)
        except Exception:
            pass
        STOP.wait(5)


def main() -> int:
    """Start one holder per configured port and idle in the foreground."""
    ports = configured_ports()
    for port in ports:
        threading.Thread(target=hold, args=(port,), daemon=True).start()
    print('easyllama-warm: holding ports ' + ', '.join(str(port) for port in ports), flush=True)
    while not STOP.wait(300):
        pass
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
