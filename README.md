# harness

백엔드 개발자용 개인 에이전트 하네스. 원본은 이 레포 하나에만 두고, **Claude Code**와 **Codex**에 심링크와 마커 블록으로 연결합니다.
노트북이 바뀌어도 클론한 뒤 `install.sh`를 한 번 실행하면 같은 환경이 됩니다.

## 빠른 시작

```bash
git clone <this-repo> ~/harness
~/harness/install.sh --dry-run --global   # 무엇이 바뀌는지 확인
~/harness/install.sh --global             # 적용
~/harness/install.sh --status             # 상태 확인
```

에이전트 안에서 요청해도 됩니다. `~/harness`에서 에이전트를 열고 "하네스 글로벌로 적용해줘"라고 하거나, 설치가 끝난 뒤라면 어디서든 `harness-install` 스킬에 요청하면 됩니다.

## 스킬

| 스킬 | 용도 | 예시 요청 |
|---|---|---|
| `repo-onboarding` | 처음 보는 레포 파악 → `.onboarding/`에 문서 생성 | "이 레포 파악해줘", "quick 모드로 온보딩" |
| `feature-implementation` | 정책 점검 → 설계 → **승인 후** 구현 → 검증 → 독립 리뷰 → 요약 | "주문 취소 API 추가해줘" |
| `bug-fix` | 재현(실패 테스트) → 원인 입증 → 수정 계획 → 최소 수정 → 영향 데이터 점검 | "이 스택트레이스 원인 찾아서 고쳐줘" |
| `impl-review` | 구현 맥락이 없는 리뷰어가 diff를 설계·컨벤션·체크리스트로 리뷰 | "머지 전에 내 변경사항 리뷰해줘" |
| `trace-flow` | 엔드포인트/메시지/배치 하나를 끝까지 추적 | "POST /api/orders 흐름 따라가줘" |
| `harness-install` | 하네스 설치·업데이트·제거 | "하네스 업데이트해줘" |
| `harness-help` | 사용법 안내 ([USAGE.md](skills/harness-help/USAGE.md)) | "하네스 사용법 알려줘" |

터미널에서는 `harness help`, `harness skills`, `harness status`, `harness update`, `harness scan <경로>`를 쓸 수 있습니다. 글로벌 설치 시 `~/.local/bin/harness`에 링크됩니다.

`repo-onboarding`은 **Java/Kotlin(Spring)** 과 **.NET(C#, 레거시 .NET Framework 포함)** 에 맞춘 참조 문서를 갖고 있습니다.
0단계는 `repo-scan.sh`가 LLM 없이 스택, 진입점, 데이터, 설정, 핫스팟을 스캔합니다. 단독으로도 쓸 수 있습니다.

```bash
~/harness/skills/repo-onboarding/scripts/repo-scan.sh /path/to/repo
```

### 온보딩 산출물 (대상 레포 안)

```
.onboarding/
├── .gitignore        # "*" — 폴더 전체가 커밋되지 않음
├── ONBOARDING.md     # 메인 문서 (기준 커밋 기록 → 재실행 시 변경분만 갱신)
├── GLOSSARY.md
├── QUESTIONS.md
├── scan.md
└── flows/*.md
```

### 기능 구현 흐름 (`feature-implementation`)

```
요구사항 정리 → 정책 점검(✅/❓/⚠️) → 코드 맥락·컨벤션 파악 → 구현 설계
   → [게이트] 질문 해소 + 설계 승인 + 테스트 계획 합의
   → 구현 → 검증(빌드·테스트·린트) → 독립 리뷰(impl-review) → 핵심 구현 요약
```

- 게이트를 통과하기 전에는 소스 코드를 수정하지 않습니다. 작은 변경은 경량 모드로 설계를 5줄 요약만 하고 확인받습니다.
- 결과는 대상 레포의 `.design/<YYYYMMDD>-<slug>/`에 `DESIGN.md`와 `SUMMARY.md`로 남습니다. 커밋되지 않습니다.
- 컨벤션·가독성 가이드: [conventions.md](skills/feature-implementation/references/conventions.md), [readable-code.md](skills/feature-implementation/references/readable-code.md)
- DB 변경: [db-migration.md](skills/feature-implementation/references/db-migration.md) — expand → contract, DB별 락 주의점, 백필, 롤백
- 독립 리뷰: Claude는 `impl-reviewer` 서브에이전트, Codex는 `codex exec -s read-only` 새 세션으로 실행합니다. 둘 다 안 되면 자체 리뷰로 대신하고 "독립 리뷰 아님"을 표시합니다.

## 설치 위치

| | Claude Code | Codex |
|---|---|---|
| 스킬 (심링크) | `~/.claude/skills/<name>` | `~/.agents/skills/<name>` |
| 서브에이전트 (심링크) | `~/.claude/agents/{repo-explorer,impl-reviewer}.md` | — (`codex exec`로 대체) |
| 공통 규칙 | `~/.claude/CLAUDE.md`에 `@…/core/AGENTS.md` import 블록 | `~/.codex/AGENTS.md`에 `core/AGENTS.md` 내용 블록 |

- 기존 파일 내용은 그대로 두고, `<!-- harness:start -->` ~ `<!-- harness:end -->` 블록만 관리합니다.
- 같은 이름의 스킬이 이미 있으면 `SKIP`합니다. `--force`를 주면 `~/.harness-backups/<시각>/`에 백업한 뒤 교체합니다.
- `--project <path>`는 해당 레포에만 스킬을 링크하고, 링크 경로를 `.git/info/exclude`에 등록합니다(로컬 전용이라 커밋되지 않음).

## 업데이트 · 제거

```bash
git -C ~/harness pull && ~/harness/install.sh --global   # Codex 규칙 블록은 복사본이라 재실행 필요
~/harness/install.sh --uninstall                         # 하네스가 만든 링크/블록만 제거
```

## 구조

```
core/AGENTS.md          모든 에이전트 공통 규칙 (매 세션 로드 — 짧게 유지)
skills/<name>/          에이전트 중립 스킬 (SKILL.md + references/ templates/ scripts/)
adapters/claude/agents/ Claude 전용 서브에이전트
install.sh              설치/상태/제거
tests/smoke.sh          임시 HOME에서 설치·재설치·충돌·제거·스캔 검증
```

## 스킬 추가하기

1. `skills/<name>/SKILL.md`를 만듭니다 (frontmatter `name`, `description` 필수. description에 트리거 문구를 넣습니다).
2. `core/AGENTS.md`의 스킬 목록과 이 README를 갱신합니다.
3. `tests/smoke.sh` → `./install.sh --global` 순서로 실행합니다.
