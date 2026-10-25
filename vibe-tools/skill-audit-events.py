#!/usr/bin/env python3
"""Normalize local usage evidence and project the backward-compatible audit ledger."""
import collections
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile


def main():
    mode, log_dir, work_dir, projects_dir, events_dir, start, end, dry, builtins = sys.argv[1:]
    root, work = Path(log_dir), Path(work_dir)
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(root, 0o700)
    with (root / '.audit.lock').open('a') as lock:
        os.chmod(lock.name, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        if mode == 'status':
            finish_status(root, int(work_dir), dry == '1')
            return
        collect(root, work, Path(projects_dir), Path(events_dir), start, end, dry == '1', set(builtins.split()))


# Helpers follow the execution entrypoint in call order.
def finish_status(root, code, dry):
    target = root / ('run-status.dry.json' if dry else 'run-status.json')
    status = json.loads(target.read_text()) if target.exists() else {}
    status.update(last_run_at=utc_now(), exit_code=code)
    atomic(target, json.dumps(status, ensure_ascii=False) + '\n')


def collect(root, work, projects, dashboard, start, end, dry, builtins):
    ledger = root / 'ledger.tsv'
    legacy_path = root / 'legacy-ledger.tsv'
    journal_path = root / 'usage-events.jsonl'
    legacy = legacy_path.read_text() if legacy_path.exists() else (ledger.read_text() if ledger.exists() else '')
    journal = list(read_jsonl(journal_path)) if journal_path.exists() else []
    import_start = next((e['import_start'] for e in journal if e.get('record') == 'import'), start)
    if not journal:
        journal = [{'record': 'import', 'import_start': import_start}]
    known = {e['id']: e for e in journal if isinstance(e.get('id'), str)}
    before = set(known)
    lower, upper = timestamp(import_start), timestamp(end)
    invalid = 0
    source_specs = [('claude_transcripts', 'claude', projects), ('dashboard_events', 'common', dashboard)]
    files = {name: list(path.rglob('*.jsonl')) if path.is_dir() else [] for name, _, path in source_specs}
    # Common events first: their native IDs merge with equivalent transcript evidence.
    for file in files['dashboard_events']:
        for payload in read_jsonl(file):
            if payload.get('event') != 'skill':
                continue
            normalized = common_event(payload)
            if normalized:
                accept(normalized, known, lower, upper)
            else:
                invalid += 1
    for file in files['claude_transcripts']:
        for line_no, payload in enumerate(read_jsonl(file)):
            for normalized in transcript_events(payload, file.parent.name, builtins, f'{file}:{line_no}'):
                accept(normalized, known, lower, upper)
    new = [e for key, e in known.items() if key not in before]
    all_events = sorted(known.values(), key=lambda e: (e['ts'], e['id']))
    usage = collections.Counter((e['type'], e['name']) for e in new if e['action'] == 'use')
    by_project = collections.Counter((e['project'], e['type'], e['name']) for e in new if e['action'] == 'use')
    atomic(work / 'usage_global.tsv', ''.join(f'{kind}\t{name}\t{count}\n' for (kind, name), count in usage.most_common()))
    atomic(work / 'usage_by_project.tsv', ''.join(f'{proj}\t{kind}\t{name}\t{count}\n' for (proj, kind, name), count in sorted(by_project.items())))
    projection = legacy
    if projection and not projection.endswith('\n'):
        projection += '\n'
    counts = collections.Counter((e['date'], e['type'], e['name']) for e in all_events if e['action'] == 'use')
    projection += ''.join(f'{day}\t{kind}\t{name}\t{count}\n' for (day, kind, name), count in sorted(counts.items()))
    if not dry:
        if not legacy_path.exists():
            atomic(legacy_path, legacy)
        # Commit evidence before projection. A retry deterministically repairs projection.
        atomic(journal_path, ''.join(json.dumps(e, ensure_ascii=False) + '\n' for e in [journal[0], *all_events]))
        atomic(ledger, projection)
        atomic(root / 'watermark', end + '\n')
    atomic(work / 'ledger_effective.tsv', projection)
    uses = [e['ts'] for e in all_events if e['action'] == 'use']
    status = {
        'schema_version': 1, 'last_run_at': utc_now(), 'exit_code': None,
        'last_usage_at': max(uses) if uses else None,
        'last_ledger_date': max((line.split('\t')[0] for line in projection.splitlines() if line), default=None),
        'sources': [{'name': name, 'harness': harness, 'status': 'available' if path.is_dir() else 'missing', 'path': str(path)} for name, harness, path in source_specs],
        'supported_harnesses': ['claude', 'codex', 'unknown'],
        'codex_explicit_use': 'unsupported_without_native_evidence',
        'instruction_read_count': sum(e['action'] == 'instruction_read' for e in all_events),
        'invalid_skill_events': invalid, 'new_explicit_uses': sum(usage.values()),
        'transcript_files': len(files['claude_transcripts']),
        'legacy_harness': 'unknown', 'date_basis': 'event_local_date; legacy_rows_unchanged',
    }
    atomic(root / ('run-status.dry.json' if dry else 'run-status.json'), json.dumps(status, ensure_ascii=False) + '\n')


def read_jsonl(path):
    with path.open(errors='replace') as stream:
        for line in stream:
            try:
                value = json.loads(line)
                if isinstance(value, dict):
                    yield value
            except (ValueError, TypeError):
                continue


def common_event(event):
    action = event.get('action')
    harness = event.get('harness', 'unknown')
    name = event.get('skill')
    if action not in {'use', 'instruction_read'} or harness not in {'claude', 'codex', 'unknown'} or not clean_name(name):
        return None
    sid = safe_string(event.get('session_id') or event.get('sid'))
    tool_id = safe_string(event.get('tool_use_id'))
    event_id = safe_string(event.get('event_id'))
    # Native IDs allow transcript/common dedup; no time/name heuristic.
    if tool_id and sid:
        key = [harness, sid, tool_id, action, 'skill', name]
    elif event_id:
        key = [harness, 'dashboard', event_id, action, name]
    else:
        return None
    record = normalized_event(key, event.get('ts'), harness, 'dashboard_events', action, 'skill', name, event.get('cwd'), sid, tool_id)
    if record is not None and event_id:
        record['source_event_id'] = event_id
    return record


def transcript_events(event, project, builtins, location):
    content = (event.get('message') or {}).get('content') if isinstance(event.get('message'), dict) else None
    sid = safe_string(event.get('sessionId') or event.get('session_id'))
    stamp = event.get('timestamp')
    if isinstance(content, list):
        for block_no, block in enumerate(content):
            if not isinstance(block, dict) or block.get('type') != 'tool_use':
                continue
            data = block.get('input') or {}
            if not isinstance(data, dict):
                continue
            tool = block.get('name')
            if tool == 'Skill':
                kind, name = 'skill', data.get('skill')
            elif tool == 'Agent' or tool == 'Task' and data.get('subagent_type'):
                kind, name = 'agent', data.get('subagent_type', 'general-purpose')
            else:
                continue
            if not clean_name(name):
                continue
            native_id = safe_string(block.get('id'))
            if native_id:
                key = ['claude', sid, native_id, 'use', kind, name]
            else:
                # Exact source event fingerprint, never infer another producer's identity.
                key = ['claude', 'transcript', location, block_no]
            yield normalized_event(key, stamp, 'claude', 'claude_transcripts', 'use', kind, name, event.get('cwd') or project, sid, native_id)
    elif isinstance(content, str) and event.get('type') == 'user' and not event.get('isSidechain'):
        match = re.match(r'^\s*(?:<command-message>[^<]*</command-message>\s*)?<command-name>/([^<\s]+)</command-name>', content)
        if match and clean_name(match[1]) and match[1] not in builtins:
            key = ['claude', 'command', sid, event.get('uuid') or location, stamp, match[1]]
            yield normalized_event(key, stamp, 'claude', 'claude_transcripts', 'use', 'command', match[1], event.get('cwd') or project, sid, '')


def accept(event, known, lower, upper):
    if event is None:
        return
    stamp = timestamp(event['ts'])
    if lower < stamp <= upper and event['id'] not in known:
        known[event['id']] = event


def normalized_event(key, stamp, harness, source, action, kind, name, project, sid, tool_id):
    try:
        moment = timestamp(stamp)
    except (ValueError, TypeError):
        return None
    return {'id': hashlib.sha256(json.dumps(key, ensure_ascii=False).encode()).hexdigest(),
            'ts': moment.isoformat(timespec='milliseconds').replace('+00:00', 'Z'),
            'date': moment.astimezone().date().isoformat(), 'harness': harness, 'source': source,
            'action': action, 'type': kind, 'name': name, 'project': safe_string(project),
            'session_id': sid, 'tool_use_id': tool_id}


def timestamp(value):
    if not isinstance(value, str):
        raise ValueError('timestamp requires ISO string')
    moment = dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
    if moment.tzinfo is None:
        raise ValueError('timestamp requires timezone')
    return moment.astimezone(dt.timezone.utc)


def clean_name(value):
    return isinstance(value, str) and bool(value) and len(value) <= 256 and not any(c in value for c in '\t\r\n')


def safe_string(value):
    return value if isinstance(value, str) and len(value) <= 4096 and not any(c in value for c in '\t\r\n') else ''


def utc_now():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')


def atomic(path, content):
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == '__main__':
    main()
