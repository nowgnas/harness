"""같은 작업 세트를 조건별(예: 하네스 미설치 vs 설치)로 실행해 토큰·결과를 기록하고 비교한다.

작업마다 대상 레포의 git worktree 를 만들고 비대화 모드(claude -p / codex exec)로 실행한다.
조건 전환(harness uninstall / install)은 사용자가 하고, 실행 시점의 하네스 적용 상태를 결과에 함께 남긴다.
"""
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import usage as U

BENCH_DIR = Path(os.environ.get("HARNESS_BENCH_DIR") or Path.home() / ".harness-bench")
EXAMPLE = Path(__file__).resolve().parent.parent / "bench" / "tasks.example.json"
LABEL_RE = re.compile(r"[A-Za-z0-9._-]+")


def fail(msg, code=1):
    print(msg, file=sys.stderr)
    sys.exit(code)


def agent_bin(agent):
    return os.environ.get(f"HARNESS_{agent.upper()}_BIN") or agent


def results_path(label):
    if not LABEL_RE.fullmatch(label):
        fail(f"label 은 영문·숫자·._- 만 사용: {label}", 2)
    return BENCH_DIR / "results" / f"{label}.jsonl"


def git(*args, cwd=None):
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)


def cmd_bench(a, h):
    {"init": init, "run": run, "compare": compare, "list": list_labels}[a.action](a, h)


def init(a, _h):
    dst = Path(a.path).expanduser()
    if dst.exists():
        fail(f"이미 있음: {dst}", 2)
    shutil.copy(EXAMPLE, dst)
    print(f"생성: {dst}\n다음: repo·tasks 를 채운 뒤 harness bench run {dst} --label <조건 이름> --dry-run")


def load_tasks(path):
    p = Path(path).expanduser()
    try:
        spec = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        fail(f"작업 파일을 읽을 수 없습니다: {e}")
    repo = Path(os.path.expanduser(spec.get("repo") or "."))
    if not repo.is_absolute():
        repo = (p.parent / repo).resolve()
    if not repo.is_dir() or git("rev-parse", "--git-dir", cwd=repo).returncode:
        fail(f"git 레포가 아닙니다: {repo}")
    tasks = spec.get("tasks") or []
    if not tasks or any(not t.get("id") or not t.get("prompt") for t in tasks):
        fail("tasks 에는 id 와 prompt 가 있는 작업이 하나 이상 필요합니다.", 2)
    return spec, repo, tasks


def harness_state(h):
    state = {}
    for agent, f in h.RULE_FILES.items():
        try:
            state[agent] = h.BLOCK_START in Path(f).read_text(encoding="utf-8")
        except OSError:
            state[agent] = False
    return state


def state_label(state):
    return ", ".join(f"{k}={'on' if v else 'off'}" for k, v in (state or {}).items())


def build_cmd(agent, model, effort, prompt, wt, a):
    extra = shlex.split(a.agent_args or "")
    if agent == "claude":
        cmd = [agent_bin("claude"), "-p", prompt, "--output-format", "json", "--model", model,
               "--permission-mode", a.permission_mode]
        if a.max_turns:
            cmd += ["--max-turns", str(a.max_turns)]
        return cmd + extra
    cmd = [agent_bin("codex"), "exec", "--json", "-C", str(wt), "-s", a.sandbox, "-m", model]
    if effort:
        cmd += ["-c", f"model_reasoning_effort={effort}"]
    return cmd + extra + [prompt]


def parse_output(agent, text):
    """에이전트 표준 출력에서 세션 id·턴·비용·토큰. 래퍼 배너 같은 비 JSON 줄은 건너뛴다."""
    info = {"session_id": None, "turns": None, "cost_usd": None, "is_error": None, "usage": None}
    lines = [l.strip() for l in (text or "").splitlines() if l.strip().startswith("{")]
    if agent == "claude":
        for line in reversed(lines):
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if r.get("type") == "result":
                u = r.get("usage") or {}
                info.update(session_id=r.get("session_id"), turns=r.get("num_turns"), cost_usd=r.get("total_cost_usd"),
                            is_error=bool(r.get("is_error")),
                            usage={"input": u.get("input_tokens") or 0, "cache_write": u.get("cache_creation_input_tokens") or 0,
                                   "cache_read": u.get("cache_read_input_tokens") or 0,
                                   "output": u.get("output_tokens") or 0, "reasoning": 0})
                break
        if info["is_error"] is None:
            info["is_error"] = True
        return info
    usage, turns = {"input": 0, "cache_write": 0, "cache_read": 0, "output": 0, "reasoning": 0}, 0
    for line in lines:
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if r.get("type") == "thread.started":
            info["session_id"] = r.get("thread_id")
        elif r.get("type") == "turn.completed":
            u, turns = r.get("usage") or {}, turns + 1
            cached = u.get("cached_input_tokens") or 0
            usage["input"] += max(0, (u.get("input_tokens") or 0) - cached)
            usage["cache_read"] += cached
            usage["output"] += u.get("output_tokens") or 0
            usage["reasoning"] += u.get("reasoning_output_tokens") or 0
        elif r.get("type") in ("turn.failed", "error"):
            info["is_error"] = True
    info["turns"] = turns
    if turns:
        info["usage"] = usage
    if info["is_error"] is None:
        info["is_error"] = not turns
    return info


def session_tokens(agent, sid):
    """세션 로그에서 토큰 (Claude 는 서브에이전트 기록 포함). 로그를 못 찾으면 None."""
    if not sid:
        return None
    if agent == "claude":
        files, parse = [p for p in U.claude_files() if p.stem == sid or p.parent.parent.name == sid], U.parse_claude
    else:
        files, parse = [p for p in U.codex_files() if sid in p.name], U.parse_codex
    if not files:
        return None
    sessions = [parse(p) for p in files]
    tokens = {f: sum(s[f] for s in sessions) for f in (*U.FIELDS, "reasoning", "calls")}
    tokens.update(source="log", subagent_sessions=sum(s["subagent"] for s in sessions))
    return tokens


def prepare_worktree(repo, wt, ref):
    if wt.exists():
        remove_worktree(repo, wt)
    wt.parent.mkdir(parents=True, exist_ok=True)
    r = git("worktree", "add", "--detach", str(wt), ref, cwd=repo)
    if r.returncode:
        fail(f"worktree 생성 실패: {r.stderr.strip()}")


def remove_worktree(repo, wt):
    git("worktree", "remove", "--force", str(wt), cwd=repo)
    if wt.exists() and BENCH_DIR in wt.parents:  # 벤치가 만든 작업 폴더만 정리
        shutil.rmtree(wt, ignore_errors=True)
    git("worktree", "prune", cwd=repo)


def _text(out):
    return out.decode("utf-8", "replace") if isinstance(out, bytes) else (out or "")


def run(a, h):
    spec, repo, tasks = load_tasks(a.tasks)
    if a.only:
        wanted = set(a.only.split(","))
        tasks = [t for t in tasks if t["id"] in wanted]
    agent = a.agent or spec.get("agent") or "claude"
    ref = spec.get("ref") or "HEAD"
    cfg, weights, state = h.load_models(), h.usage_weights(), harness_state(h)
    rev = git("rev-parse", "--short", "HEAD", cwd=h.HARNESS).stdout.strip()
    out_file = results_path(a.label)
    if not a.dry_run:
        out_file.parent.mkdir(parents=True, exist_ok=True)
        print(f"조건 '{a.label}': 하네스 {state_label(state)} · 에이전트 {agent} · 결과 {U.pretty(out_file)}")
    for t in tasks:
        if a.model:
            model, effort = a.model, a.effort
        else:
            model, effort = h.resolve_model(cfg, t.get("type") or "main", agent)
        for i in range(1, a.repeat + 1):
            wt = BENCH_DIR / "work" / a.label / f"{t['id']}-{i}"
            cmd = build_cmd(agent, model, effort, t["prompt"], wt, a)
            if a.dry_run:
                print(f"[{t['id']} #{i}] {h.model_label(model, effort)}")
                print(f"  git -C {repo} worktree add --detach {wt} {ref}")
                print(f"  (cd {wt} && {shlex.join(cmd)})")
                if t.get("check"):
                    print(f"  check: {t['check']}")
                continue
            prepare_worktree(repo, wt, ref)
            started = time.time()
            try:
                proc = subprocess.run(cmd, cwd=wt, capture_output=True, text=True, timeout=a.timeout)
                stdout, rc = proc.stdout, proc.returncode
            except subprocess.TimeoutExpired as e:
                stdout, rc = _text(e.stdout), None
            duration = round(time.time() - started, 1)
            info = parse_output(agent, stdout)
            tokens = session_tokens(agent, info["session_id"])
            if tokens is None and info["usage"]:
                tokens = {**info["usage"], "calls": info["turns"] or 0, "source": "stdout"}
            check_ok = None
            if t.get("check"):
                try:
                    check_ok = subprocess.run(["bash", "-lc", t["check"]], cwd=wt, capture_output=True,
                                              timeout=a.check_timeout).returncode == 0
                except subprocess.TimeoutExpired:
                    check_ok = False
            status = git("status", "--porcelain", cwd=wt).stdout.splitlines()
            rec = {"label": a.label, "task": t["id"], "type": t.get("type"), "rep": i, "agent": agent,
                   "model": model, "effort": effort, "harness": state, "harness_rev": rev,
                   "time": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                   "exit_code": rc, "timed_out": rc is None, "is_error": info["is_error"], "turns": info["turns"],
                   "cost_usd": info["cost_usd"], "duration_s": duration, "check_ok": check_ok,
                   "diff": git("diff", "--shortstat", "HEAD", cwd=wt).stdout.strip(),
                   "untracked": sum(1 for l in status if l.startswith("??")),
                   "tokens": tokens,
                   "weighted": round(U.weighted({"agent": agent, **tokens}, weights), 1) if tokens else None,
                   "session_id": info["session_id"], "worktree": str(wt) if a.keep else None}
            with open(out_file, "a", encoding="utf-8") as fh:
                fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
            mark = "-" if check_ok is None else ("✓" if check_ok else "✗")
            print(f"  {t['id']} #{i} check {mark} · {duration}s · turns {info['turns']} · "
                  f"weighted {U.human(rec['weighted']) if tokens else '-'} ({tokens['source'] if tokens else 'no usage'})")
            if not a.keep:
                remove_worktree(repo, wt)


def load_results(label):
    f = results_path(label)
    if not f.is_file():
        fail(f"결과 없음: {label} (harness bench list)")
    return [json.loads(l) for l in f.read_text(encoding="utf-8").splitlines() if l.strip()]


def stats(rows):
    def mean(values):
        values = [v for v in values if v is not None]
        return sum(values) / len(values) if values else None

    checks = [r["check_ok"] for r in rows if r.get("check_ok") is not None]
    return {"n": len(rows), "weighted": mean([r.get("weighted") for r in rows]), "turns": mean([r.get("turns") for r in rows]),
            "duration": mean([r.get("duration_s") for r in rows]), "pass": sum(checks) / len(checks) if checks else None,
            "errors": sum(1 for r in rows if r.get("is_error") or r.get("timed_out"))}


def _fmt(v, kind):
    if v is None:
        return "-"
    if kind == "pct":
        return f"{v * 100:.0f}%"
    if kind == "tok":
        return U.human(v)
    return f"{v:.1f}"


def _delta(x, y):
    return f"{(y - x) / x * 100:+.0f}%" if x and y is not None else "-"


def compare(a, _h):
    rows_a, rows_b = load_results(a.a), load_results(a.b)
    tasks = list(dict.fromkeys([r["task"] for r in rows_a] + [r["task"] for r in rows_b]))
    table = {t: (stats([r for r in rows_a if r["task"] == t]), stats([r for r in rows_b if r["task"] == t])) for t in tasks}
    if a.json:
        print(json.dumps({"a": a.a, "b": a.b, "tasks": table}, ensure_ascii=False, indent=1))
        return
    print(f"A = {a.a} (하네스 {state_label(rows_a[-1].get('harness'))}) · B = {a.b} (하네스 {state_label(rows_b[-1].get('harness'))})")
    if rows_a[-1].get("harness") == rows_b[-1].get("harness"):
        print("  ⚠ 두 조건의 하네스 적용 상태가 같습니다.")
    print(f"{'task':<16} {'A tok':>8} {'B tok':>8} {'Δtok':>6} | {'A pass':>6} {'B pass':>6} | "
          f"{'A turn':>6} {'B turn':>6} | {'A sec':>6} {'B sec':>6} | {'n':>5}")
    tot_a = tot_b = 0.0
    for t, (sa, sb) in table.items():
        if sa["weighted"] is not None and sb["weighted"] is not None:
            tot_a, tot_b = tot_a + sa["weighted"], tot_b + sb["weighted"]
        print(f"{t:<16} {_fmt(sa['weighted'], 'tok'):>8} {_fmt(sb['weighted'], 'tok'):>8} {_delta(sa['weighted'], sb['weighted']):>6} | "
              f"{_fmt(sa['pass'], 'pct'):>6} {_fmt(sb['pass'], 'pct'):>6} | {_fmt(sa['turns'], 'n'):>6} {_fmt(sb['turns'], 'n'):>6} | "
              f"{_fmt(sa['duration'], 'n'):>6} {_fmt(sb['duration'], 'n'):>6} | {sa['n']:>2}/{sb['n']:<2}")
    print(f"{'TOTAL':<16} {U.human(tot_a):>8} {U.human(tot_b):>8} {_delta(tot_a, tot_b):>6}")
    print("\ntok = 작업별 평균 weighted 토큰 (입력 토큰 기준 가중합, 달러 아님) · Δ = (B−A)/A · pass = check 통과율")


def list_labels(_a, _h):
    root = BENCH_DIR / "results"
    files = sorted(root.glob("*.jsonl")) if root.is_dir() else []
    if not files:
        print("벤치 결과가 없습니다. harness bench init → harness bench run")
        return
    for f in files:
        rows = [json.loads(l) for l in f.read_text(encoding="utf-8").splitlines() if l.strip()]
        last = rows[-1] if rows else {}
        print(f"  {f.stem:<20} 실행 {len(rows):>3} · 작업 {len({r['task'] for r in rows})} · {last.get('agent', '-')} · "
              f"하네스 {state_label(last.get('harness'))} · {last.get('time', '-')}")
