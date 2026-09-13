# 하네스 사용법

백엔드 개발용 개인 하네스입니다. 에이전트(Claude Code, Codex)의 **스킬·룰·훅·서브에이전트**를 이 레포 하나에서 관리합니다.
요청 문장에 맞는 스킬이 자동으로 선택되고, 직접 부를 수도 있습니다.

- **Claude Code**: `/스킬이름` (예: `/repo-onboarding quick`)
- **Codex**: 프롬프트에 `$스킬이름`으로 언급하거나 `/skills`에서 선택

## 상황별 사용법

| 상황 | 이렇게 요청 | 스킬 | 결과물 |
|---|---|---|---|
| 처음 보는 레포 | "이 레포 파악해줘", "quick으로 온보딩", "deep 모드로 결제 도메인 위주로" | `repo-onboarding` | `.onboarding/ONBOARDING.md` 외 |
| API 동작 이해 | "POST /api/orders 흐름 따라가줘" | `trace-flow` | `.onboarding/flows/*.md` |
| 새 기능 | "주문 취소 API 추가해줘" (요구사항·정책 문서가 있으면 함께) | `feature-implementation` | `.design/<날짜>-<slug>/DESIGN.md`, `SUMMARY.md` |
| 버그 | "이 에러 원인 찾아서 고쳐줘" + 스택트레이스·로그 | `bug-fix` | `.design/<날짜>-bug-<slug>/BUGFIX.md` |
| 머지 전 리뷰 | "내 변경사항 리뷰해줘" | `impl-review` | `.design/.../REVIEW.md` |
| 스킬·룰·훅 설치·관리 | "이 스킬 설치해줘", "훅 추가해줘", "하네스 업데이트해줘" | `harness-manage` | 하네스 레포 변경 |
| 사용법 | "하네스 사용법 알려줘" | `harness-help` | — |

## 스킬별 요약

### repo-onboarding — 처음 보는 레포 파악
- 모드: `quick`(0~2단계, 5분 내외) / `standard`(기본, 0~6단계) / `deep`(0~7단계, 리스크 분석)
- 단계: 스캔 → 큰 그림 → 진입점 → 핵심 흐름 → 데이터 → 연동 → 운영 → 리스크
- 재실행하면 문서에 기록된 기준 커밋 이후의 변경분만 갱신합니다.

### trace-flow — 요청 흐름 추적
- 입력: `METHOD /path`, 토픽·큐 이름, 배치 잡, `Class.method`
- 출력: 시퀀스 다이어그램, 단계별 표(`path:line`), 데이터 변경, 부수효과, 실패 경로

### feature-implementation — 기능 구현
```
요구사항 정리 → 정책 점검(✅/❓/⚠️) → 컨벤션 파악 → 구현 설계
  → [게이트] 질문 해소 + 설계 승인 + 테스트 계획 합의
  → 구현 → 검증 → 독립 리뷰 → 핵심 구현 요약
```
- 게이트를 통과하기 전에는 코드를 수정하지 않습니다. 설계가 괜찮으면 "진행해"처럼 **명시적으로 승인**해 주세요.
- 승인 뒤에는 로컬 빌드·테스트·린트 실행과 실패 수정을 묻지 않고, 완료 기준(테스트·린트 통과, 독립 리뷰 반영, 요약)까지 진행한 다음 한 번 보고합니다.
- 작은 변경은 경량 모드로, 설계를 5줄로 요약해 확인받습니다. "설계 없이 바로 해줘"라고 하면 게이트를 건너뜁니다(가정은 요약에 남음).
- 스키마가 바뀌면 DB 마이그레이션 가이드(expand → contract, 락, 롤백)가 설계에 적용됩니다.

### bug-fix — 버그 수정
- 원인을 입증하기 전에는 고치지 않습니다. 재현 테스트를 먼저 만듭니다.
- 동작·정책 변경, API·스키마 변경, 데이터 보정, 3개 파일 초과, 추정 수정 중 하나라도 해당하면 승인 후 수정합니다.
- 잘못 저장된 데이터가 있으면 조회 쿼리와 보정 스크립트 **초안**만 만듭니다. 실행은 사람이 합니다.

### impl-review — 독립 리뷰
- 구현 맥락이 없는 리뷰어가 diff를 설계 문서, 레퍼런스 기능, 체크리스트와 대조합니다.
  - Claude: `impl-reviewer` 서브에이전트
  - Codex: `codex exec -s read-only` 새 세션
- 심각도는 🔴 Blocker · 🟠 Major · 🟡 Minor · ⚪ Nit · ❔ 질문 다섯 단계입니다. 🔴·🟠는 반영하고, 리뷰는 최대 2라운드까지 합니다.

### harness-manage — 스킬·룰·훅 관리
- 스킬을 설치할 때 에이전트 폴더에 바로 넣지 않고 하네스에 추가한 뒤 `harness install`로 연결합니다.
- 설치 전에 `harness list --all`로 하네스와 외부에 이미 있는 스킬(같은 이름, 플러그인 스킬 포함)을 확인합니다.
- 에이전트 폴더에 직접 설치하려고 하면 `guard-agent-config` 훅이 막고 하네스 명령을 안내합니다.

## 룰과 훅

| 종류 | 위치 | 적용 방식 |
|---|---|---|
| always 룰 | `rules/*.md` (`load: always`) | Claude: `CLAUDE.md`에 import / Codex: `AGENTS.md`에 본문 블록. 매 세션 로드되므로 짧게 유지 |
| on-demand 룰 | `rules/*.md` (`load: on-demand`, `when:`) | 지시 파일에는 이름과 시점 한 줄만 들어가고, 본문은 필요할 때 `harness show rule <이름>`으로 읽음 |
| 훅 | `hooks/<이름>/hook.json` + 스크립트 | `settings.json`(Claude), `hooks.json`(Codex)에 `--harness-hook` 표식이 붙은 항목만 추가·제거. 다른 훅은 건드리지 않음 |

기본 훅 `guard-agent-config`는 `~/.claude/skills`, `~/.agents/skills`, `~/.codex/skills`, `~/.claude/agents`에 직접 쓰는 것을 막습니다. 하네스로 이어지는 링크를 통한 수정은 허용합니다. 끄려면 `harness hook disable guard-agent-config` → `harness install`.

## 작업 유형별 모델

`models.json`이 작업 유형(설계·구현·리뷰·탐색·git·문서·조회)마다 쓸 모델을 정합니다. 작업은 티어(deep / standard / fast)에 묶이고, 티어는 에이전트별 모델로 이어집니다. 현재 표는 `harness model`로 확인합니다.

| 적용 방식 | Claude Code | Codex |
|---|---|---|
| 위임 서브에이전트 (`agents/*.md`의 `task:`) | `~/.claude/agents/*.md`를 `model:`을 넣어 생성 | `~/.codex/config.toml`에 `[agents.<이름>]` 역할, `~/.codex/harness/agents/*.toml`에 모델·effort |
| 세션 기본 모델 (`main`) | `~/.claude/settings.json`의 `model` | `~/.codex/config.toml`의 `model`, `model_reasoning_effort` |
| 지시 파일 블록 | "커밋·푸시·PR → `git-ops`에 위임" 같은 색인 몇 줄 | 동일 (`spawn_agent`로 위임) |

- 커밋·푸시·PR은 `git-ops`, 탐색은 `repo-explorer`, 독립 리뷰는 `impl-reviewer`에 위임되고, 설계·구현은 세션 모델로 진행합니다.
- 스크립트로 고르기: `harness model which "<요청>"`(키워드 분류), `harness model get <작업> --agent codex --format flags`, `harness run auto -- "<요청>"`(맞는 모델로 새 세션 실행).
- 바꾸기: `harness model set git haiku --agent claude`, `harness model set implement deep`, `harness model set main deep --agent codex` → `harness install`.

## 토큰 사용량 측정과 비교

| 명령 | 용도 |
|---|---|
| `harness usage [--since 7d] [--agent claude\|codex] [--here] [--by session\|model\|day\|skill\|cwd]` | 두 에이전트의 세션 로그에서 토큰(입력·캐시 쓰기·캐시 읽기·출력)과 가중 환산값을 집계 |
| `harness bench init` → `harness bench ab --repeat 2` | 같은 작업 세트를 baseline(하네스 제외)과 현재 설정으로 연달아 실행하고 토큰·check 통과율·턴·시간 비교표 출력 |
| `harness bench run [--baseline] --label <조건>` · `harness bench compare <A> <B>` | 조건 하나씩 실행하고 원하는 두 조건 비교 |

- weighted는 입력 토큰 기준 가중합입니다(캐시 읽기 0.1배, 출력 5~8배). 달러가 아닌 상대 비교용이며 `models.json`의 `usage_weights`에서 조정합니다.
- 벤치는 작업마다 git worktree를 만들어 비대화 모드(`claude -p`, `codex exec`)로 실행하고 끝나면 정리합니다(`--keep`으로 보존).
- 작업 파일 기본 위치는 `~/.harness-bench/tasks.json`입니다(`harness bench init`으로 생성).
- baseline은 전역 설정을 건드리지 않고 `~/.harness-bench/baseline-home`의 HOME 미러로 실행합니다. 하네스 스킬·서브에이전트, 지시 파일의 harness 블록, 하네스 훅, Codex 역할 블록만 빠지고 인증·프록시 설정·캐시·세션 로그 폴더는 원본 링크입니다. 빠지는 항목은 `harness bench baseline`으로 확인합니다.
- 에이전트에게 "하네스 벤치 돌려줘, repeat 2"라고 하면 `harness-manage` 절차로 작업 파일을 확인하고 `harness bench ab --repeat 2`를 실행합니다. 오래 걸리므로 Claude는 백그라운드로 실행하고, Codex는 샌드박스 밖 작업이라 명령을 안내합니다.
- 에이전트는 PATH의 `claude`/`codex` 바이너리로 실행됩니다(셸 함수·별칭은 적용되지 않음). headroom 같은 래퍼를 거치려면 `--agent-cmd 'headroom wrap claude --'` 또는 환경변수 `HARNESS_CLAUDE_CMD`를 씁니다. `harness run`도 같은 환경변수를 따릅니다.
- 비대화 실행에는 CLI 로그인이 필요합니다. `401 authentication_error`가 나면 터미널에서 `claude`(또는 `codex`)를 실행해 로그인한 뒤 다시 시도합니다.
- 모든 옵션: `harness bench --help`, `harness bench ab --help`
- 비대화 모드에서는 설계 게이트에서 멈추므로 벤치 프롬프트에 "설계는 승인된 것으로 보고 진행"처럼 적습니다(`bench/tasks.example.json` 참고).
- Claude는 기본 `--permission-mode acceptEdits`라 셸 명령이 막힐 수 있습니다. 테스트 실행이 필요하면 `--agent-args='--allowedTools Bash'`처럼 넘깁니다.

## 항상 적용되는 공통 규칙
- 주장에는 근거(`path:line`)를 붙이고, 확인하지 못한 것은 `(추정)`으로 표시합니다.
- 레포 컨벤션이 우선입니다. 주석은 "왜"에만 달고, 범위 밖 리팩토링은 하지 않습니다.
- 시크릿 값은 출력하지 않고, 운영 환경에는 쓰지 않습니다. 스키마 변경은 마이그레이션 파일로만 합니다.
- 전체 목록: `harness list rules`

## 결과물 위치
대상 레포 안에 만들어지며, 폴더마다 `.gitignore`(`*`)가 있어서 커밋되지 않습니다.
```
.onboarding/   ONBOARDING.md, GLOSSARY.md, QUESTIONS.md, scan.md, flows/
.design/       <날짜>-<slug>/DESIGN.md, SUMMARY.md, REVIEW.md
               <날짜>-bug-<slug>/BUGFIX.md
```

## 터미널 명령 `harness`

| 명령 | 설명 |
|---|---|
| `harness list [skills\|rules\|agents\|hooks\|plugins\|mcp] [--all] [--json]` | 하네스 항목과 설치 상태. `--all`이면 외부 스킬·룰·훅·플러그인·MCP까지 |
| `harness show <skill\|rule\|agent\|hook\|ref\|template\|usage> <이름> [--toc\|--section N\|--path]` | 필요한 부분만 조회 (예: `harness show ref db-migration --section 2`) |
| `harness search <키워드> [-l] [-E]` | 하네스 문서 검색 (`path:line`) |
| `harness doctor` | 구조·중복·설치 상태·환경 점검 |
| `harness add skill <경로\|git URL> [--subdir P] [--name N] [--install]` | 외부 스킬을 하네스에 복사 (출처는 `.harness-source`에 기록) |
| `harness new <skill\|rule\|hook> <이름> [--always]` | 뼈대 생성 (룰은 기본 on-demand, 훅은 기본 꺼짐) |
| `harness adopt skill <이름>` | 에이전트 폴더의 외부 스킬을 하네스로 이동 |
| `harness hook <enable\|disable> <이름>` | 훅 켜기·끄기 (적용은 `harness install`) |
| `harness model [list\|get <작업>\|which "<요청>"\|set …]` | 작업 유형별 모델 조회·분류·변경 |
| `harness run <작업\|auto> [--agent claude\|codex] [--print] -- "<프롬프트>"` | 작업에 맞는 모델로 에이전트 실행 (`--dry-run`: 명령만 출력) |
| `harness usage [--since 7d] [--by session\|model\|day\|skill\|cwd] [--json]` | 세션 로그 기반 토큰 사용량 집계 |
| `harness bench <init\|ab\|run [--baseline]\|compare\|list\|baseline>` | 작업 세트를 조건별로 실행·비교 (`harness bench --help`) |
| `harness install [--dry-run] [--project <path>] [--agents claude,codex] [--force]` | 설치 (기본값: 글로벌) |
| `harness status` / `harness update` / `harness uninstall` | 상태 / git pull 후 재설치 / 제거 |
| `harness help [스킬]` · `harness scan [경로]` · `harness test` · `harness version` | 사용법 · 레포 스캔 · 스모크 테스트 · 버전 |

## 설치 · 업데이트
```bash
git clone https://github.com/nowgnas/harness.git ~/harness && ~/harness/install.sh --global   # 새 노트북
harness update                                                                              # 업데이트
```
설치하거나 업데이트한 뒤에는 새 에이전트 세션부터 반영됩니다.
