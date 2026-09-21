import argparse
import concurrent.futures
import hashlib
import json
import os
import statistics
import subprocess
import time
from pathlib import Path
from urllib.parse import urlsplit

from aether_app_protocol import AppClient

ROOT = Path(__file__).resolve().parents[1]
PROBE = Path(__file__).with_name('aether_page_probe.js').read_text()
SITES = [
    'https://www.see-for-yourself.com/', 'https://www.dontlookup.app/',
    'https://wisprflow.ai/', 'https://tryclico.com/', 'https://www.boonglobal.io/',
    'https://www.moremedia.at/', 'https://www.corndel.com/',
    'https://www.podiumautomation.com/', 'https://usealia.com/', 'https://calendly.com/',
    'https://www.clay.com/', 'https://www.apollo.io/', 'https://instantly.ai/',
    'https://eatsnackish.com/', 'https://playfolly.com/', 'https://www.lyleandscott.com/',
    'https://land-book.com/', 'https://www.awwwards.com/', 'https://openai.com/codex/',
    'https://www.trysapphire.today/',
]


def run(command):
    return subprocess.run(command, text=True, capture_output=True, timeout=15, check=True).stdout.strip()


def key(value, modifiers='command down'):
    run(['osascript', '-e', 'tell application "System Events" to tell process "AetherApp"\n'
         'set frontmost to true\n' + f'keystroke {json.dumps(value)} using {{{modifiers}}}\nend tell'])


def host(url):
    return (urlsplit(url).hostname or '').lower().removeprefix('www.')


def matches(state, url):
    actual = host(state.get('url', ''))
    expected = host(url)
    return actual == expected or actual.endswith('.' + expected)


def title_ready(state, url):
    title = state.get('title', '').strip().lower()
    placeholders = {'', 'untitled', 'new tab', 'about:blank', host(url), host(state.get('url', ''))}
    return matches(state, url) and title not in placeholders and not title.startswith(('http:', 'https:'))


def pages(client, context):
    return client.call('page.list', context=context)


def app_pid():
    value = run(['pgrep', '-f', str(ROOT / '.build/Aether.app/Contents/MacOS/AetherApp')])
    ids = value.splitlines()
    if len(ids) != 1:
        raise RuntimeError(f'Expected one app, found {len(ids)}')
    return int(ids[0])


def open_tab(client, context, url):
    before = {p['id'] for p in pages(client, context)}
    started = time.perf_counter()
    run(['open', '-a', str(ROOT / '.build/Aether.app'), url])
    deadline = started + 15
    while time.perf_counter() < deadline:
        created = [p for p in pages(client, context) if p['id'] not in before]
        if len(created) == 1:
            return {'page': created[0]['id'], 'url': url, 'started': started,
                    'dispatch_ms': round((time.perf_counter() - started) * 1000, 2)}
        if len(created) > 1:
            raise RuntimeError('Multiple pages created; user activity or window duplication')
        time.sleep(.1)
    raise RuntimeError('UI did not create an engine page within 15 seconds')


def observe(client, item, timeout):
    row = {k: v for k, v in item.items() if k != 'started'}
    row.update(status='TIMEOUT', observed_title_ms=None, observed_complete_ms=None)
    deadline = item['started'] + timeout
    errors = []
    state = {}
    while time.perf_counter() < deadline:
        try:
            state = client.evaluate(item['page'], PROBE)
            elapsed = round((time.perf_counter() - item['started']) * 1000, 2)
            if title_ready(state, item['url']) and row['observed_title_ms'] is None:
                row['observed_title_ms'] = elapsed
            if matches(state, item['url']) and state['challenge']:
                row['status'] = 'CHALLENGE'
                break
            if matches(state, item['url']) and state['readyState'] == 'complete':
                row['observed_complete_ms'] = elapsed
                if state['textLength'] >= 80 and state['elements'] >= 10:
                    row['status'] = 'CONTENT_LOADED'
                    break
        except (RuntimeError, OSError, ValueError) as error:
            if len(errors) < 8:
                errors.append(str(error))
        time.sleep(.2)
    row['initial_state'] = state
    row['probe_errors'] = errors
    row['observation_elapsed_ms'] = round((time.perf_counter() - item['started']) * 1000, 2)
    return row


def inspect_visible(client, row, destination):
    deadline = time.perf_counter() + 8
    state = {}
    while time.perf_counter() < deadline:
        state = client.evaluate(row['page'], PROBE)
        if state['visibility'] == 'visible' and state['fonts'] == 'loaded' and state['pendingVisibleImages'] == 0:
            break
        time.sleep(.2)
    row['final_state'] = state
    row['foreground_verified'] = state.get('visibility') == 'visible'
    issues = []
    if not row['foreground_verified']:
        issues.append('not_foreground')
    if state.get('missingStylesheets'):
        issues.append('missing_stylesheets')
    if state.get('brokenImages'):
        issues.append('broken_images')
    if state.get('pendingVisibleImages'):
        issues.append('pending_visible_images')
    if state.get('fonts') != 'loaded':
        issues.append('pending_fonts')
    if not matches(state, row['url']):
        issues.append('unexpected_redirect')
    if row['status'] == 'CONTENT_LOADED':
        row['status'] = 'PASS' if not issues else 'RENDER_ISSUES'
    row['issues'] = issues
    if row['foreground_verified']:
        before = client.evaluate(row['page'], 'JSON.stringify({y:scrollY,max:document.documentElement.scrollHeight-innerHeight})')
        client.evaluate(row['page'], 'JSON.stringify((scrollTo(0,Math.min(600,document.documentElement.scrollHeight-innerHeight)),true))')
        time.sleep(.3)
        after = client.evaluate(row['page'], 'JSON.stringify({y:scrollY})')
        row['scroll_verified'] = before['max'] <= 0 or after['y'] > 0
        client.evaluate(row['page'], 'JSON.stringify((scrollTo(0,0),true))')
        time.sleep(.2)
        sandbox_path = client.directory / destination.name
        client.call('page.render', page=row['page'], path=str(sandbox_path))
        destination.write_bytes(sandbox_path.read_bytes())
        sandbox_path.unlink()
        row['screenshot'] = destination.name
        row['screenshot_bytes'] = destination.stat().st_size
    return row


def distribution(values):
    values = sorted(x for x in values if x is not None)
    if not values:
        return None
    import math
    return {'n': len(values), 'median_ms': round(statistics.median(values), 2),
            'p95_ms': round(values[math.ceil(.95 * len(values)) - 1], 2), 'max_ms': round(max(values), 2)}


def save(output, metadata, results):
    summary = {}
    for mode in sorted({r['mode'] for r in results}):
        rows = [r for r in results if r['mode'] == mode]
        summary[mode] = {
            'attempts': len(rows), 'status_counts': {s: sum(r['status'] == s for r in rows) for s in sorted({r['status'] for r in rows})},
            'observed_title': distribution([r.get('observed_title_ms') for r in rows]),
            'observed_complete': distribution([r.get('observed_complete_ms') for r in rows]),
            'navigation_load': distribution([(r.get('final_state', {}).get('navigation') or {}).get('load') or None for r in rows]),
            'fcp': distribution([next((p['startTime'] for p in r.get('final_state', {}).get('paint', []) if p['name'] == 'first-contentful-paint'), None) for r in rows]),
        }
    temp = output.with_suffix('.tmp')
    temp.write_text(json.dumps({'metadata': metadata, 'summary': summary, 'results': results}, indent=2))
    temp.replace(output)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', type=Path, default=Path.home() / 'Library/Containers/dev.aether.browser/Data/tmp/aether-agent')
    parser.add_argument('--output', type=Path, default=ROOT / 'agents/codex/visible-webkit/results/app-benchmark.json')
    parser.add_argument('--trials', type=int, default=2)
    parser.add_argument('--concurrency', type=int, default=4)
    parser.add_argument('--timeout', type=float, default=60)
    parser.add_argument('--only', nargs='*')
    parser.add_argument('--modes', nargs='+', choices=['sequential','concurrent'], default=['sequential','concurrent'])
    args = parser.parse_args()
    if args.trials < 1 or not 1 <= args.concurrency <= 8 or args.timeout <= 0:
        parser.error('Positive trials/timeout and concurrency 1–8 required')
    client = AppClient(args.directory)
    contexts = client.call('context.list')
    if len(contexts) != 1:
        raise RuntimeError('Enable exactly one benchmark profile')
    context = contexts[0]['id']
    pid = app_pid()
    initial_pages = {p['id'] for p in pages(client, context)}
    chosen = args.only or SITES
    metadata = {'pid': pid, 'started_at': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
                'os': run(['sw_vers']), 'binary_sha256': hashlib.sha256((ROOT / '.build/Aether.app/Contents/MacOS/AetherApp').read_bytes()).hexdigest(),
                'sites': chosen, 'trials': args.trials, 'concurrency': args.concurrency,
                'scope': 'Visible Aether.app; UI URL opening; warm existing profile; no daemon; no cache clearing; title is not rendering completion',
                'initial_page_ids': sorted(initial_pages)}
    results = []
    args.output.parent.mkdir(parents=True, exist_ok=True)
    try:
        for mode in args.modes:
            width = 1 if mode == 'sequential' else args.concurrency
            for trial in range(1, args.trials + 1):
                order = chosen if trial % 2 else list(reversed(chosen))
                for offset in range(0, len(order), width):
                    if app_pid() != pid:
                        raise RuntimeError('App exited or restarted; aborting without hidden restart')
                    items = []
                    with concurrent.futures.ThreadPoolExecutor(max_workers=width) as pool:
                        futures = []
                        for url in order[offset:offset + width]:
                            item = open_tab(client, context, url)
                            items.append(item)
                            futures.append(pool.submit(observe, client, item, args.timeout))
                        rows = [f.result() for f in futures]
                    for row in reversed(rows):
                        row.update(mode=mode, trial=trial)
                        filename = f'{mode}-{trial}-{chosen.index(row["url"]) + 1:02d}.png'
                        try:
                            inspect_visible(client, row, args.output.parent / filename)
                        except (RuntimeError, OSError, ValueError) as error:
                            row['verification_error'] = str(error)
                            row['status'] = 'VERIFICATION_ERROR'
                        results.append(row)
                        print(f'{mode} {trial} {row["status"]} {row.get("observed_complete_ms")}ms {row["url"]}', flush=True)
                        save(args.output, metadata, results)
                        if not row.get('foreground_verified'):
                            raise RuntimeError('Selected tab mismatch; refusing to close an unverified tab')
                        key('w')
                        deadline = time.perf_counter() + 5
                        while time.perf_counter() < deadline and row['page'] in {p['id'] for p in pages(client, context)}:
                            time.sleep(.1)
                        if row['page'] in {p['id'] for p in pages(client, context)}:
                            raise RuntimeError('UI tab close did not remove its runtime page')
        metadata['finished_at'] = time.strftime('%Y-%m-%dT%H:%M:%S%z')
        metadata['final_pid'] = app_pid()
        metadata['final_page_ids'] = [p['id'] for p in pages(client, context)]
        metadata['cleanup_verified'] = set(metadata['final_page_ids']) == initial_pages
    except BaseException as error:
        metadata['aborted'] = str(error)
        raise
    finally:
        save(args.output, metadata, results)


if __name__ == '__main__':
    main()
