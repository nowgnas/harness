"""세션 로그에서 토큰 사용량을 집계한다 (Claude Code · Codex). knack usage 와 bench 가 사용한다.

- Claude: ~/.claude/projects/**/*.jsonl 의 assistant 메시지 usage. 스트리밍 블록마다 같은 message.id 가
  반복 기록되므로 id 로 중복을 제거한다. <세션>/subagents/*.jsonl 은 서브에이전트 기록이다.
- Codex: $CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl 의 token_count 이벤트. total_token_usage 는
  누적값이라 마지막 값을 쓰고, input_tokens 에 캐시 적중분이 포함돼 있어 빼서 계산한다.
"""
import json
import os
import re
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path

HOME = Path.home()
CLAUDE_PROJECTS = HOME / ".claude" / "projects"
CODEX_SESSIONS = Path(os.environ.get("CODEX_HOME") or HOME / ".codex") / "sessions"
FIELDS = ("input", "cache_write", "cache_read", "output")
DEFAULT_WEIGHTS = {
    "claude": {"input": 1.0, "cache_write": 1.25, "cache_read": 0.1, "output": 5.0},
    "codex": {"input": 1.0, "cache_write": 1.0, "cache_read": 0.1, "output": 8.0},
}
EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)


def parse_time(value):
    try:
        t = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    return t if t.tzinfo else t.replace(tzinfo=timezone.utc)


def parse_since(value):
    if not value:
        return None
    m = re.fullmatch(r"(\d+)([dh])", value)
    if m:
        unit = timedelta(days=1) if m.group(2) == "d" else timedelta(hours=1)
        return datetime.now(timezone.utc) - int(m.group(1)) * unit
    t = parse_time(value)
    if t is None:
        raise ValueError(f"기간 형식: 7d, 12h, 2026-09-01 ({value})")
    return t


def new_session(agent, path):
    return {"agent": agent, "session": path.stem, "file": str(path), "cwd": "", "start": None, "end": None,
            "models": Counter(), "input": 0, "cache_write": 0, "cache_read": 0, "output": 0, "reasoning": 0,
            "calls": 0, "skills": Counter(), "subagents": Counter(), "subagent": False, "parent": None}


def _touch(s, value):
    t = parse_time(value) if value else None
    if t:
        s["start"] = min(s["start"], t) if s["start"] else t
        s["end"] = max(s["end"], t) if s["end"] else t


def _records(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if isinstance(r, dict):
                yield r


def parse_claude(path):
    path = Path(path)
    s = new_session("claude", path)
    if path.parent.name == "subagents":
        s["subagent"], s["parent"] = True, path.parent.parent.name
    seen = set()
    for r in _records(path):
        _touch(s, r.get("timestamp"))
        s["cwd"] = s["cwd"] or r.get("cwd") or ""
        if r.get("sessionId") and not s["subagent"]:
            s["session"] = r["sessionId"]
        msg = r.get("message") if isinstance(r.get("message"), dict) else {}
        for c in msg.get("content") if isinstance(msg.get("content"), list) else []:
            if isinstance(c, dict) and c.get("type") == "tool_use":
                args = c.get("input") or {}
                if c.get("name") == "Skill" and args.get("skill"):
                    s["skills"][args["skill"]] += 1
                elif c.get("name") in ("Agent", "Task") and args.get("subagent_type"):
                    s["subagents"][args["subagent_type"]] += 1
        usage = msg.get("usage")
        if r.get("type") != "assistant" or not isinstance(usage, dict):
            continue
        key = msg.get("id") or r.get("uuid")
        if key in seen:
            continue
        seen.add(key)
        s["calls"] += 1
        if msg.get("model") and not str(msg["model"]).startswith("<"):
            s["models"][msg["model"]] += 1
        s["input"] += usage.get("input_tokens") or 0
        s["cache_write"] += usage.get("cache_creation_input_tokens") or 0
        s["cache_read"] += usage.get("cache_read_input_tokens") or 0
        s["output"] += usage.get("output_tokens") or 0
    return s


def parse_codex(path):
    path = Path(path)
    s = new_session("codex", path)
    last = None
    for r in _records(path):
        _touch(s, r.get("timestamp"))
        p = r.get("payload") if isinstance(r.get("payload"), dict) else {}
        if r.get("type") == "session_meta":
            s["session"] = p.get("id") or s["session"]
            s["cwd"] = p.get("cwd") or s["cwd"]
            if isinstance(p.get("source"), dict) and "subagent" in p["source"]:
                s["subagent"] = True
        elif r.get("type") == "turn_context" and p.get("model"):
            s["models"][p["model"] + (f"/{p['effort']}" if p.get("effort") else "")] += 1
        elif p.get("type") == "token_count" and isinstance(p.get("info"), dict):
            total = p["info"].get("total_token_usage")
            if total and total != last:
                s["calls"] += 1
                last = total
    if last:
        cached = last.get("cached_input_tokens") or 0
        written = last.get("cache_write_input_tokens") or 0
        s["input"] = max(0, (last.get("input_tokens") or 0) - cached - written)
        s["cache_read"], s["cache_write"] = cached, written
        s["output"] = last.get("output_tokens") or 0
        s["reasoning"] = last.get("reasoning_output_tokens") or 0
    return s


def claude_files():
    return list(CLAUDE_PROJECTS.rglob("*.jsonl")) if CLAUDE_PROJECTS.is_dir() else []


def codex_files():
    return list(CODEX_SESSIONS.glob("*/*/*/rollout-*.jsonl")) if CODEX_SESSIONS.is_dir() else []


def collect(agent="all", since=None, cwd=None, session=None):
    jobs = []
    if agent in ("all", "claude"):
        jobs += [(parse_claude, p) for p in claude_files()]
    if agent in ("all", "codex"):
        jobs += [(parse_codex, p) for p in codex_files()]
    root = os.path.realpath(cwd) if cwd else None
    out = []
    for parse, p in jobs:
        if session and session not in str(p):
            continue
        if since and datetime.fromtimestamp(p.stat().st_mtime, timezone.utc) < since:
            continue
        s = parse(p)
        if not s["calls"] or (since and s["end"] and s["end"] < since):
            continue
        if root:
            here = os.path.realpath(s["cwd"] or "/")
            if here != root and not here.startswith(root + os.sep):
                continue
        out.append(s)
    return sorted(out, key=lambda s: s["start"] or EPOCH)


def weighted(s, weights):
    w = weights.get(s["agent"]) or DEFAULT_WEIGHTS.get(s["agent"], {})
    return sum((s.get(f) or 0) * w.get(f, 0) for f in FIELDS)


def human(n):
    n = float(n or 0)
    for unit, size in (("M", 1e6), ("k", 1e3)):
        if abs(n) >= size:
            return f"{n / size:.1f}{unit}"
    return f"{n:.0f}"


def pretty(p):
    s, h = str(p), str(HOME)
    return "~" + s[len(h):] if s == h or s.startswith(h + "/") else s


def serialize(s, weights):
    out = {k: v for k, v in s.items() if k not in ("start", "end")}
    out.update(start=s["start"].isoformat() if s["start"] else None, end=s["end"].isoformat() if s["end"] else None,
               models=dict(s["models"]), skills=dict(s["skills"]), subagents=dict(s["subagents"]),
               weighted=round(weighted(s, weights), 1))
    return out


def _row(label, items, weights):
    tot = {f: sum(s[f] for s in items) for f in FIELDS}
    w = sum(weighted(s, weights) for s in items)
    calls = sum(s["calls"] for s in items)
    return (f"{label:<34} {human(tot['input']):>7} {human(tot['cache_write']):>8} {human(tot['cache_read']):>8} "
            f"{human(tot['output']):>7} {human(w):>9} {calls:>6}")


def _groups(sessions, by, weights):
    buckets = {}
    for s in sessions:
        start = (s["start"] or EPOCH).astimezone()
        if by == "session":
            keys = [f"{start:%m-%d %H:%M} {s['agent'][:6]} {s['session'][:8]}{'*' if s['subagent'] else ''}"]
        elif by == "model":
            keys = [(s["models"].most_common(1) or [("?", 0)])[0][0]]
        elif by == "day":
            keys = [f"{start:%Y-%m-%d}"]
        elif by == "skill":
            keys = list(s["skills"]) or ["(no skill)"]
        else:
            keys = [pretty(s["cwd"]) or "?"]
        for k in keys:
            buckets.setdefault(k, []).append(s)
    items = list(buckets.items())
    if by == "session":
        return items[::-1]
    return sorted(items, key=lambda kv: -sum(weighted(s, weights) for s in kv[1]))


def cmd_usage(a, weights):
    try:
        since = None if a.session else parse_since(a.since)
    except ValueError as e:
        raise SystemExit(str(e))
    sessions = collect(a.agent, since, os.getcwd() if a.here else a.cwd, a.session)
    if a.json:
        print(json.dumps([serialize(s, weights) for s in sessions], ensure_ascii=False, indent=1))
        return
    if not sessions:
        print("해당 조건의 세션 기록이 없습니다.")
        return
    starts = [s["start"] for s in sessions if s["start"]]
    agents = Counter(s["agent"] for s in sessions)
    period = f"{min(starts).astimezone():%Y-%m-%d} ~ {max(starts).astimezone():%Y-%m-%d}" if starts else "-"
    print(f"기간 {period} · 세션 {len(sessions)} ({', '.join(f'{k} {v}' for k, v in agents.items())}, "
          f"서브에이전트 {sum(s['subagent'] for s in sessions)})")
    print(f"{'':<34} {'input':>7} {'c.write':>8} {'c.read':>8} {'output':>7} {'weighted':>9} {'calls':>6}")
    print(_row("TOTAL", sessions, weights))
    groups = _groups(sessions, a.by, weights)
    print(f"\n[by {a.by}]")
    for label, items in groups[: a.limit]:
        extra = ""
        if a.by == "session":
            s = items[0]
            model = (s["models"].most_common(1) or [("?", 0)])[0][0]
            skills = ",".join(s["skills"]) or "-"
            extra = f"  {model} · {pretty(s['cwd'])} · skills:{skills}"
        elif a.by == "skill":
            extra = f"  세션 {len(items)}"
        print(_row(label, items, weights) + extra)
    if len(groups) > a.limit:
        print(f"… 외 {len(groups) - a.limit}개 (--limit)")
    print("\n* weighted = 입력 토큰 기준 가중합 (캐시 읽기 0.1배, 출력 5~8배 등. models.json usage_weights)."
          " 달러가 아닌 상대 비교용. * 표시 세션은 서브에이전트.")
