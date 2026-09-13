#!/usr/bin/env python3
"""SessionStart 훅: 설치본이 하네스 레포와 다르면 세션 맥락에 알린다.

스킬은 심링크라 레포를 고치면 바로 반영되지만, 룰 블록·서브에이전트·훅·모델은
install.sh 가 만드는 생성물이라 레포만 고치면 낡은 상태로 남는다. 그 간극을 알린다.
판단은 install.sh --status 에 맡긴다(설치와 같은 코드 경로라 정의가 갈라지지 않는다).
설치는 하지 않는다(사용자 승인 후 knack install). 판단할 수 없으면 조용히 통과한다(fail-open).
"""
import json
import os
import subprocess
import sys

HOOK_DIR = os.path.dirname(os.path.realpath(__file__))
KNACK = os.path.realpath(os.path.join(HOOK_DIR, "..", ".."))
STATUS_TIMEOUT = 8
LIMIT = 6  # 메시지에 나열할 항목 수
# install.sh --status 가 쓰는 상태 표시 중 "갱신 필요"에 해당하는 것들
STALE_STATES = {"MISSING", "STALE", "BROKEN", "CONFLICT", "EXTRA", "ERROR"}

GUIDE = ("하네스 설치본이 레포({repo})와 다릅니다 — 갱신 필요 {n}건:\n{items}\n"
         "룰 블록·서브에이전트·훅·모델은 install.sh 가 만드는 생성물이라 레포만 고치면 반영되지 않습니다.\n"
         "이 세션에서 하네스 항목이 최신이라고 가정하지 마세요. 사용자에게 알리고, 승인받으면 "
         "`knack install --dry-run` → `knack install` 로 갱신하세요. 전체 상태는 `knack status`.")


def stale_lines(agents):
    """install.sh --status 출력에서 OK 가 아닌 줄을 모은다."""
    proc = subprocess.run([os.path.join(KNACK, "install.sh"), "--status", "--global",
                           "--agents", ",".join(agents)],
                          capture_output=True, text=True, timeout=STATUS_TIMEOUT)
    out = []
    for line in proc.stdout.splitlines():
        parts = line.split()
        if parts and parts[0] in STALE_STATES:
            out.append(" ".join(parts))
    return out


def main():
    try:
        json.load(sys.stdin)  # 입력은 쓰지 않지만 파이프를 비워 준다
    except (ValueError, OSError):
        pass
    sys.path.insert(0, os.path.join(KNACK, "lib"))
    try:
        import knack as h

        agents = h.installed_agents()
        if not agents:  # 하네스를 설치하지 않은 상태 — 알릴 것이 없다
            return
        items = stale_lines(agents)
        repo = h.pretty(h.KNACK)
    except Exception:  # 레포 구조·설정이 예상과 다르거나 status 가 실패하면 조용히 통과
        return
    if not items:
        return
    shown = ["  - " + i for i in items[:LIMIT]]
    if len(items) > LIMIT:
        shown.append(f"  - … 외 {len(items) - LIMIT}건")
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": GUIDE.format(repo=repo, n=len(items), items="\n".join(shown))}},
        ensure_ascii=False))


if __name__ == "__main__":
    main()
