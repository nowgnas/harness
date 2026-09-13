"""같은 작업 세트를 조건별(하네스 미적용 vs 적용)로 실행해 토큰·결과를 기록하고 비교한다.

작업마다 대상 레포의 git worktree 를 만들고 비대화 모드(claude -p / codex exec)로 실행한다.
baseline 조건은 전역 설정을 건드리지 않고, 하네스 산출물만 뺀 HOME 미러(~/.knack-bench/baseline-home)로
에이전트를 띄운다. 미러의 나머지 항목(인증, 프록시 설정, 캐시, 세션 로그 폴더)은 원본 링크라 조건이 같다.
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

def _bench_dir():
    """KNACK_BENCH_DIR > ~/.knack-bench. 개명 전 ~/.harness-bench 만 있으면 그것을 쓴다(결과 보존)."""
    env = os.environ.get("KNACK_BENCH_DIR") or os.environ.get("HARNESS_BENCH_DIR")
    if env:
        return Path(env)
    new_dir, old_dir = Path.home() / ".knack-bench", Path.home() / ".harness-bench"
    return old_dir if old_dir.is_dir() and not new_dir.is_dir() else new_dir


BENCH_DIR = _bench_dir()
BASELINE_HOME = BENCH_DIR / "baseline-home"
DEFAULT_TASKS = BENCH_DIR / "tasks.json"
EXAMPLE = Path(__file__).resolve().parent.parent / "bench" / "tasks.example.json"
LABEL_RE = re.compile(r"[A-Za-z0-9._-]+")


def fail(msg, code=1):
    print(msg, file=sys.stderr)
    sys.exit(code)


def results_path(label):
    if not LABEL_RE.fullmatch(label):
        fail(f"label 은 영문·숫자·._- 만 사용: {label}", 2)
    return BENCH_DIR / "results" / f"{label}.jsonl"


def git(*args, cwd=None):
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)


def cmd_bench(a, h):
    {"init": init, "run": run, "ab": ab, "compare": compare, "list": list_labels,
     "baseline": show_baseline}[a.action](a, h)


def init(a, _h):
    dst = Path(a.path).expanduser() if a.path else DEFAULT_TASKS
    if dst.exists():
        fail(f"이미 있음: {dst}", 2)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(EXAMPLE, dst)
    print(f"생성: {U.pretty(dst)}\n다음: repo·tasks·check 를 채운 뒤 knack bench ab --repeat 2 --dry-run")


def load_tasks(path):
    p = Path(path).expanduser() if path else DEFAULT_TASKS
    if not p.is_file():
        fail(f"작업 파일이 없습니다: {U.pretty(p)}\n먼저 knack bench init 으로 만들고 repo·tasks 를 채우세요.")
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


def knack_state(h, home=None, codex_home=None):
    """지시 파일에 하네스 블록이 있는지로 적용 여부를 판단한다."""
    files = {"claude": Path(home) / ".claude" / "CLAUDE.md" if home else h.RULE_FILES["claude"],
             "codex": Path(codex_home) / "AGENTS.md" if codex_home else h.RULE_FILES["codex"]}
    state = {}
    for agent, f in files.items():
        try:
            state[agent] = h.BLOCK_START in Path(f).read_text(encoding="utf-8")
        except OSError:
            state[agent] = False
    return state


def state_label(state):
    return ", ".join(f"{k}={'on' if v else 'off'}" for k, v in (state or {}).items())


# ── baseline: 하네스만 뺀 HOME 미러 ────────────
def _mirror(src_dir, dst_dir, special):
    """src_dir 의 항목을 링크로 복제한다. special 의 항목은 함수로 처리하고, False 면 제외한다."""
    dst_dir.mkdir(parents=True, exist_ok=True)
    if not src_dir.is_dir():
        return
    for e in sorted(src_dir.iterdir()):
        handler = special.get(e.name)
        if handler is None:
            (dst_dir / e.name).symlink_to(e)
        elif handler is not False:
            handler(e, dst_dir / e.name)


def _strip_block(h, report, start, end, what):
    def handle(src, dst):
        text = src.read_text(encoding="utf-8")
        new = h.set_block(text, start, end, None) if start in text else text
        dst.write_text(new, encoding="utf-8")
        if new != text:
            report.append(f"{U.pretty(src)}: {what} 제외")
    return handle


def _strip_hooks(h, report):
    def handle(src, dst):
        data = h.load_json(src)
        if not isinstance(data, dict):
            dst.symlink_to(src)
            return
        hooks, removed = data.get("hooks") or {}, 0
        for event in list(hooks):
            kept = [g for g in hooks[event] if not (isinstance(g, dict) and h.managed_name(g))]
            removed += len(hooks[event]) - len(kept)
            if kept:
                hooks[event] = kept
            else:
                del hooks[event]
        dst.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if removed:
            report.append(f"{U.pretty(src)}: 하네스 훅 {removed}개 제외")
    return handle


def _filter_dir(h, report, generated=False):
    def handle(src, dst):
        dst.mkdir()
        skipped = []
        for e in sorted(src.iterdir()):
            ours = h.in_knack(e) or (e.is_symlink() and os.readlink(e).startswith(str(h.KNACK)))
            if not ours and generated and e.is_file() and not e.is_symlink():
                try:
                    ours = h.GEN_MARK in e.read_text(encoding="utf-8")[:4000]
                except OSError:
                    pass
            if ours:
                skipped.append(e.name)
            else:
                (dst / e.name).symlink_to(e)
        if skipped:
            report.append(f"{U.pretty(src)}: 하네스 항목 {len(skipped)}개 제외 ({', '.join(skipped[:8])})")
    return handle


def build_baseline_home(h):
    real, base, report = Path.home(), BASELINE_HOME, []
    if base.exists() or base.is_symlink():
        shutil.rmtree(base)  # 벤치 전용 폴더
    base.mkdir(parents=True)
    skip = {".claude", ".agents"}
    for special_dir in (BENCH_DIR, h.CODEX_HOME):
        if special_dir.parent == real:
            skip.add(special_dir.name)
    for e in sorted(real.iterdir()):
        if e.name not in skip:
            (base / e.name).symlink_to(e)
    md = (h.BLOCK_START, h.BLOCK_END, "하네스 룰 블록")
    _mirror(real / ".claude", base / ".claude", {
        "CLAUDE.md": _strip_block(h, report, *md), "settings.json": _strip_hooks(h, report),
        "skills": _filter_dir(h, report), "agents": _filter_dir(h, report, generated=True)})
    _mirror(real / ".agents", base / ".agents", {"skills": _filter_dir(h, report)})
    _mirror(h.CODEX_HOME, base / ".codex", {
        "AGENTS.md": _strip_block(h, report, *md), "hooks.json": _strip_hooks(h, report), "knack": False,
        "config.toml": _strip_block(h, report, h.TOML_START, h.TOML_END, "서브에이전트 역할 블록")})
    return {"HOME": str(base), "CODEX_HOME": str(base / ".codex")}, report


def show_baseline(_a, h):
    env, report = build_baseline_home(h)
    print(f"baseline HOME 미러: {U.pretty(env['HOME'])} (CODEX_HOME={U.pretty(env['CODEX_HOME'])})")
    for line in report or ["제외할 하네스 항목이 없습니다 (하네스가 설치되지 않은 상태)"]:
        print(f"  - {line}")
    print("그 외 항목(인증, 프록시 설정, 캐시, 세션 로그 폴더)은 원본을 가리키는 링크입니다.")


# ── 실행 ─────────────────────────────────────
def build_cmd(h, agent, model, effort, prompt, wt, a):
    extra, base = shlex.split(a.agent_args or ""), h.agent_cmd(agent, a.agent_cmd)
    if agent == "claude":
        # -p 대신 --print: 래퍼(headroom 등)의 -p 옵션과 겹치지 않게
        cmd = [*base, "--print", prompt, "--output-format", "json", "--model", model,
               "--permission-mode", a.permission_mode]
        if a.max_turns:
            cmd += ["--max-turns", str(a.max_turns)]
        return cmd + extra
    cmd = [*base, "exec", "--json", "-C", str(wt), "-s", a.sandbox, "-m", model]
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
    cfg, weights = h.load_models(), h.usage_weights()
    rev = git("rev-parse", "--short", "HEAD", cwd=h.KNACK).stdout.strip()
    out_file = results_path(a.label)
    mode, env, env_note = ("baseline" if a.baseline else "current"), None, ""
    if a.baseline:
        env_note = f"HOME={BASELINE_HOME} CODEX_HOME={BASELINE_HOME / '.codex'} "
        state = {"claude": False, "codex": False}
        if not a.dry_run:
            extra_env, report = build_baseline_home(h)
            env = {**os.environ, **extra_env}
            env.pop("CLAUDE_CONFIG_DIR", None)
            state = knack_state(h, extra_env["HOME"], extra_env["CODEX_HOME"])
            print("baseline: 하네스만 뺀 HOME 미러로 실행 — " + ("; ".join(report) or "제외할 하네스 항목 없음"))
    else:
        state = knack_state(h)
    if not a.dry_run:
        out_file.parent.mkdir(parents=True, exist_ok=True)
        print(f"조건 '{a.label}' ({mode}): 하네스 {state_label(state)} · 에이전트 {agent} · 결과 {U.pretty(out_file)}")
    for t in tasks:
        if a.model:
            model, effort = a.model, a.effort
        else:
            model, effort = h.resolve_model(cfg, t.get("type") or "main", agent)
        for i in range(1, a.repeat + 1):
            wt = BENCH_DIR / "work" / a.label / f"{t['id']}-{i}"
            cmd = build_cmd(h, agent, model, effort, t["prompt"], wt, a)
            if a.dry_run:
                print(f"[{a.label}] {t['id']} #{i} · {h.model_label(model, effort)}")
                print(f"  git -C {repo} worktree add --detach {wt} {ref}")
                print(f"  (cd {wt} && {env_note}{shlex.join(cmd)})")
                if t.get("check"):
                    print(f"  check: {t['check']}")
                continue
            prepare_worktree(repo, wt, ref)
            started = time.time()
            try:
                proc = subprocess.run(cmd, cwd=wt, env=env, capture_output=True, text=True, timeout=a.timeout)
                stdout, rc = proc.stdout, proc.returncode
            except FileNotFoundError:
                fail(f"에이전트 실행 명령을 찾을 수 없습니다: {cmd[0]} (--agent-cmd 또는 KNACK_{agent.upper()}_CMD 로 지정)")
            except subprocess.TimeoutExpired as e:
                stdout, rc = _text(e.stdout), None
            duration = round(time.time() - started, 1)
            info = parse_output(agent, stdout)
            if info["is_error"] and "authentication_error" in (stdout or ""):
                print(f"  ⚠ {agent} 인증 실패(401). 터미널에서 {agent} 를 실행해 로그인한 뒤 다시 시도하세요.")
            tokens = session_tokens(agent, info["session_id"])
            if tokens is None and info["usage"]:
                tokens = {**info["usage"], "calls": info["turns"] or 0, "source": "stdout"}
            check_ok = None
            if t.get("check"):  # 평가는 두 조건 모두 실제 환경에서
                try:
                    check_ok = subprocess.run(["bash", "-lc", t["check"]], cwd=wt, capture_output=True,
                                              timeout=a.check_timeout).returncode == 0
                except subprocess.TimeoutExpired:
                    check_ok = False
            status = git("status", "--porcelain", cwd=wt).stdout.splitlines()
            rec = {"label": a.label, "mode": mode, "task": t["id"], "type": t.get("type"), "rep": i, "agent": agent,
                   "model": model, "effort": effort, "knack": state, "knack_rev": rev,
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


def ab(a, h):
    """baseline(하네스 제외)과 knack(현재 설정)를 연달아 실행하고 비교한다."""
    if not a.dry_run and not any(knack_state(h).values()):
        fail("하네스가 적용되지 않은 상태입니다. knack install 후 다시 실행하세요.")
    prefix = a.prefix or datetime.now().strftime("ab-%Y%m%d-%H%M")
    labels = (f"{prefix}-baseline", f"{prefix}-knack")
    for label, baseline in zip(labels, (True, False)):
        print(f"\n=== {label} ===")
        a.label, a.baseline = label, baseline
        run(a, h)
    if a.dry_run:
        print(f"\n실행 수: 작업 × repeat {a.repeat} × 2조건. 실제 실행: --dry-run 없이 같은 명령")
        return
    print()
    a.a, a.b, a.json = labels[0], labels[1], False
    compare(a, h)


# ── 비교 ─────────────────────────────────────
def load_results(label):
    f = results_path(label)
    if not f.is_file():
        fail(f"결과 없음: {label} (knack bench list)")
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
    print(f"A = {a.a} (하네스 {state_label(rows_a[-1].get('knack'))}) · B = {a.b} (하네스 {state_label(rows_b[-1].get('knack'))})")
    if rows_a[-1].get("knack") == rows_b[-1].get("knack"):
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
        print("벤치 결과가 없습니다. knack bench init → knack bench ab --repeat 2")
        return
    for f in files:
        rows = [json.loads(l) for l in f.read_text(encoding="utf-8").splitlines() if l.strip()]
        last = rows[-1] if rows else {}
        print(f"  {f.stem:<28} 실행 {len(rows):>3} · 작업 {len({r['task'] for r in rows})} · {last.get('agent', '-')} · "
              f"{last.get('mode', '-')} · 하네스 {state_label(last.get('knack'))} · {last.get('time', '-')}")
