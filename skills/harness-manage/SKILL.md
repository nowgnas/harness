---
name: harness-manage
description: 스킬·룰·훅·서브에이전트·모델 라우팅을 하네스로 조회·추가·설치한다. "이 스킬 설치해줘", "하네스 업데이트", "커밋 모델 바꿔줘" 같은 요청에 사용.
---

# Harness Manage

에이전트 설정의 원본은 하네스 레포다. `~/.claude/skills`, `~/.agents/skills`, `~/.claude/agents`,
훅 설정 파일(`~/.claude/settings.json`, `~/.codex/hooks.json`), 지시 파일의 harness 블록에 직접 쓰지 않는다.
직접 쓰려고 하면 `guard-agent-config` 훅이 막는다.

## 1. 조회 — 파일을 읽지 말고 CLI로
| 목적 | 명령 |
|---|---|
| 하네스 항목과 설치 상태 | `harness list` (종류: `skills`, `rules`, `agents`, `hooks`) |
| 외부 항목까지 (중복 확인) | `harness list --all`, `harness list skills --all` |
| 플러그인, MCP 서버 | `harness list plugins`, `harness list mcp` |
| 항목 내용 | `harness show <종류> <이름> --toc` 후 `--section <번호\|제목>` |
| 키워드 | `harness search <키워드>` (`-l`: 파일별 개수만) |
| 구조·작성 기준·설치 점검 | `harness doctor` |
| 작업 유형별 모델 | `harness model` |
| 토큰 사용량·비교 | `harness usage [--by session\|model\|skill]`, `harness bench compare <A> <B>` |

## 2. 요청별 절차
| 요청 | 절차 |
|---|---|
| 외부 스킬 설치 (경로, git URL) | 1) `harness list skills --all`로 같은·비슷한 스킬 확인, 겹치면 알린다 2) `harness add skill <src> [--subdir P] [--name N]` 3) 출력의 "실행 가능한 파일"을 검토해 요약한다 4) 설치 단계로 |
| 새 스킬·룰·훅 만들기 | `harness new skill\|rule\|hook <이름>` → 내용 작성 → 스킬이면 `skills/harness-help/USAGE.md`에 안내 추가 → `harness doctor`로 작성 기준 확인 → `harness test` → 설치 단계로 |
| 외부 스킬을 하네스로 옮기기 | 사용자가 요청할 때만 `harness adopt skill <이름>` → 설치 단계로 |
| 훅 켜기·끄기 | `harness hook enable\|disable <이름>` → 설치 단계로 |
| 작업 유형별 모델 변경 | `harness model`로 현재 표 확인 → `harness model set <작업\|main\|tier:이름> <티어\|모델> [--agent] [--effort]` → 설치 단계로. 새 위임 대상이 필요하면 `agents/`에 `task:`를 가진 서브에이전트를 만든다 |
| 하네스 효과 측정 | `harness bench init` → 작업 파일 작성 → `harness uninstall` 후 `bench run --label baseline`, `harness install` 후 `bench run --label harness` → `bench compare baseline harness` |
| 룰 | always 룰은 매 세션 로드되므로 짧게 쓴다. 가끔 필요한 규칙은 on-demand 룰(`when:`에 읽을 시점)로 만든다 |
| 플러그인·MCP | 하네스는 조회만 한다. 설치는 각 에이전트 명령으로 하되 사용자에게 알린다 |

## 3. 설치 단계
1. `harness install --dry-run`으로 변경 예정 사항을 보여주고, **사용자 승인 후** `harness install`을 실행한다.
   - 특정 레포에만: `--project <path>`. 특정 에이전트만: `--agents claude|codex`.
   - 업데이트: `harness update` (git pull + 재설치). 제거: `harness uninstall`.
2. `harness status`나 `harness doctor`로 결과를 확인해 보고한다.
3. 충돌로 건너뛴 항목(`SKIP`)은 그대로 알리고, 덮어쓸지(`--force`, 백업 후 교체) 묻는다.
4. 하네스 레포를 바꿨으면 `harness test`로 검증한 뒤 커밋을 제안한다. push는 요청이 있을 때만 한다.
5. 새 스킬·룰·훅은 새 에이전트 세션부터 적용된다. Codex는 새 훅을 처음 실행할 때 신뢰 확인을 요청한다.
