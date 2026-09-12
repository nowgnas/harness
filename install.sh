#!/usr/bin/env bash
# install.sh — 하네스를 에이전트(Claude Code, Codex)에 연결한다.
#   스킬/에이전트: 이 레포를 가리키는 심링크  → git pull 만으로 갱신
#   전역 규칙:     지시 파일에 마커 블록 삽입  → 기존 내용 보존, 재실행해도 결과 동일
# macOS 기본 bash 3.2 호환.
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPPORTED="claude codex"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
MD_START="<!-- harness:start"
MD_END="<!-- harness:end -->"
GIT_START="# harness:start"
GIT_END="# harness:end"

ACTION=install
MODE=global
PROJECT=""
AGENTS=""
DRY=0
FORCE=0
BACKUP_DIR=""
N_SKIP=0
N_CHANGE=0

usage() {
  cat <<EOF
사용법: $(basename "$0") [옵션]

  --global              사용자 전역 설정에 설치 (기본값)
  --project <path>      특정 레포에만 설치 (스킬/에이전트 심링크, .git/info/exclude 등록)
  --agents <list>       대상 에이전트 (쉼표 구분: ${SUPPORTED// /,}). 생략 시 설치된 것 자동 감지
  --status              설치 상태 확인
  --uninstall           제거 (하네스가 만든 심링크와 마커 블록만 제거)
  --dry-run             변경하지 않고 무엇이 바뀔지만 출력
  --force               기존 파일과 충돌 시 백업(~/.harness-backups) 후 교체
  -h, --help            도움말
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --global) MODE=global ;;
    --project) MODE=project; PROJECT="${2:?--project 뒤에 경로가 필요합니다}"; shift ;;
    --agents) AGENTS="$(echo "${2:?--agents 뒤에 목록이 필요합니다}" | tr ',' ' ')"; shift ;;
    --status) ACTION=status ;;
    --uninstall) ACTION=uninstall ;;
    --dry-run) DRY=1 ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "알 수 없는 옵션: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ "$MODE" = project ]; then
  PROJECT="$(cd "$PROJECT" 2>/dev/null && pwd)" || { echo "프로젝트 경로가 없습니다" >&2; exit 1; }
fi

if [ -z "$AGENTS" ]; then
  { [ -d "$HOME/.claude" ] || command -v claude >/dev/null 2>&1; } && AGENTS="claude"
  { [ -d "$CODEX_DIR" ] || command -v codex >/dev/null 2>&1; } && AGENTS="${AGENTS:+$AGENTS }codex"
  [ -z "$AGENTS" ] && { echo "설치된 에이전트를 찾지 못했습니다. --agents 로 지정하세요." >&2; exit 1; }
fi
for a in $AGENTS; do
  case " $SUPPORTED " in *" $a "*) ;; *) echo "지원하지 않는 에이전트: $a (지원: $SUPPORTED)" >&2; exit 2 ;; esac
done

# ── 공통 유틸 ─────────────────────────────────
pretty() { case "$1" in "$HOME"/*) echo "~${1#"$HOME"}" ;; *) echo "$1" ;; esac; }
say() { printf '  %-7s %s\n' "$1" "$2"; }

backup() {  # 원본을 백업 디렉터리로 복사(copy) 또는 이동(move)
  [ -z "$BACKUP_DIR" ] && BACKUP_DIR="$HOME/.harness-backups/$(date +%Y%m%d-%H%M%S)"
  local dst="$BACKUP_DIR${1#"$HOME"}"
  mkdir -p "$(dirname "$dst")"
  if [ "$2" = move ]; then mv "$1" "$dst"; else cp -P "$1" "$dst"; fi
}

# 파일에서 마커 블록을 뺀 내용 (끝의 빈 줄 제거)
strip_block() {
  [ -f "$1" ] || return 0
  awk -v s="$2" -v e="$3" '
    index($0, s) == 1 { skip = 1; next }
    skip && $0 == e   { skip = 0; next }
    skip              { next }
    { buf[++n] = $0 }
    END { while (n > 0 && buf[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print buf[i] }' "$1"
}

# ── 대상별 처리 (ACTION 에 따라 설치/제거/상태) ─────
handle_link() {  # src dst
  local src="$1" dst="$2" cur=""
  [ -L "$dst" ] && cur="$(readlink "$dst")"
  case "$ACTION" in
    status)
      if [ "$cur" = "$src" ]; then say OK "$(pretty "$dst")"
      elif [ -e "$dst" ] || [ -L "$dst" ]; then say CONFLICT "$(pretty "$dst") (하네스가 아닌 파일)"
      else say MISSING "$(pretty "$dst")"; fi ;;
    uninstall)
      case "$cur" in
        "$HARNESS_DIR"/*) N_CHANGE=$((N_CHANGE + 1)); say REMOVE "$(pretty "$dst")"; [ $DRY -eq 1 ] || rm "$dst" ;;
      esac ;;
    install)
      if [ "$cur" = "$src" ]; then say OK "$(pretty "$dst")"; return; fi
      if [ -e "$dst" ] || [ -L "$dst" ]; then
        case "$cur" in
          "$HARNESS_DIR"/*) ;;  # 하네스의 옛 링크 → 교체
          *)
            if [ $FORCE -eq 0 ]; then
              N_SKIP=$((N_SKIP + 1)); say SKIP "$(pretty "$dst") (기존 항목 존재. --force 로 백업 후 교체)"; return
            fi
            say BACKUP "$(pretty "$dst")"; [ $DRY -eq 1 ] || backup "$dst" move ;;
        esac
        [ $DRY -eq 1 ] || rm -f "$dst"
      fi
      N_CHANGE=$((N_CHANGE + 1)); say LINK "$(pretty "$dst") -> $(pretty "$src")"
      [ $DRY -eq 1 ] && return
      mkdir -p "$(dirname "$dst")"
      ln -s "$src" "$dst" ;;
  esac
}

handle_block() {  # file start end content
  local file="$1" start="$2" end="$3" content="$4" base current new hdr
  base="$(strip_block "$file" "$start" "$end")"
  current="$([ -f "$file" ] && cat "$file" || true)"
  hdr="$start (managed by $(pretty "$HARNESS_DIR")/install.sh — 직접 수정 금지)"
  [ "$start" = "$MD_START" ] && hdr="$hdr -->"
  new="$(printf '%s\n%s\n%s' "$hdr" "$content" "$end")"
  [ -n "$base" ] && new="$(printf '%s\n\n%s' "$base" "$new")"
  case "$ACTION" in
    status)
      if [ "$current" = "$new" ]; then say OK "$(pretty "$file") (블록 최신)"
      elif grep -qF "$start" "$file" 2>/dev/null; then say STALE "$(pretty "$file") (블록 갱신 필요 → install.sh 재실행)"
      else say MISSING "$(pretty "$file") (블록 없음)"; fi ;;
    uninstall)
      grep -qF "$start" "$file" 2>/dev/null || return 0
      N_CHANGE=$((N_CHANGE + 1)); say UNBLOCK "$(pretty "$file")"
      [ $DRY -eq 1 ] && return
      backup "$file" copy
      if [ -n "$base" ]; then printf '%s\n' "$base" > "$file"; else : > "$file"; fi ;;
    install)
      if [ "$current" = "$new" ]; then say OK "$(pretty "$file") (블록 최신)"; return; fi
      N_CHANGE=$((N_CHANGE + 1)); say BLOCK "$(pretty "$file") (하네스 블록 추가/갱신)"
      [ $DRY -eq 1 ] && return
      [ -f "$file" ] && backup "$file" copy
      mkdir -p "$(dirname "$file")"
      printf '%s\n' "$new" > "$file" ;;
  esac
}

skill_names() { for d in "$HARNESS_DIR"/skills/*/; do [ -f "$d/SKILL.md" ] && basename "$d"; done; }

# 링크 대상 목록을 "src<TAB>dst" 로 출력
targets_claude() {  # base_dir
  local s f
  for s in $(skill_names); do printf '%s\t%s\n' "$HARNESS_DIR/skills/$s" "$1/skills/$s"; done
  for f in "$HARNESS_DIR"/adapters/claude/agents/*.md; do
    [ -f "$f" ] && printf '%s\t%s\n' "$f" "$1/agents/$(basename "$f")"
  done
}
targets_codex() {  # skills_dir
  local s
  for s in $(skill_names); do printf '%s\t%s\n' "$HARNESS_DIR/skills/$s" "$1/$s"; done
}

process_links() { local src dst; while IFS="$(printf '\t')" read -r src dst; do handle_link "$src" "$dst"; done; }

# ── 실행 ─────────────────────────────────────
case "$ACTION" in
  install) title="설치" ;; uninstall) title="제거" ;; status) title="상태" ;;
esac
echo "하네스 $title — $(pretty "$HARNESS_DIR")"
echo "  모드: $MODE${PROJECT:+ ($(pretty "$PROJECT"))} · 에이전트: $AGENTS$( [ $DRY -eq 1 ] && echo ' · [dry-run: 실제 변경 없음]')"

for agent in $AGENTS; do
  echo
  echo "[$agent]"
  if [ "$MODE" = global ]; then
    case "$agent" in
      claude)
        process_links < <(targets_claude "$HOME/.claude")
        handle_block "$HOME/.claude/CLAUDE.md" "$MD_START" "$MD_END" "@$HARNESS_DIR/core/AGENTS.md" ;;
      codex)
        process_links < <(targets_codex "$HOME/.agents/skills")
        handle_block "$CODEX_DIR/AGENTS.md" "$MD_START" "$MD_END" "$(cat "$HARNESS_DIR/core/AGENTS.md")" ;;
    esac
  else
    case "$agent" in
      claude) process_links < <(targets_claude "$PROJECT/.claude") ;;
      codex)  process_links < <(targets_codex "$PROJECT/.agents/skills") ;;
    esac
  fi
done

# 글로벌 모드: 터미널 명령 harness
if [ "$MODE" = global ]; then
  echo
  echo "[cli]"
  handle_link "$HARNESS_DIR/bin/harness" "$HOME/.local/bin/harness"
  if [ "$ACTION" = install ]; then
    case ":$PATH:" in
      *":$HOME/.local/bin:"*) ;;
      *) echo "  참고: ~/.local/bin 이 PATH에 없습니다. 셸 설정에 export PATH=\"\$HOME/.local/bin:\$PATH\" 를 추가하세요." ;;
    esac
  fi
fi

# 프로젝트 모드: 심링크가 커밋되지 않도록 로컬 전용 exclude 에 등록
if [ "$MODE" = project ] && [ -d "$PROJECT/.git" ]; then
  echo
  echo "[git]"
  excl=""
  for agent in $AGENTS; do
    if [ "$agent" = claude ]; then
      excl="$excl$(targets_claude "/.claude" | cut -f2)"$'\n'
    else
      excl="$excl$(targets_codex "/.agents/skills" | cut -f2)"$'\n'
    fi
  done
  excl="$(printf '%s' "$excl" | sed '/^$/d')"
  # 다른 에이전트 조합으로 재설치해도 이전 항목이 남지 않도록 블록 전체를 교체
  handle_block "$PROJECT/.git/info/exclude" "$GIT_START" "$GIT_END" "$excl"
fi

echo
case "$ACTION" in
  status) ;;
  *)
    [ $DRY -eq 1 ] && echo "dry-run 완료: 변경 예정 ${N_CHANGE}건, 건너뜀 ${N_SKIP}건" ||
      echo "완료: 변경 ${N_CHANGE}건, 건너뜀 ${N_SKIP}건${BACKUP_DIR:+ · 백업: $(pretty "$BACKUP_DIR")}"
    [ "$ACTION" = install ] && [ $DRY -eq 0 ] && [ $N_CHANGE -gt 0 ] && echo "새 에이전트 세션부터 적용됩니다."
    [ "$MODE" = project ] && [ "$ACTION" = install ] && echo "참고: 프로젝트 모드는 스킬만 설치합니다. 공통 규칙(core/AGENTS.md)은 --global 에서 주입됩니다."
    ;;
esac
exit 0
