#!/usr/bin/env bash
# smoke.sh — 임시 HOME 에서 설치·조회·관리·훅·모델 라우팅을 검증한다. 실제 설정과 이 레포는 건드리지 않는다.
set -u
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" CODEX_HOME="$TMP/home/.codex"
mkdir -p "$HOME/.claude/agents" "$CODEX_HOME"
INSTALL="$HARNESS_DIR/install.sh"
H="$HOME/.local/bin/harness"
GUARD="$HARNESS_DIR/hooks/guard-agent-config/guard.py"
ROLES="$CODEX_HOME/harness/agents"
FAIL=0

ok()   { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }
contains() { grep -qF -- "$2" "$1" 2>/dev/null; }
json_eq() { python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])) == json.load(open(sys.argv[2])) else 1)' "$1" "$2"; }
guard() { printf '%s' "$1" | python3 "$GUARD"; }
TOMLPY=""
for p in python3 python3.13 python3.12 python3.11 /opt/homebrew/bin/python3 /usr/local/bin/python3; do
  command -v "$p" >/dev/null 2>&1 && "$p" -c "import tomllib" 2>/dev/null && { TOMLPY="$p"; break; }
done
toml_ok() { [ -z "$TOMLPY" ] || "$TOMLPY" -c 'import tomllib,sys; tomllib.load(open(sys.argv[1],"rb"))' "$1"; }
TOML_NOTE="${TOMLPY:+tomllib}"; TOML_NOTE="${TOML_NOTE:-tomllib 없음 — 문법 검사 생략}"

echo "▶ 구조"
for f in "$HARNESS_DIR"/skills/*/SKILL.md; do
  d="$(dirname "$f")"; s="$(basename "$d")"
  check "$s: frontmatter name 일치" '[ "$(sed -n "s/^name: *//p" "$f" | head -1)" = "$s" ]'
  check "$s: description 존재" 'grep -qE "^description: .{20,}" "$f"'
  check "$s: description 160자 이하" '[ "$(sed -n "s/^description: *//p" "$f" | head -1 | python3 -c "import sys; print(len(sys.stdin.read().strip()))")" -le 160 ]'
  missing=""
  for ref in $(grep -oE '(\.\./[a-z-]+/)?(references|templates|scripts)/[A-Za-z0-9_./-]+\.(md|sh)' "$f" | sort -u); do
    [ -e "$d/$ref" ] || missing="$missing $ref"
  done
  check "$s: 참조 파일 존재${missing:+ (없음:$missing)}" '[ -z "$missing" ]'
done
for f in "$HARNESS_DIR"/rules/*.md; do
  check "rule $(basename "$f"): name·description·load" 'grep -q "^name: " "$f" && grep -q "^description: " "$f" && grep -qE "^load: (always|on-demand)$" "$f"'
done
check "USAGE.md 에 모든 스킬 안내" '( for s in $(ls "$HARNESS_DIR/skills"); do grep -q "\`$s\`" "$HARNESS_DIR/skills/harness-help/USAGE.md" || exit 1; done )'
check "harness doctor (레포 구조·모델 라우팅) 문제 없음" 'python3 "$HARNESS_DIR/lib/harness.py" doctor > "$TMP/doctor0.txt" 2>&1 || grep -q "문제 0" "$TMP/doctor0.txt"'

echo "▶ 글로벌 설치"
printf '@RTK.md\n' > "$HOME/.claude/CLAUDE.md"
printf '# existing codex rules\n' > "$CODEX_HOME/AGENTS.md"
cat > "$HOME/.claude/settings.json" <<'EOF'
{"model": "opus[1m]", "hooks": {"PermissionRequest": [{"matcher": "", "hooks": [{"type": "http", "url": "http://127.0.0.1:23333/permission", "timeout": 600}]}]}}
EOF
cat > "$CODEX_HOME/hooks.json" <<'EOF'
{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "echo hi", "timeout": 30}]}]}}
EOF
printf 'model = "gpt-5.6-luna"\nmodel_reasoning_effort = "medium"\n\n[mcp_servers.cx]\ncommand = "y"\n[mcp_servers.cx.env]\nA = "b"\n' > "$CODEX_HOME/config.toml"
ln -s "$HARNESS_DIR/adapters/claude/agents/impl-reviewer.md" "$HOME/.claude/agents/impl-reviewer.md"   # 옛 구조의 끊어진 링크
printf -- '---\nname: my-agent\ndescription: mine\n---\nmine\n' > "$HOME/.claude/agents/my-agent.md"
cp "$HOME/.claude/settings.json" "$TMP/orig-settings.json"
cp "$CODEX_HOME/hooks.json" "$TMP/orig-codex-hooks.json"
cp "$CODEX_HOME/config.toml" "$TMP/orig-config.toml"
"$INSTALL" --global --agents claude,codex --dry-run > "$TMP/dry.txt"
check "dry-run 은 아무것도 바꾸지 않음" '[ ! -e "$HOME/.claude/skills" ] && json_eq "$HOME/.claude/settings.json" "$TMP/orig-settings.json" && cmp -s "$CODEX_HOME/config.toml" "$TMP/orig-config.toml"'
"$INSTALL" --global --agents claude,codex > "$TMP/out1.txt"
for s in $(ls "$HARNESS_DIR/skills"); do
  check "스킬 링크: $s" '[ "$(readlink "$HOME/.claude/skills/'$s'")" = "$HARNESS_DIR/skills/'$s'" ] && [ "$(readlink "$HOME/.agents/skills/'$s'")" = "$HARNESS_DIR/skills/'$s'" ]'
done
for a in "$HARNESS_DIR"/agents/*.md; do
  n="$(basename "$a")"; A="$HOME/.claude/agents/$n"
  check "Claude 서브에이전트 생성: $n" '[ -f "$A" ] && [ ! -L "$A" ] && contains "$A" "harness:generated" && grep -q "^model: " "$A" && ! grep -qE "^(task|sandbox): " "$A"'
  check "Codex 역할 생성: ${n%.md}" '[ -f "$ROLES/${n%.md}.toml" ] && contains "$CODEX_HOME/config.toml" "[agents.${n%.md}]" && toml_ok "$ROLES/${n%.md}.toml"'
done
check "작업별 모델: git-ops=sonnet, impl-reviewer=opus" 'grep -q "^model: sonnet$" "$HOME/.claude/agents/git-ops.md" && grep -q "^model: opus$" "$HOME/.claude/agents/impl-reviewer.md"'
check "Codex 역할 모델·effort·sandbox" 'contains "$ROLES/git-ops.toml" "model = \"gpt-5.6-sol\"" && contains "$ROLES/git-ops.toml" "model_reasoning_effort = \"medium\"" && contains "$ROLES/impl-reviewer.toml" "model = \"gpt-6-astra\"" && contains "$ROLES/repo-explorer.toml" "sandbox_mode = \"read-only\"" && ! contains "$ROLES/git-ops.toml" "sandbox_mode"'
check "Codex config.toml: 기존 내용 보존 + 역할 블록 ($TOML_NOTE)" 'contains "$CODEX_HOME/config.toml" "[mcp_servers.cx]" && [ "$(head -1 "$CODEX_HOME/config.toml")" = "model = \"gpt-5.6-luna\"" ] && contains "$CODEX_HOME/config.toml" "config_file = \"$ROLES/git-ops.toml\"" && toml_ok "$CODEX_HOME/config.toml"'
check "외부 서브에이전트는 그대로" '[ "$(cat "$HOME/.claude/agents/my-agent.md" | tail -1)" = "mine" ]'
check "harness CLI 링크" '[ "$(readlink "$H")" = "$HARNESS_DIR/bin/harness" ]'
check "CLAUDE.md 기존 내용 보존" '[ "$(head -1 "$HOME/.claude/CLAUDE.md")" = "@RTK.md" ]'
check "CLAUDE.md: always 룰 import" 'contains "$HOME/.claude/CLAUDE.md" "@$HARNESS_DIR/rules/10-core.md" && contains "$HOME/.claude/CLAUDE.md" "@$HARNESS_DIR/rules/40-harness.md"'
check "CLAUDE.md: on-demand 룰은 import 없이 색인만" '! contains "$HOME/.claude/CLAUDE.md" "rules/50-git.md" && contains "$HOME/.claude/CLAUDE.md" "- \`git\` — "'
check "CLAUDE.md: 작업 유형별 모델 색인" 'contains "$HOME/.claude/CLAUDE.md" "\`git-ops\` 서브에이전트에 위임 · sonnet"'
check "Codex AGENTS.md: 기존 내용 보존 + 룰 본문" 'contains "$CODEX_HOME/AGENTS.md" "# existing codex rules" && contains "$CODEX_HOME/AGENTS.md" "# 작업 원칙" && contains "$CODEX_HOME/AGENTS.md" "# 하네스 관리"'
check "Codex AGENTS.md: frontmatter·on-demand 본문 제외" '! contains "$CODEX_HOME/AGENTS.md" "load: always" && ! contains "$CODEX_HOME/AGENTS.md" "# Git 작업"'
check "Codex AGENTS.md: 역할 위임 색인 + 상위 모델 권장" 'contains "$CODEX_HOME/AGENTS.md" "\`git-ops\` 역할로 위임 (spawn_agent) · gpt-5.6-sol/medium" && contains "$CODEX_HOME/AGENTS.md" "harness run <작업>"'
check "Claude 훅: 기존 훅·모델 보존 + guard 추가" 'python3 -c "
import json; d=json.load(open(\"$HOME/.claude/settings.json\"))
assert d[\"model\"]==\"opus[1m]\" and d[\"hooks\"][\"PermissionRequest\"][0][\"hooks\"][0][\"type\"]==\"http\"
g=d[\"hooks\"][\"PreToolUse\"][-1]; assert g[\"matcher\"]==\"Write|Edit|MultiEdit|Bash\" and \"--harness-hook guard-agent-config\" in g[\"hooks\"][0][\"command\"]"'
check "Codex 훅: 기존 훅 보존 + guard 추가 (matcher 없음)" 'python3 -c "
import json; d=json.load(open(\"$CODEX_HOME/hooks.json\"))
assert d[\"hooks\"][\"SessionStart\"][0][\"hooks\"][0][\"command\"]==\"echo hi\"
g=d[\"hooks\"][\"PreToolUse\"][-1]; assert \"matcher\" not in g and \"--harness-hook guard-agent-config\" in g[\"hooks\"][0][\"command\"]"'

echo "▶ 재설치 (멱등성)"
snap() { cat "$HOME/.claude/CLAUDE.md" "$CODEX_HOME/AGENTS.md" "$HOME/.claude/settings.json" "$CODEX_HOME/hooks.json" "$CODEX_HOME/config.toml" "$HOME"/.claude/agents/*.md "$ROLES"/*.toml | cksum; }
sum1="$(snap)"
"$INSTALL" --global --agents claude,codex > "$TMP/out2.txt"
check "두 번째 실행은 변경 0건" 'contains "$TMP/out2.txt" "변경 0건"'
check "설정 파일 내용 동일" '[ "$sum1" = "$(snap)" ]'
# 빈 config.toml(새 머신)에서는 최상위 키 삽입 간격 때문에 한 번 더 설치해야 수렴하던 적이 있다
FRESH="$TMP/fresh"; mkdir -p "$FRESH/.codex"
HOME="$FRESH" CODEX_HOME="$FRESH/.codex" "$INSTALL" --global --agents claude,codex > "$TMP/fresh1.txt" 2>&1
HOME="$FRESH" CODEX_HOME="$FRESH/.codex" "$INSTALL" --status --global --agents claude,codex > "$TMP/fresh-status.txt" 2>&1
check "빈 HOME: 설치 한 번으로 status 전부 OK" '! grep -qE "^  (STALE|MISSING|CONFLICT|BROKEN)" "$TMP/fresh-status.txt"'

echo "▶ 모델 라우팅 CLI"
"$H" model > "$TMP/model.txt"
check "model: 작업·티어·모델·위임 표" 'grep -qE "^  git +standard +sonnet +\| +gpt-5\.6-sol/medium +→ git-ops" "$TMP/model.txt" && grep -qE "^  main +세션기본 +opus\[1m\]" "$TMP/model.txt"'
check "model get (claude)" '[ "$("$H" model get git --agent claude)" = sonnet ]'
check "model get --format flags (codex)" '[ "$("$H" model get implement --agent codex --format flags)" = "-m gpt-6-astra -c model_reasoning_effort=high" ]'
check "which: 커밋·푸시 → git" '"$H" model which "변경사항 커밋하고 푸시해줘" | grep -q "작업 유형: git"'
check "which: 구현 → implement" '"$H" model which "주문 취소 API 구현해줘" | grep -q "작업 유형: implement"'
check "which: 동점이면 높은 티어 (PR 리뷰 → review)" '"$H" model which "PR 리뷰해줘" | grep -q "작업 유형: review"'
check "which: 영어 키워드는 단어 경계 (print ≠ PR)" '! "$H" model which "print the prompt" | grep -q "작업 유형: git"'
check "run auto → claude sonnet (dry-run)" '"$H" run auto --agent claude --dry-run -- "커밋해줘" 2>/dev/null | grep -q "^claude --model sonnet .*커밋해줘"'
check "run implement → codex exec astra/high (dry-run)" '"$H" run implement --agent codex --print --dry-run -- "구현" 2>/dev/null | grep -q "^codex exec -m gpt-6-astra -c model_reasoning_effort=high "'
check "run: 알 수 없는 작업은 실패" '! "$H" run nope --dry-run -- x >/dev/null 2>&1'

echo "▶ 조회 CLI"
mkdir -p "$HOME/.claude/skills/my-ext" "$HOME/.claude/plugins/cache/demo/skills/foo"
printf -- '---\nname: my-ext\ndescription: external skill for test\n---\n' > "$HOME/.claude/skills/my-ext/SKILL.md"
printf -- '---\nname: foo\ndescription: plugin skill\n---\n' > "$HOME/.claude/plugins/cache/demo/skills/foo/SKILL.md"
printf '{"version": 2, "plugins": {"demo@market": [{"installPath": "%s", "version": "1.0.0"}]}}\n' "$HOME/.claude/plugins/cache/demo" > "$HOME/.claude/plugins/installed_plugins.json"
printf '{"mcpServers": {"svc": {"command": "x"}}}\n' > "$HOME/.claude.json"
"$H" list > "$TMP/list.txt"
check "list: 스킬 설치 상태" 'contains "$TMP/list.txt" "[✓ ✓] bug-fix"'
check "list: 서브에이전트 (claude·codex)" 'grep -q "\[✓ ✓\] git-ops" "$TMP/list.txt"'
check "list: 룰 on-demand" 'grep -q "\[- -\] git .*(on-demand)" "$TMP/list.txt"'
check "list: 훅 설치 상태" 'grep -q "\[✓ ✓\] guard-agent-config" "$TMP/list.txt"'
"$H" list --all > "$TMP/list-all.txt"
check "list --all: 외부 스킬·플러그인 스킬·외부 서브에이전트" 'contains "$TMP/list-all.txt" "my-ext" && contains "$TMP/list-all.txt" "demo:foo" && contains "$TMP/list-all.txt" "my-agent.md"'
check "list --all: 외부 훅" 'contains "$TMP/list-all.txt" "PermissionRequest" && contains "$TMP/list-all.txt" "echo hi"'
"$H" list mcp > "$TMP/list-mcp.txt"
check "list mcp: Claude·Codex 서버 (하위 테이블 제외)" 'contains "$TMP/list-mcp.txt" "svc" && contains "$TMP/list-mcp.txt" "cx " && ! contains "$TMP/list-mcp.txt" "cx.env"'
check "list --json 파싱 가능" '"$H" list --all --json | python3 -c "import json,sys; d=json.load(sys.stdin); assert d[\"skills\"] and \"external_skills\" in d"'
"$H" show skill feature-implementation --toc > "$TMP/toc.txt"
check "show --toc: 목차와 줄 수" 'grep -q "5. 게이트.*줄)" "$TMP/toc.txt"'
"$H" show skill feature-implementation --section 5 > "$TMP/sec.txt"
check "show --section 5: 해당 섹션만" 'contains "$TMP/sec.txt" "Definition of Ready" && ! contains "$TMP/sec.txt" "## 6."'
full=$(wc -c < "$HARNESS_DIR/skills/feature-implementation/SKILL.md"); part=$(wc -c < "$TMP/sec.txt")
check "section 출력이 전체보다 작음 (${part}B / ${full}B)" '[ "$part" -lt "$((full / 3))" ]'
check "show ref --section 제목" '"$H" show ref java-spring --section "로컬 실행" | grep -q bootRun'
check "show ref --path" '[ -f "$("$H" show ref review-checklist --path)" ]'
check "show rule (on-demand 본문)" '"$H" show rule git | grep -q "^# Git 작업"'
check "show 코드펜스 안 # 은 제목 아님" '! "$H" show ref review-checklist --toc | grep -q "^## 리뷰 결과"'
check "search -l" '"$H" search expand -l | grep -q "db-migration.md"'
check "없는 섹션은 실패" '! "$H" show skill bug-fix --section 없는섹션 >/dev/null 2>&1'
"$H" doctor > "$TMP/doctor.txt" 2>&1; rc=$?
check "doctor: 문제 0 (exit $rc)" '[ $rc -eq 0 ] && contains "$TMP/doctor.txt" "모든 항목 설치됨" && contains "$TMP/doctor.txt" "모델 이름 확인됨"'
check "doctor: 스킬 작성 기준 충족 (Astra 가이드)" 'contains "$TMP/doctor.txt" "스킬 작성 기준 충족"'
check "doctor: Codex 기능 플래그 경고 (hooks, multi_agent)" 'contains "$TMP/doctor.txt" "[features] hooks = true" && contains "$TMP/doctor.txt" "multi_agent = true"'

echo "▶ 가드 훅"
deny_case() { payload="$2"; check "차단: $1" 'guard "$payload" | grep -q "\"permissionDecision\": \"deny\""'; }
allow_case() { payload="$2"; check "허용: $1" '[ -z "$(guard "$payload")" ]'; }
deny_case "Write ~/.claude/skills/x" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.claude/skills/x/SKILL.md\"}}"
deny_case "Bash cp → ~/.claude/skills" '{"tool_name":"Bash","tool_input":{"command":"cp -r ./x ~/.claude/skills/"}}'
deny_case "Bash \$HOME/.claude/agents 리다이렉트" '{"tool_name":"Bash","tool_input":{"command":"echo a > $HOME/.claude/agents/a.md"}}'
deny_case "Codex shell(list) git clone → ~/.agents/skills" '{"tool_name":"shell","tool_input":{"command":["bash","-lc","git clone https://e.x/r ~/.agents/skills/r"]}}'
deny_case "Codex apply_patch → ~/.codex/skills" "{\"tool_name\":\"apply_patch\",\"tool_input\":{\"input\":\"*** Begin Patch\n*** Add File: $HOME/.codex/skills/z/SKILL.md\n+x\n*** End Patch\"}}"
deny_case "npx skills add" '{"tool_name":"Bash","tool_input":{"command":"npx skills add owner/repo"}}'
allow_case "ls ~/.claude/skills 2>/dev/null" '{"tool_name":"Bash","tool_input":{"command":"ls ~/.claude/skills 2>/dev/null"}}'
allow_case "Write /tmp 파일" '{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo.txt"}}'
allow_case "하네스 링크를 통한 수정" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$HOME/.claude/skills/bug-fix/SKILL.md\"}}"
allow_case "harness install" '{"tool_name":"Bash","tool_input":{"command":"harness install --dry-run"}}'
allow_case "잘못된 JSON" 'not json'

echo "▶ 페르소나"
# 실제 core.md 를 건드리지 않도록 레포 복사본에서 검증한다
PREPO="$TMP/persona-repo"; mkdir -p "$PREPO"
cp -R "$HARNESS_DIR/lib" "$HARNESS_DIR/bin" "$HARNESS_DIR/rules" "$HARNESS_DIR/skills" "$HARNESS_DIR/agents" \
      "$HARNESS_DIR/hooks" "$HARNESS_DIR/persona" "$HARNESS_DIR/models.json" "$HARNESS_DIR/install.sh" "$PREPO/"
rm -f "$PREPO/persona/core.md" "$PREPO/persona/.disabled"; rm -f "$PREPO"/persona/detail/*.md
PH="python3 $PREPO/lib/harness.py"
check "미설정: init 안내" '$PH persona | grep -q "harness persona init"'
check "미설정: 주입 블록 없음" '[ -z "$($PH persona-block)" ]'
$PH persona init > /dev/null
check "init: 템플릿 복사" '[ -f "$PREPO/persona/core.md" ]'
check "자리표시자만 있으면 주입하지 않음" '[ -z "$($PH persona-block)" ]'
check "check: 자리표시자를 문제로 보고 1로 종료" '! $PH persona check > "$TMP/pcheck.txt" 2>&1; grep -q "자리표시자" "$TMP/pcheck.txt"'
$PH persona set role "백엔드. 결제 서비스 담당" > /dev/null
$PH persona set defaults "새 의존성은 먼저 묻는다; 스키마 변경은 마이그레이션 파일로만" > /dev/null
check "set: 값 저장 (; 는 목록으로)" 'grep -q "^role: 백엔드" "$PREPO/persona/core.md" && grep -q "^  - 새 의존성은 먼저 묻는다" "$PREPO/persona/core.md"'
check "set: 같은 키 재지정은 교체 (중복 없음)" '$PH persona set role "백엔드. 정산 담당" > /dev/null; [ "$(grep -c "^role:" "$PREPO/persona/core.md")" = 1 ]'
check "주입 블록: 채운 항목만 한국어 라벨로" '$PH persona-block | grep -q "^- 역할: 백엔드. 정산 담당" && $PH persona-block | grep -q "^- 기본값: 새 의존성은 먼저 묻는다; 스키마"'
check "주입 블록: 자리표시자 항목은 제외" '! $PH persona-block | grep -q "<"'
printf 'role: 표준입력에서 온 역할\n' | $PH persona import - > /dev/null
check "import -: 표준입력으로 통째 교체" 'grep -q "표준입력에서 온 역할" "$PREPO/persona/core.md" && ! grep -q "정산 담당" "$PREPO/persona/core.md"'
check "import: 형식이 아니면 거부" '! printf "그냥 줄글입니다\n" | $PH persona import - 2>/dev/null'
printf '# DB\nPostgres 15, 스키마 2개\n' | $PH persona import --detail db - > /dev/null
check "import --detail: 상세 저장 + 색인만 주입" '[ -f "$PREPO/persona/detail/db.md" ] && $PH persona-block | grep -q "필요할 때 읽는 상세.*: db" && ! $PH persona-block | grep -q "Postgres 15"'
check "show <주제>: 상세 본문 출력" '$PH persona show db | grep -q "Postgres 15"'
check "show: 없는 주제는 거부" '! $PH persona show nope 2>/dev/null'
check "disable: 주입 끔 (bench 비교용)" '$PH persona disable > /dev/null; [ -z "$($PH persona-block)" ]'
check "enable: 주입 다시 켬" '$PH persona enable > /dev/null; [ -n "$($PH persona-block)" ]'
check "core 가 길면 경고" 'for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do echo "k$i: v"; done | $PH persona import - | grep -q "권장 15줄"'
printf 'role: 결제 백엔드\n' | $PH persona import - > /dev/null
PHOME="$TMP/phome"; mkdir -p "$PHOME"
HOME="$PHOME" CODEX_HOME="$PHOME/.codex" "$PREPO/install.sh" --global --agents claude,codex > /dev/null 2>&1
check "설치: 지시 블록 맨 앞에 주입 (claude·codex)" 'head -5 "$PHOME/.claude/CLAUDE.md" | grep -q "결제 백엔드" && head -5 "$PHOME/.codex/AGENTS.md" | grep -q "결제 백엔드"'
check "설치: 페르소나가 룰 앞에 온다" '[ "$(grep -n "결제 백엔드" "$PHOME/.claude/CLAUDE.md" | cut -d: -f1)" -lt "$(grep -n "rules/10-core.md" "$PHOME/.claude/CLAUDE.md" | cut -d: -f1)" ]'
check "설치 후 status 전부 OK" 'HOME="$PHOME" CODEX_HOME="$PHOME/.codex" "$PREPO/install.sh" --status --global --agents claude,codex 2>&1 | grep -vq "^  STALE"'

echo "▶ stale 감지 훅"
STALE_HOOK="$HARNESS_DIR/hooks/harness-stale/stale.py"
stale_out() { printf '%s' "${1-\{\}}" | python3 "$STALE_HOOK"; }
check "훅 등록: Claude SessionStart (codex 는 대상 아님)" 'python3 -c "
import json
d=json.load(open(\"$HOME/.claude/settings.json\"))
cmds=[h[\"command\"] for g in d[\"hooks\"][\"SessionStart\"] for h in g[\"hooks\"]]
assert any(\"--harness-hook harness-stale\" in c for c in cmds), cmds
c=json.load(open(\"$CODEX_HOME/hooks.json\"))
assert not any(\"harness-stale\" in h[\"command\"] for g in c[\"hooks\"][\"SessionStart\"] for h in g[\"hooks\"])"'
check "설치·최신 상태에서는 조용함" '[ -z "$(stale_out)" ]'
cp "$HOME/.claude/agents/git-ops.md" "$TMP/git-ops.bak"
printf '\n손댄 줄\n' >> "$HOME/.claude/agents/git-ops.md"
check "설치본이 다르면 SessionStart 맥락으로 알림" 'stale_out | python3 -c "
import json,sys
d=json.load(sys.stdin)[\"hookSpecificOutput\"]
assert d[\"hookEventName\"]==\"SessionStart\"
assert \"harness install\" in d[\"additionalContext\"]
assert \"git-ops\" in d[\"additionalContext\"]"'
cp "$TMP/git-ops.bak" "$HOME/.claude/agents/git-ops.md"
check "깨진 입력에도 통과 (fail-open)" 'stale_out "not json" >/dev/null 2>&1'
check "하네스 미설치 HOME 에서는 조용함" '[ -z "$(HOME="$TMP/empty-home" CODEX_HOME="$TMP/empty-home/.codex" printf "{}" | HOME="$TMP/empty-home" CODEX_HOME="$TMP/empty-home/.codex" python3 "$STALE_HOOK")" ]'

echo "▶ 충돌·정리"
rm "$HOME/.claude/skills/trace-flow"; mkdir -p "$HOME/.claude/skills/trace-flow"; echo mine > "$HOME/.claude/skills/trace-flow/SKILL.md"
rm "$HOME/.claude/agents/git-ops.md"; printf -- '---\nname: git-ops\ndescription: mine\n---\nmine\n' > "$HOME/.claude/agents/git-ops.md"
"$INSTALL" --global --agents claude > "$TMP/out3.txt"
check "기존 스킬·서브에이전트는 SKIP" 'contains "$TMP/out3.txt" "SKIP" && [ ! -L "$HOME/.claude/skills/trace-flow" ] && ! contains "$HOME/.claude/agents/git-ops.md" "harness:generated"'
"$INSTALL" --global --agents claude --force > "$TMP/out4.txt"
check "--force: 스킬 링크 교체 + 백업" '[ -L "$HOME/.claude/skills/trace-flow" ] && [ -n "$(find "$HOME/.harness-backups" -path "*trace-flow/SKILL.md" 2>/dev/null)" ]'
check "--force: 서브에이전트 생성 + 백업" 'contains "$HOME/.claude/agents/git-ops.md" "harness:generated" && [ -n "$(find "$HOME/.harness-backups" -path "*agents/git-ops.md" 2>/dev/null)" ]'
ln -s "$HARNESS_DIR/skills/deleted-skill" "$HOME/.claude/skills/deleted-skill"
"$INSTALL" --global --agents claude > "$TMP/out5.txt"
check "삭제된 스킬 링크 정리 (PRUNE)" 'contains "$TMP/out5.txt" "PRUNE" && [ ! -L "$HOME/.claude/skills/deleted-skill" ]'
"$INSTALL" --status --agents claude,codex > "$TMP/status.txt"
check "상태: MISSING/STALE/CONFLICT/BROKEN 없음" '! grep -qE "MISSING|STALE|CONFLICT|BROKEN" "$TMP/status.txt"'

echo "▶ 제거"
"$INSTALL" --uninstall --agents claude,codex > "$TMP/out6.txt"
check "스킬·CLI 링크 제거" '[ ! -e "$HOME/.claude/skills/repo-onboarding" ] && [ ! -e "$HOME/.agents/skills/repo-onboarding" ] && [ ! -e "$H" ]'
check "생성한 서브에이전트·역할 제거, 외부 것은 유지" '[ ! -e "$HOME/.claude/agents/git-ops.md" ] && [ -z "$(ls -A "$ROLES" 2>/dev/null)" ] && [ -f "$HOME/.claude/agents/my-agent.md" ]'
check "CLAUDE.md 원상복구" '[ "$(cat "$HOME/.claude/CLAUDE.md")" = "@RTK.md" ]'
check "Codex AGENTS.md 원상복구" '[ "$(cat "$CODEX_HOME/AGENTS.md")" = "# existing codex rules" ]'
check "Claude settings.json 원상복구" 'json_eq "$HOME/.claude/settings.json" "$TMP/orig-settings.json"'
check "Codex hooks.json 원상복구" 'json_eq "$CODEX_HOME/hooks.json" "$TMP/orig-codex-hooks.json"'
check "Codex config.toml 원상복구" 'cmp -s "$CODEX_HOME/config.toml" "$TMP/orig-config.toml"'

echo "▶ 프로젝트 모드"
P="$TMP/proj"; mkdir -p "$P"; git -C "$P" init -q
"$INSTALL" --project "$P" --agents claude,codex > "$TMP/out7.txt"
check "프로젝트 스킬 링크·서브에이전트" '[ -L "$P/.claude/skills/repo-onboarding" ] && [ -L "$P/.agents/skills/repo-onboarding" ] && grep -q "^model: sonnet$" "$P/.claude/agents/git-ops.md"'
check "프로젝트 모드는 세션 모델을 건드리지 않음" 'json_eq "$HOME/.claude/settings.json" "$TMP/orig-settings.json"'
check "git status 에 하네스 파일이 안 보임" '[ -z "$(git -C "$P" status --porcelain)" ]'
"$INSTALL" --project "$P" --agents claude,codex --uninstall > /dev/null
check "프로젝트 제거" '[ ! -e "$P/.claude/skills/repo-onboarding" ] && [ ! -e "$P/.claude/agents/git-ops.md" ] && ! contains "$P/.git/info/exclude" "harness:start"'

echo "▶ 관리 명령 (레포 복사본에서)"
C="$TMP/hcopy"; mkdir -p "$C"
(cd "$HARNESS_DIR" && tar cf - --exclude .git .) | (cd "$C" && tar xf -)
CH="$C/bin/harness"
"$CH" new skill demo-skill > /dev/null
check "new skill" '[ -f "$C/skills/demo-skill/SKILL.md" ] && "$CH" list skills | grep -q demo-skill'
"$CH" new rule team-style > /dev/null
check "new rule (기본 on-demand, 다음 번호)" 'grep -q "^load: on-demand" "$C"/rules/60-team-style.md'
"$CH" new hook my-hook > /dev/null
check "new hook (기본 꺼짐, 실행 권한)" 'grep -q "\"enabled\": false" "$C/hooks/my-hook/hook.json" && [ -x "$C/hooks/my-hook/hook.py" ]'
"$CH" hook enable my-hook > /dev/null
check "hook enable" 'grep -q "\"enabled\": true" "$C/hooks/my-hook/hook.json"'
mkdir -p "$TMP/ext/alpha" "$TMP/ext/beta"
printf -- '---\nname: alpha\ndescription: alpha skill for test\n---\n# A\n' > "$TMP/ext/alpha/SKILL.md"
printf -- '---\nname: beta\ndescription: beta skill for test\n---\n# B\n' > "$TMP/ext/beta/SKILL.md"
"$CH" add skill "$TMP/ext" > "$TMP/add1.txt" 2>&1; rc=$?
check "add: 여러 스킬이면 --subdir 요구 (exit 2)" '[ $rc -eq 2 ] && contains "$TMP/add1.txt" "--subdir alpha"'
"$CH" add skill "$TMP/ext" --subdir alpha > /dev/null
check "add 로컬 경로" '[ -f "$C/skills/alpha/SKILL.md" ] && contains "$C/skills/alpha/.harness-source" "$TMP/ext"'
mkdir -p "$TMP/extrepo/skills/gamma"
printf -- '---\nname: gamma\ndescription: gamma skill for test\n---\n# G\n' > "$TMP/extrepo/skills/gamma/SKILL.md"
printf '#!/bin/sh\necho hi\n' > "$TMP/extrepo/skills/gamma/run.sh"; chmod +x "$TMP/extrepo/skills/gamma/run.sh"
(cd "$TMP/extrepo" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init)
"$CH" add skill "file://$TMP/extrepo" --subdir skills/gamma > "$TMP/add2.txt"
check "add git URL: 출처·커밋 기록" 'python3 -c "import json; d=json.load(open(\"$C/skills/gamma/.harness-source\")); assert len(d[\"commit\"])==40 and d[\"subdir\"]==\"skills/gamma\""'
check "add: 실행 파일 검토 경고" 'contains "$TMP/add2.txt" "실행 가능한 파일"'
check "add: 중복은 거부" '! "$CH" add skill "$TMP/ext" --subdir alpha >/dev/null 2>&1'
mkdir -p "$HOME/.claude/skills/legacy"
printf -- '---\nname: legacy\ndescription: legacy skill for test\n---\n' > "$HOME/.claude/skills/legacy/SKILL.md"
"$CH" adopt skill legacy > /dev/null
check "adopt: 외부 스킬을 하네스로 이동" '[ -f "$C/skills/legacy/SKILL.md" ] && [ ! -e "$HOME/.claude/skills/legacy" ]'
"$CH" model set git haiku --agent claude > /dev/null
check "model set <작업> <모델> --agent" '[ "$("$CH" model get git --agent claude)" = haiku ] && [ "$("$CH" model get git --agent codex)" = gpt-5.6-sol ]'
"$CH" model set docs deep > /dev/null
check "model set <작업> <티어>" '[ "$("$CH" model get docs --agent codex)" = gpt-6-astra ]'
check "model set 잘못된 대상은 실패" '! "$CH" model set nope deep >/dev/null 2>&1'
"$CH" model set main fast --agent codex > /dev/null
"$CH" model set main sonnet --agent claude > /dev/null
"$C/install.sh" --global --agents claude,codex > "$TMP/out8.txt"
check "세션 모델 반영: Claude settings.json" 'python3 -c "import json; assert json.load(open(\"$HOME/.claude/settings.json\"))[\"model\"]==\"sonnet\""'
check "세션 모델 반영: Codex config.toml ($TOML_NOTE)" 'grep -q "^model_reasoning_effort = \"low\"$" "$CODEX_HOME/config.toml" && grep -q "^model = \"gpt-5.6-luna\"$" "$CODEX_HOME/config.toml" && contains "$CODEX_HOME/config.toml" "[mcp_servers.cx]" && toml_ok "$CODEX_HOME/config.toml"'
check "변경된 작업 모델이 서브에이전트에 반영" 'grep -q "^model: haiku$" "$HOME/.claude/agents/git-ops.md"'
check "복사본 doctor 문제 없음" '"$CH" doctor > "$TMP/doctor2.txt" 2>&1; grep -q "문제 0" "$TMP/doctor2.txt"'
"$C/install.sh" --uninstall --agents claude,codex > /dev/null

echo "▶ 사용량 집계 (harness usage)"
HB="$HARNESS_DIR/bin/harness"
UP="$HOME/.claude/projects/-uproj"; mkdir -p "$UP/sess1/subagents" "$TMP/uproj"
cat > "$UP/sess1.jsonl" <<EOF
{"type":"user","timestamp":"2026-09-10T00:00:00Z","cwd":"$TMP/uproj","sessionId":"sess1","message":{"role":"user","content":"hi"}}
{"type":"assistant","timestamp":"2026-09-10T00:00:01Z","cwd":"$TMP/uproj","sessionId":"sess1","message":{"id":"m1","model":"claude-opus-5","content":[{"type":"tool_use","name":"Skill","input":{"skill":"bug-fix"}}],"usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":50}}}
{"type":"assistant","timestamp":"2026-09-10T00:00:01Z","cwd":"$TMP/uproj","sessionId":"sess1","message":{"id":"m1","model":"claude-opus-5","content":[{"type":"text","text":"x"}],"usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":50}}}
{"type":"assistant","timestamp":"2026-09-10T00:00:05Z","cwd":"$TMP/uproj","sessionId":"sess1","message":{"id":"m2","model":"claude-opus-5","content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"git-ops"}}],"usage":{"input_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":2000,"output_tokens":20}}}
EOF
cat > "$UP/sess1/subagents/agent-a.jsonl" <<EOF
{"type":"assistant","timestamp":"2026-09-10T00:00:03Z","cwd":"$TMP/uproj","sessionId":"sess1","message":{"id":"s1","model":"claude-sonnet-5","content":[],"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":500,"output_tokens":5}}}
EOF
CR="$CODEX_HOME/sessions/2026/09/10"; mkdir -p "$CR"
cat > "$CR/rollout-2026-09-10T01-00-00-th1.jsonl" <<EOF
{"timestamp":"2026-09-10T01:00:00Z","type":"session_meta","payload":{"id":"th1","cwd":"$TMP/uproj","source":"cli"}}
{"timestamp":"2026-09-10T01:00:01Z","type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"medium"}}
{"timestamp":"2026-09-10T01:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":800,"cache_write_input_tokens":0,"output_tokens":30,"reasoning_output_tokens":10}}}}
{"timestamp":"2026-09-10T01:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":3000,"cached_input_tokens":2500,"cache_write_input_tokens":0,"output_tokens":90,"reasoning_output_tokens":20}}}}
EOF
"$HB" usage --since 2000-01-01 --json > "$TMP/usage.json"
check "usage: Claude 중복 제거·스킬·서브에이전트 집계" 'python3 -c "
import json; d=json.load(open(\"$TMP/usage.json\")); m=[s for s in d if s[\"agent\"]==\"claude\" and not s[\"subagent\"]][0]
assert (m[\"input\"],m[\"cache_write\"],m[\"cache_read\"],m[\"output\"],m[\"calls\"])==(15,100,3000,70,2), m
assert m[\"skills\"]=={\"bug-fix\":1} and m[\"subagents\"]=={\"git-ops\":1}
sub=[s for s in d if s[\"subagent\"] and s[\"agent\"]==\"claude\"][0]; assert sub[\"parent\"]==\"sess1\" and sub[\"cache_read\"]==500"'
check "usage: Codex 누적값·캐시 분리" 'python3 -c "
import json; d=json.load(open(\"$TMP/usage.json\")); c=[s for s in d if s[\"agent\"]==\"codex\"][0]
assert (c[\"input\"],c[\"cache_read\"],c[\"output\"],c[\"reasoning\"],c[\"calls\"])==(500,2500,90,20,2), c"'
check "usage --by skill (텍스트)" '"$HB" usage --since 2000-01-01 --by skill | grep -q "bug-fix"'
check "usage --cwd 필터" '[ "$("$HB" usage --since 2000-01-01 --cwd "$TMP/uproj" --json | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")" = 3 ] && [ "$("$HB" usage --since 2000-01-01 --cwd /nonexistent --json | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")" = 0 ]'

echo "▶ 벤치 (harness bench)"
"$INSTALL" --global --agents claude,codex > /dev/null   # baseline 비교를 위해 하네스를 다시 적용
BR="$TMP/brepo"; mkdir -p "$BR"; (cd "$BR" && git init -q && echo a > a.txt && git add -A && git -c user.email=t@t -c user.name=t commit -qm init)
cat > "$TMP/tasks.json" <<EOF
{"repo": "$BR", "ref": "HEAD", "tasks": [
  {"id": "t1", "type": "git", "prompt": "make out.txt", "check": "test -f out.txt"},
  {"id": "t2", "type": "implement", "prompt": "noop", "check": "test -f nope.txt"}]}
EOF
cat > "$TMP/fakeclaude" <<'EOF'
#!/usr/bin/env bash
prompt=""; while [ $# -gt 0 ]; do case "$1" in -p|--print) prompt="$2"; shift ;; esac; shift; done
echo "HEADROOM WRAP banner"
echo "$HOME" >> "${SEEN_FILE:-/dev/null}"
case "$prompt" in *out.txt*) echo x > out.txt ;; esac
sid="fake-$$-$RANDOM"; d="$HOME/.claude/projects/-bench"; mkdir -p "$d"
printf '{"type":"assistant","timestamp":"2026-09-12T00:00:00Z","cwd":"%s","sessionId":"%s","message":{"id":"b1","model":"claude-sonnet-5","content":[],"usage":{"input_tokens":7,"cache_creation_input_tokens":0,"cache_read_input_tokens":300,"output_tokens":11}}}\n' "$PWD" "$sid" > "$d/$sid.jsonl"
printf '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"session_id":"%s","total_cost_usd":0.01,"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":1,"output_tokens":1}}\n' "$sid"
EOF
cat > "$TMP/fakecodex" <<'EOF'
#!/usr/bin/env bash
echo x > out.txt
echo '{"type":"thread.started","thread_id":"th-bench"}'
echo '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":7}}'
EOF
chmod +x "$TMP/fakeclaude" "$TMP/fakecodex"
export HARNESS_CLAUDE_BIN="$TMP/fakeclaude" HARNESS_CODEX_BIN="$TMP/fakecodex" HARNESS_BENCH_DIR="$TMP/bench"
"$HB" bench run "$TMP/tasks.json" --label base --dry-run > "$TMP/bench-dry.txt"
check "bench --dry-run: 작업 유형별 모델, 실행 없음" 'grep -q -- "--model sonnet" "$TMP/bench-dry.txt" && grep -q -- "--model opus" "$TMP/bench-dry.txt" && [ ! -d "$TMP/bench/results" ]'
"$HB" bench run "$TMP/tasks.json" --label base > "$TMP/bench1.txt" 2>&1
"$HB" bench run "$TMP/tasks.json" --label exp --repeat 2 > "$TMP/bench2.txt" 2>&1
check "bench run: check 성공/실패·로그 기반 토큰·모델 기록" 'python3 -c "
import json; rows=[json.loads(l) for l in open(\"$TMP/bench/results/base.jsonl\")]
r={x[\"task\"]:x for x in rows}; assert r[\"t1\"][\"check_ok\"] is True and r[\"t2\"][\"check_ok\"] is False
assert r[\"t1\"][\"tokens\"][\"source\"]==\"log\" and r[\"t1\"][\"tokens\"][\"cache_read\"]==300 and r[\"t1\"][\"turns\"]==2
assert r[\"t1\"][\"model\"]==\"sonnet\" and r[\"t2\"][\"model\"]==\"opus\" and r[\"t1\"][\"mode\"]==\"current\" and r[\"t1\"][\"harness\"]==dict(claude=True, codex=True)"'
check "bench run: repeat 반영" '[ "$(wc -l < "$TMP/bench/results/exp.jsonl" | tr -d " ")" = 4 ]'
check "bench run: worktree 정리" '[ "$(git -C "$BR" worktree list | wc -l | tr -d " ")" = 1 ]'
"$HB" bench compare base exp > "$TMP/bench-cmp.txt"
check "bench compare: 작업별 비교표" 'grep -q "^t1 " "$TMP/bench-cmp.txt" && grep -q "^TOTAL " "$TMP/bench-cmp.txt" && contains "$TMP/bench-cmp.txt" "하네스 적용 상태가 같습니다"'
check "bench list" '"$HB" bench list | grep -q "exp"'
"$HB" bench run "$TMP/tasks.json" --label cx --agent codex --only t1 > /dev/null 2>&1
check "bench codex: 스트림 토큰 (캐시 분리)" 'python3 -c "
import json; r=json.loads(open(\"$TMP/bench/results/cx.jsonl\").readline())
t=r[\"tokens\"]; assert (t[\"input\"],t[\"cache_read\"],t[\"output\"],t[\"source\"])==(40,60,7,\"stdout\")
assert r[\"model\"]==\"gpt-5.6-sol\" and r[\"effort\"]==\"medium\" and r[\"check_ok\"] is True"'
check "bench: 잘못된 label 거부" '! "$HB" bench run "$TMP/tasks.json" --label "../x" --dry-run >/dev/null 2>&1'
"$HB" bench baseline > "$TMP/bl.txt"
BH="$TMP/bench/baseline-home"
check "baseline 미러: 하네스 스킬·서브에이전트 제외, 외부 것은 유지" '[ ! -e "$BH/.claude/skills/bug-fix" ] && [ -e "$BH/.claude/skills/my-ext" ] && [ ! -e "$BH/.agents/skills/bug-fix" ] && [ ! -e "$BH/.claude/agents/git-ops.md" ] && [ -f "$BH/.claude/agents/my-agent.md" ]'
check "baseline 미러: 룰 블록·하네스 훅·Codex 역할 블록 제외, 나머지 설정 유지" '! contains "$BH/.claude/CLAUDE.md" "harness:start" && contains "$BH/.claude/CLAUDE.md" "@RTK.md" && ! contains "$BH/.claude/settings.json" "--harness-hook" && contains "$BH/.claude/settings.json" "PermissionRequest" && ! contains "$BH/.codex/config.toml" "[agents.git-ops]" && contains "$BH/.codex/config.toml" "[mcp_servers.cx]" && ! contains "$BH/.codex/AGENTS.md" "harness:start" && contains "$BH/.codex/AGENTS.md" "# existing codex rules" && ! contains "$BH/.codex/hooks.json" "--harness-hook" && contains "$BH/.codex/hooks.json" "echo hi" && [ ! -e "$BH/.codex/harness" ]'
check "baseline 미러: 세션 로그·기타 항목은 원본 링크" '[ -L "$BH/.claude/projects" ] && [ -L "$BH/.claude.json" ] && [ -L "$BH/.codex/sessions" ] && [ -L "$BH/.local" ]'
check "baseline 미러: 실제 전역 설정은 그대로" 'contains "$HOME/.claude/CLAUDE.md" "harness:start" && [ -L "$HOME/.claude/skills/bug-fix" ] && contains "$CODEX_HOME/config.toml" "[agents.git-ops]"'
check "baseline 보고: 제외 항목 출력" 'contains "$TMP/bl.txt" "하네스 룰 블록 제외" && contains "$TMP/bl.txt" "하네스 훅"'
export SEEN_FILE="$TMP/seen-home.txt"
"$HB" bench run "$TMP/tasks.json" --label bl --baseline --only t1 > "$TMP/bench3.txt" 2>&1
check "run --baseline: 미러 HOME 으로 실행, 상태·로그 토큰 기록" '[ "$(tail -1 "$SEEN_FILE")" = "$BH" ] && python3 -c "
import json; r=json.loads(open(\"$TMP/bench/results/bl.jsonl\").readline())
assert r[\"mode\"]==\"baseline\" and r[\"harness\"]==dict(claude=False, codex=False) and r[\"tokens\"][\"source\"]==\"log\" and r[\"check_ok\"] is True, r"'
"$HB" bench ab "$TMP/tasks.json" --repeat 1 --prefix t > "$TMP/ab.txt" 2>&1
check "ab: baseline → harness 연속 실행 후 비교" '[ -f "$TMP/bench/results/t-baseline.jsonl" ] && [ -f "$TMP/bench/results/t-harness.jsonl" ] && grep -q "^t1 " "$TMP/ab.txt" && contains "$TMP/ab.txt" "claude=off" && contains "$TMP/ab.txt" "claude=on" && ! contains "$TMP/ab.txt" "적용 상태가 같습니다"'
check "ab --dry-run: 실행 계획만" '"$HB" bench ab "$TMP/tasks.json" --repeat 2 --prefix d --dry-run | grep -q "HOME=$BH" && [ ! -f "$TMP/bench/results/d-baseline.jsonl" ]'
"$HB" bench init > /dev/null
check "init 기본 위치 (~/.harness-bench/tasks.json)" '[ -f "$TMP/bench/tasks.json" ]'
check "--agent-cmd: 래퍼 명령 앞에 붙이고 --print 사용" '"$HB" bench run "$TMP/tasks.json" --label w --only t1 --dry-run --agent-cmd "headroom wrap claude --" | grep -q "headroom wrap claude -- --print"'
check "HARNESS_CLAUDE_CMD 환경변수" 'HARNESS_CLAUDE_CMD="mywrap claude --" "$HB" run git --agent claude --print --dry-run -- x 2>/dev/null | grep -q "^mywrap claude -- --model sonnet --print"'
check "bench --help 예시 포함" '"$HB" bench --help | grep -q "harness bench ab --repeat 2"'
unset HARNESS_CLAUDE_BIN HARNESS_CODEX_BIN HARNESS_BENCH_DIR SEEN_FILE

echo "▶ repo-scan: Spring 픽스처"
S="$TMP/spring"; mkdir -p "$S/src/main/java/com/acme/order" "$S/src/main/resources/db/migration" "$S/src/test/java/com/acme"
cat > "$S/build.gradle" <<'EOF'
plugins { id 'org.springframework.boot' version '3.2.5' }
java { sourceCompatibility = JavaVersion.VERSION_17 }
dependencies {
  implementation 'org.springframework.boot:spring-boot-starter-web'
  implementation 'org.springframework.boot:spring-boot-starter-data-jpa'
  implementation 'org.springframework.kafka:spring-kafka'
}
EOF
printf "include 'order-api', 'order-core'\n" > "$S/settings.gradle"
cat > "$S/src/main/java/com/acme/order/OrderController.java" <<'EOF'
@RestController
@RequestMapping("/orders")
class OrderController {
  @GetMapping("/{id}") Order get() { return null; }
  @PostMapping Order create() { return null; }
  @KafkaListener(topics = "payments") void on(String m) {}
}
EOF
printf '@Entity\nclass Order { }\n' > "$S/src/main/java/com/acme/order/Order.java"
printf 'spring.datasource.password: s3cr3t-value\n' > "$S/src/main/resources/application.yml"
printf 'create table orders(id bigint);\n' > "$S/src/main/resources/db/migration/V1__init.sql"
printf 'FROM eclipse-temurin:17\n' > "$S/Dockerfile"
(cd "$S" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init)
bash "$HARNESS_DIR/skills/repo-onboarding/scripts/repo-scan.sh" "$S" > "$TMP/spring.md" 2> "$TMP/spring.err"
check "Spring Boot·Java 버전" 'contains "$TMP/spring.md" "3.2.5" && contains "$TMP/spring.md" "VERSION_17"'
check "의존성·모듈" 'contains "$TMP/spring.md" "JPA" && contains "$TMP/spring.md" "Kafka" && contains "$TMP/spring.md" "order-core"'
check "진입점·데이터" 'contains "$TMP/spring.md" "요청 매핑 메서드 (Spring)**: 3건" && contains "$TMP/spring.md" "Kafka 리스너" && contains "$TMP/spring.md" "Flyway"'
check "시크릿 값 미노출 · stderr 없음" '! contains "$TMP/spring.md" "s3cr3t" && [ ! -s "$TMP/spring.err" ]'

echo "▶ repo-scan: .NET 픽스처"
D="$TMP/dotnet"; mkdir -p "$D/src/Api/Controllers" "$D/src/Infra/Migrations"
cat > "$D/App.sln" <<'EOF'
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Api", "src\Api\Api.csproj", "{1}"
EndProject
Project("{2150E333-8FDC-42A3-9474-1A3956D46DE8}") = "src", "src", "{2}"
EndProject
EOF
cat > "$D/src/Api/Api.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
  <ItemGroup>
    <PackageReference Include="MediatR" Version="12.0.0" />
    <PackageReference Include="Microsoft.EntityFrameworkCore.SqlServer" Version="8.0.0" />
  </ItemGroup>
</Project>
EOF
printf 'var builder = WebApplication.CreateBuilder(args);\nvar app = builder.Build();\napp.MapGet("/health", () => "ok");\n' > "$D/src/Api/Program.cs"
printf '[ApiController]\n[Route("api/[controller]")]\npublic class OrdersController : ControllerBase {\n  [HttpGet] public IActionResult Get() => Ok();\n}\n' > "$D/src/Api/Controllers/OrdersController.cs"
printf 'public class AppDb : DbContext { public DbSet<Order> Orders { get; set; } }\npublic class Worker : BackgroundService { }\n' > "$D/src/Infra/AppDb.cs"
printf '// migration\n' > "$D/src/Infra/Migrations/20240101_Init.cs"
printf '{ "ConnectionStrings": { "Db": "Password=hunter2" } }\n' > "$D/src/Api/appsettings.json"
bash "$HARNESS_DIR/skills/repo-onboarding/scripts/repo-scan.sh" "$D" > "$TMP/dotnet.md" 2> "$TMP/dotnet.err"
check "TargetFramework·NuGet" 'contains "$TMP/dotnet.md" "net8.0" && contains "$TMP/dotnet.md" "MediatR"'
check "솔루션 프로젝트 (폴더 제외)" 'contains "$TMP/dotnet.md" "- Api (" && ! contains "$TMP/dotnet.md" "- src ("'
check "호스트·컨트롤러·Minimal API·BackgroundService" 'contains "$TMP/dotnet.md" "ASP.NET 호스트" && contains "$TMP/dotnet.md" "HTTP 액션" && contains "$TMP/dotnet.md" "Minimal API" && contains "$TMP/dotnet.md" "BackgroundService/HostedService"'
check "DbContext·EF Migrations" 'contains "$TMP/dotnet.md" "EF Core DbContext" && contains "$TMP/dotnet.md" "EF Migrations"'
check "시크릿 값 미노출 · stderr 없음" '! contains "$TMP/dotnet.md" "hunter2" && [ ! -s "$TMP/dotnet.err" ]'

echo
if [ $FAIL -eq 0 ]; then echo "PASS"; else echo "FAIL: ${FAIL}건"; exit 1; fi
