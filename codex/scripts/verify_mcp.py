#!/usr/bin/env python3
"""Exercise the configured stdio MCP server without an LLM or third-party SDK."""
import argparse
from collections import deque
import json
import os
import queue
import signal
import subprocess
import sys
import threading
import time


def verify(expected_url, query):
    config = json.loads(subprocess.check_output(
        ['codex', 'mcp', 'get', 'searxng', '--json'], text=True, timeout=15))
    if not config.get('enabled', True):
        raise RuntimeError('searxng is disabled in Codex')
    transport = config['transport']
    if transport['type'] != 'stdio':
        raise RuntimeError('This recipe expects a stdio server')
    env = os.environ.copy()
    env.update(transport.get('env') or {})
    if env.get('SEARXNG_URL') != expected_url:
        raise RuntimeError('Configured SEARXNG_URL differs from SEARXNG_PORT')
    if env.get('MCP_HTTP_PORT'):
        raise RuntimeError('MCP_HTTP_PORT must be unset/empty for stdio')
    proc = subprocess.Popen(
        [transport['command'], *transport.get('args', [])],
        cwd=transport.get('cwd'), env=env, stdin=subprocess.PIPE,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        bufsize=1, start_new_session=True)
    messages = queue.Queue()
    diagnostics = deque(maxlen=20)

    def read_stdout():
        for line in proc.stdout:
            messages.put(line)
        messages.put(None)

    def read_stderr():
        for line in proc.stderr:
            diagnostics.append(line.rstrip())

    threading.Thread(target=read_stdout, daemon=True).start()
    threading.Thread(target=read_stderr, daemon=True).start()

    def send(message):
        proc.stdin.write(json.dumps({'jsonrpc': '2.0', **message}) + '\n')
        proc.stdin.flush()

    request_id = 0

    def request(method, params):
        nonlocal request_id
        request_id += 1
        send({'id': request_id, 'method': method, 'params': params})
        deadline = time.monotonic() + 60
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f'{method} timed out')
            try:
                line = messages.get(timeout=remaining)
            except queue.Empty:
                raise TimeoutError(f'{method} timed out') from None
            if line is None:
                raise RuntimeError('MCP process closed stdout: ' + '\n'.join(diagnostics))
            response = json.loads(line)
            if 'method' in response:
                # Notifications have no id. Answer optional server requests explicitly.
                if 'id' in response:
                    if response['method'] == 'ping':
                        send({'id': response['id'], 'result': {}})
                    else:
                        send({'id': response['id'], 'error': {
                            'code': -32601, 'message': 'Unsupported client method'}})
                continue
            if response.get('id') != request_id:
                continue
            if 'error' in response:
                raise RuntimeError(f'{method}: {response["error"]}')
            return response['result']

    try:
        init = request('initialize', {
            'protocolVersion': '2024-11-05', 'capabilities': {},
            'clientInfo': {'name': 'searxng-agent-recipes-verify', 'version': '1.0.0'}})
        send({'method': 'notifications/initialized'})
        info = init.get('serverInfo', {})
        print(f'[ok] MCP initialize: {info.get("name")} {info.get("version")}')
        tools = request('tools/list', {})['tools']
        names = {tool['name'] for tool in tools}
        required = {'searxng_web_search', 'web_url_read',
                    'searxng_search_suggestions', 'searxng_instance_info'}
        if not required <= names:
            raise RuntimeError(f'Missing MCP tools: {sorted(required - names)}')
        print('[ok] MCP tools/list: ' + ', '.join(sorted(names)))
        result = request('tools/call', {
            'name': 'searxng_web_search',
            'arguments': {'query': query, 'num_results': 3, 'response_format': 'json'}})
        text = '\n'.join(item.get('text', '') for item in result.get('content', [])
                         if item.get('type') == 'text')
        if result.get('isError'):
            raise RuntimeError('Search tool failed: ' + text)
        data = json.loads(text)
        results = data.get('results', [])
        if not results or not any(item.get('url') for item in results):
            raise RuntimeError('Search returned no source URLs. Check engines/network in docker logs searxng')
        print(f'[ok] MCP tools/call: {len(results)} search results for {query!r}')
        for item in results:
            print('  ' + item.get('url', ''))
    finally:
        proc.stdin.close()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-url', default='http://127.0.0.1:8888')
    parser.add_argument('--query', default='SearXNG documentation')
    args = parser.parse_args()
    try:
        verify(args.expected_url, args.query)
    except (OSError, ValueError, KeyError, RuntimeError, AssertionError,
            subprocess.SubprocessError) as exc:
        print(f'[FAIL] {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
