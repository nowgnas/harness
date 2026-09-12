# 하네스 사용법

백엔드 개발용 개인 하네스입니다. 요청 문장에 맞는 스킬이 자동으로 선택되고, 직접 부를 수도 있습니다.

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
| 하네스 관리 | "하네스 업데이트해줘", "이 프로젝트에만 하네스 설치해줘" | `harness-install` | — |
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

### 항상 적용되는 공통 규칙
- 주장에는 근거(`path:line`)를 붙이고, 확인하지 못한 것은 `(추정)`으로 표시합니다.
- 레포 컨벤션이 우선입니다. 주석은 "왜"에만 달고, 범위 밖 리팩토링은 하지 않습니다.
- 시크릿 값은 출력하지 않고, 운영 환경에는 쓰지 않습니다. 스키마 변경은 마이그레이션 파일로만 합니다.

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
| `harness help` | 이 사용법 |
| `harness help <스킬>` | 해당 스킬의 상세 절차 (SKILL.md) |
| `harness skills` | 스킬 목록 |
| `harness status` | 설치 상태 |
| `harness update` | `git pull` 후 글로벌 재설치 |
| `harness install [--project <path>] [--agents claude,codex]` | 설치 (기본값: 글로벌) |
| `harness uninstall [--project <path>]` | 제거 |
| `harness scan [경로]` | 레포 지문 스캔 (온보딩 0단계만 빠르게) |
| `harness test` | 스모크 테스트 |
| `harness version` | 설치된 하네스 커밋 |

## 설치 · 업데이트
```bash
git clone https://github.com/nowgnas/harness.git ~/harness && ~/harness/install.sh --global   # 새 노트북
harness update                                                                              # 업데이트
```
설치하거나 업데이트한 뒤에는 새 에이전트 세션부터 반영됩니다.
