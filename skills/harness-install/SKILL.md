---
name: harness-install
description: 개인 하네스(harness 레포)를 에이전트 글로벌 설정이나 특정 프로젝트에 설치·업데이트·상태확인·제거한다. "하네스 글로벌로 적용해줘", "하네스 설치", "하네스 업데이트", "이 프로젝트에 하네스 추가", "하네스 제거", "harness install" 같은 요청에 사용.
---

# Harness Install

## 하네스 위치 찾기
이 SKILL.md는 `<HARNESS>/skills/harness-install/SKILL.md`에 대한 심링크로 설치된다.
```bash
HARNESS="$(cd "$(dirname "$(readlink -f <이 SKILL.md 경로>)")/../.." && pwd)"
```
찾지 못하면 `~/harness`를 확인하고, 그래도 없으면 사용자에게 클론 위치를 묻는다.

## 절차
1. 요청을 명령으로 옮긴다.

   | 요청 | 명령 |
   |---|---|
   | 글로벌 설치/재적용 | `"$HARNESS/install.sh" --global` |
   | 특정 에이전트만 | `--agents claude` / `--agents codex` / `--agents claude,codex` |
   | 현재 프로젝트에만 | `"$HARNESS/install.sh" --project "$PWD"` |
   | 업데이트 | `git -C "$HARNESS" pull --ff-only` 후 `--global` 재실행 |
   | 상태 확인 | `"$HARNESS/install.sh" --status` |
   | 제거 | `"$HARNESS/install.sh" --uninstall` (+ `--project <path>`) |

2. 설정을 바꾸는 명령(설치·업데이트·제거)은 먼저 `--dry-run`으로 실행해 변경 예정 사항을 보여주고, **사용자 승인 후** 실제로 실행한다.
3. 실행 후 `--status` 결과를 요약해 보고한다. 기존 파일과 충돌해 건너뛴 항목(`SKIP`)이 있으면 그대로 알리고, 덮어쓸지(`--force`, 백업 후 교체) 묻는다.
4. 새로 설치된 스킬은 에이전트를 재시작하거나 새 세션에서 인식된다고 안내한다.
