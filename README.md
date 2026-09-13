# knack

백엔드 개발자용 개인 에이전트 하네스입니다. **Claude Code**와 **Codex**의 스킬·룰·훅·서브에이전트를 이 레포 하나에서 관리합니다.
노트북이 바뀌어도 클론한 뒤 `install.sh`를 한 번 실행하면 같은 환경이 됩니다.

## 빠른 시작

```bash
git clone https://github.com/nowgnas/knack.git ~/knack
~/knack/install.sh --dry-run    # 무엇이 바뀌는지 확인
~/knack/install.sh              # 글로벌 적용
knack doctor                    # 점검
knack help                      # 사용법
```

## 무엇을 관리하나

| 종류 | 원본 | Claude Code | Codex |
|---|---|---|---|
| 스킬 | `skills/<name>/SKILL.md` | `~/.claude/skills/<name>` 링크 | `~/.agents/skills/<name>` 링크 |
| 서브에이전트 | `agents/*.md` (`task:`) | `~/.claude/agents/*.md` 생성 (`model:` 포함) | `config.toml`의 `[agents.<이름>]` 역할 + `~/.codex/knack/agents/*.toml` |
| 작업 유형별 모델 | `models.json` | 서브에이전트 모델, `settings.json`의 세션 모델 | 역할 모델·effort, `config.toml`의 세션 모델 |
| 룰 (always) | `rules/*.md` | `~/.claude/CLAUDE.md` 블록에 `@import` | `~/.codex/AGENTS.md` 블록에 본문 |
| 룰 (on-demand) | `rules/*.md` | 블록에 이름·시점 한 줄 | 동일 |
| 훅 | `hooks/<name>/hook.json` + 스크립트 | `~/.claude/settings.json`의 `hooks` | `~/.codex/hooks.json` |
| 페르소나 | `persona/core.md` (gitignore) | 지시 블록 맨 앞에 주입 | 동일 |
| CLI | `bin/knack` | `~/.local/bin/knack` 링크 | 동일 |
| 플러그인·MCP | — | 조회만 (`knack list plugins`, `knack list mcp`) | 조회만 |

- 기존 설정은 보존합니다. 지시 파일은 `<!-- knack:start -->` 블록만, 훅 파일은 `--knack-hook` 표식이 있는 항목만 관리합니다.
- `harness` 에서 개명했습니다. `knack install` 한 번으로 구 블록·훅·링크가 정리되고, `HARNESS_*` 환경변수는 당분간 함께 동작합니다.
- 레포를 고친 뒤 `knack install`을 잊으면 `knack-stale` 훅이 다음 세션 시작 때 알려 줍니다(생성물만 해당. 스킬은 심링크라 즉시 반영).
- 같은 이름이 이미 있으면 `SKIP`합니다. `--force`를 주면 `~/.knack-backups/<시각>/`에 백업한 뒤 교체합니다.
- 하네스에서 지운 항목의 링크는 다음 설치 때 정리됩니다(`PRUNE`).

## 스킬

| 스킬 | 용도 | 예시 요청 |
|---|---|---|
| `repo-onboarding` | 처음 보는 레포 파악 → `.onboarding/` 문서 | "이 레포 파악해줘" |
| `trace-flow` | 엔드포인트·메시지·배치 흐름 추적 | "POST /api/orders 흐름 따라가줘" |
| `feature-implementation` | 정책 점검 → 설계 → **승인 후** 구현 → 검증 → 독립 리뷰 → 요약 | "주문 취소 API 추가해줘" |
| `bug-fix` | 재현 → 원인 입증 → 수정 계획 → 최소 수정 → 영향 데이터 점검 | "이 스택트레이스 원인 찾아서 고쳐줘" |
| `impl-review` | 구현 맥락이 없는 리뷰어의 독립 리뷰 | "머지 전에 내 변경사항 리뷰해줘" |
| `knack-manage` | 스킬·룰·훅 조회·추가·설치 | "이 스킬 설치해줘" |
| `knack-help` | 사용법 안내 ([USAGE.md](skills/knack-help/USAGE.md)) | "하네스 사용법 알려줘" |

## 토큰을 아끼는 조회

에이전트가 문서를 통째로 읽지 않도록, 조회는 `lib/knack.py`가 짧게 잘라서 돌려줍니다.

```bash
knack list                                        # 항목과 설치 상태 (한 줄씩)
knack list skills --all                           # 외부·플러그인 스킬까지 → 중복 확인
knack show skill feature-implementation --toc     # 목차와 섹션별 줄 수
knack show skill feature-implementation --section 5
knack show ref db-migration --section "락"
knack search "expand" -l
```

always 룰은 매 세션 로드되므로 짧게 유지합니다. 가끔 필요한 규칙은 on-demand 룰로 두면 지시 파일에는 한 줄 색인만 들어갑니다.

## 관리 명령

```bash
knack add skill https://github.com/owner/repo.git --subdir skills/foo   # 외부 스킬 추가
knack new skill my-skill | new rule team-style | new hook my-hook       # 뼈대 생성
knack adopt skill dev-guide                                             # 외부 스킬을 하네스로 이동
knack hook disable guard-agent-config                                   # 훅 끄기
knack install --dry-run && knack install                              # 적용
```

## 측정

```bash
knack usage --since 7d --by skill                   # 스킬별 토큰 사용량 (Claude·Codex 세션 로그)
knack bench init                                    # ~/.knack-bench/tasks.json 생성 → repo·작업 편집
knack bench ab --repeat 2                           # baseline(하네스만 뺀 HOME 미러) → 현재 설정 → 비교표
knack bench baseline                                # baseline 에서 빠지는 항목 확인
```

## 구조

```
rules/                  룰 (frontmatter: name, description, load: always|on-demand, when)
skills/<name>/          에이전트 중립 스킬 (SKILL.md + references/ templates/ scripts/)
agents/                 서브에이전트 (frontmatter task: → models.json 의 작업 유형)
models.json             작업 유형별 모델 라우팅 (티어 → 에이전트별 모델·effort, 세션 기본 모델)
hooks/<name>/           훅 정의(hook.json)와 스크립트
lib/knack.py          조회·관리·훅·모델 동기화 (python3 표준 라이브러리)
lib/usage.py            세션 로그 토큰 집계 (knack usage)
lib/bench.py            작업 세트 조건별 실행·비교 (knack bench)
bench/                  벤치 작업 예시
bin/knack             CLI
install.sh              설치/상태/제거
tests/smoke.sh          임시 HOME에서 설치·조회·관리·훅 검증
```

## 업데이트 · 제거

```bash
knack update       # git pull + 재설치
knack uninstall    # 하네스가 만든 링크·블록·훅만 제거
```
