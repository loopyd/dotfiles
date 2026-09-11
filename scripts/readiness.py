#!/usr/bin/env python3
import argparse
from pathlib import Path
import subprocess
import sys
import time


def probes(component):
    helpers = Path.home() / '.local/lib/dotfiles'
    commands = [
        ['/usr/bin/systemctl', 'is-active', '--quiet', 'docker.service'],
        ['/usr/bin/docker', 'info', '--format', '{{.ServerVersion}}'],
    ]
    if component == 'router':
        commands.extend([
            ['/usr/bin/systemctl', '--user', 'is-active', '--quiet', 'easyllama.service'],
            ['/usr/bin/python3', str(helpers / 'tailscale.py'), 'check'],
        ])
    elif component == 'hindsight':
        commands.extend([
            ['/usr/bin/systemctl', '--user', 'is-active', '--quiet', 'hindsight-db.service'],
            ['/usr/bin/systemctl', '--user', 'is-active', '--quiet', '9router.service'],
            ['/usr/bin/docker', 'exec', 'hindsight-db', 'pg_isready', '-q', '-U', 'postgres', '-d', 'hindsight'],
            ['/usr/bin/python3', str(helpers / 'router.py'), 'health'],
        ])
    return commands


def wait(component, timeout):
    deadline = time.monotonic() + timeout
    commands = probes(component)
    print('Waiting for ' + component + ' prerequisites', flush=True)
    while time.monotonic() < deadline:
        ready = True
        for command in commands:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                ready = False
                break
            try:
                result = subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                        timeout=min(10, remaining), check=False)
                ready = result.returncode == 0
            except (OSError, subprocess.TimeoutExpired):
                ready = False
            if not ready:
                break
        if ready:
            print(component + ' prerequisites ready')
            return
        time.sleep(min(2, max(0, deadline - time.monotonic())))
    raise TimeoutError(component + ' prerequisites unavailable; service restart will retry')


def main():
    parser = argparse.ArgumentParser(description='Wait for fixed local service prerequisites without changing services')
    parser.add_argument('action', choices=['wait'])
    parser.add_argument('component', choices=['docker', 'router', 'hindsight'])
    parser.add_argument('--timeout', type=int, default=180)
    args = parser.parse_args()
    if not 1 <= args.timeout <= 600:
        parser.error('Timeout must be between 1 and 600 seconds')
    try:
        wait(args.component, args.timeout)
    except TimeoutError as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
