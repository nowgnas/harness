# harness 레포 작업 가이드

개인용 에이전트 하네스. 원본은 이 레포에만 두고, 각 에이전트 설정 폴더에는 심링크/마커 블록으로 연결한다.

## 구조
- `core/AGENTS.md` — 모든 에이전트에 주입되는 공통 규칙 (짧게 유지. 매 세션 컨텍스트에 로드됨)
- `skills/<name>/SKILL.md` — 에이전트 중립 스킬 (Agent Skills 포맷). 스크립트는 `skills/<name>/scripts/`
- `adapters/<agent>/` — 특정 에이전트 전용 부가물 (예: Claude 서브에이전트)
- `install.sh` — 설치/상태/제거. `tests/smoke.sh` — 스모크 테스트

## 사용자가 "글로벌로 적용/설치/업데이트/제거해줘"라고 하면
1. `./install.sh --dry-run [옵션]`으로 변경 예정 사항을 먼저 보여준다.
2. 사용자 승인 후 `--dry-run` 없이 실행한다.
3. `./install.sh --status`로 결과를 확인해 보고한다.

| 요청 | 명령 |
|---|---|
| 글로벌 설치 | `./install.sh --global` |
| 특정 에이전트만 | `./install.sh --global --agents codex` |
| 특정 레포에만 | `./install.sh --project <path>` |
| 업데이트 | `git pull && ./install.sh --global` (Codex 규칙 블록은 복사본이라 재실행 필요) |
| 제거 | `./install.sh --uninstall [--project <path>]` |

## 규칙
- 스크립트는 macOS 기본 bash 3.2에서 동작해야 한다 (연관 배열, `mapfile`, `${v,,}` 금지).
- 새 스킬을 추가하면 `core/AGENTS.md`의 스킬 목록과 `README.md`를 갱신한다.
- 변경 후 `tests/smoke.sh`를 실행한다.
