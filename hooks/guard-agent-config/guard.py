#!/usr/bin/env python3
"""PreToolUse 훅: 에이전트 설정 폴더(스킬·서브에이전트)에 직접 쓰는 것을 막고 하네스로 안내한다.

Claude Code(Write/Edit/MultiEdit/Bash)와 Codex(shell, apply_patch)의 입력 형식을 모두 처리한다.
판단할 수 없는 입력은 통과시킨다(fail-open). 에이전트 작업을 훅 오류로 멈추지 않기 위해서다.
"""
import json
import os
import re
import sys

HOME_FORMS = {os.path.expanduser("~"), os.path.realpath(os.path.expanduser("~"))}
HARNESS = os.path.realpath(os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", ".."))
PROTECTED = (".claude/skills", ".claude/agents", ".agents/skills", ".codex/skills")
PREFIXES = sorted({h + "/" for h in HOME_FORMS} | {"~/", "$HOME/", "${HOME}/"})

WRITE_CMD = re.compile(
    r"(^|[\s;&|(])(cp|mv|ln|rsync|install|mkdir|rm|rmdir|touch|tee|unzip|tar|curl|wget|git\s+clone)\b")
REDIRECT = re.compile(r">")
HARMLESS_REDIRECT = re.compile(r"\d*>\s*/dev/null|\d*>&\d")
SKILLS_CLI = re.compile(r"\bskills?\s+(add|install)\b")
HARNESS_CMD = re.compile(r"(^|[\s;&|(])(harness\s|\S*/install\.sh\b)")
PATCH_FILE = re.compile(r"^\*\*\* (?:Add|Update|Delete) File: (.+)$", re.M)

GUIDE = ("하네스 관리 대상 경로입니다: {path}\n"
         "스킬·서브에이전트는 에이전트 설정 폴더에 직접 설치하지 않고 하네스에 추가합니다.\n"
         "- 현재 목록·중복 확인: harness list --all\n"
         "- 외부 스킬 추가: harness add skill <경로|git URL> → harness install\n"
         "- 새로 만들기: harness new skill <이름>\n"
         "하네스 밖 설치가 꼭 필요하면 사용자가 직접 실행하도록 안내하세요.")


def deny(path):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": GUIDE.format(path=path)}}, ensure_ascii=False))
    sys.exit(0)


def inside(path, root):
    return path == root or path.startswith(root + os.sep)


def protected_file(path, cwd):
    """파일 경로가 보호 폴더 안이면서 하네스로 이어지지 않으면 그 경로를 돌려준다."""
    full = os.path.expanduser(path)
    if not os.path.isabs(full):
        full = os.path.join(cwd or os.getcwd(), full)
    real = os.path.realpath(full)
    if inside(real, HARNESS):
        return None
    for home in HOME_FORMS:
        for rel in PROTECTED:
            root = os.path.join(home, rel)
            if inside(os.path.normpath(full), root) or inside(real, os.path.realpath(root)):
                return full
    return None


def protected_in_command(cmd, cwd):
    for prefix in PREFIXES:
        for rel in PROTECTED:
            for m in re.finditer(re.escape(prefix + rel) + r"(/[^\s'\";|&)]*)?", cmd):
                path = m.group(0)
                for form in ("~/", "$HOME/", "${HOME}/"):
                    if path.startswith(form):
                        path = os.path.join(os.path.expanduser("~"), path[len(form):])
                if protected_file(path, cwd):
                    return m.group(0)
    return None


def check_command(cmd, cwd):
    if HARNESS_CMD.search(cmd):
        return
    if SKILLS_CLI.search(cmd):
        deny("skills add/install 명령 (에이전트 설정 폴더에 설치됨)")
    hit = protected_in_command(cmd, cwd)
    if hit and (WRITE_CMD.search(cmd) or REDIRECT.search(HARMLESS_REDIRECT.sub("", cmd))):
        deny(hit)


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return
    tool_input = payload.get("tool_input") or {}
    cwd = payload.get("cwd") or ""
    if not isinstance(tool_input, dict):
        tool_input = {"input": tool_input}
    for key, value in tool_input.items():
        if isinstance(value, list) and key == "command":
            value = " ".join(str(v) for v in value)
        if not isinstance(value, str):
            continue
        if "path" in key:
            hit = protected_file(value, cwd)
            if hit:
                deny(hit)
        elif key in ("command", "cmd"):
            check_command(value, cwd)
        elif "*** Begin Patch" in value:
            for path in PATCH_FILE.findall(value):
                hit = protected_file(path.strip(), cwd)
                if hit:
                    deny(hit)


if __name__ == "__main__":
    main()
