---
name: knack-help
description: 하네스 사용법 안내 — 스킬·명령·결과물 위치·설치 방법. "하네스 사용법", "knack help" 같은 요청에 사용.
---

# Harness Help

사용법 문서를 통째로 읽지 말고 CLI로 필요한 부분만 조회한다.

1. 전반적인 질문이면 다음을 보여준다.
   - `knack list`: 스킬·룰·훅·서브에이전트와 설치 상태
   - `knack show usage --section "상황별"`: 상황별 사용법 표
2. 특정 주제를 물으면 해당 섹션만 조회한다.
   - 목차: `knack show usage --toc`
   - 스킬 절차: `knack show skill <이름> --toc` 후 `--section <번호|제목>`
   - 터미널 명령: `knack show usage --section "터미널"`
3. 현재 작업 디렉터리 상황에 맞는 다음 요청 예시를 1~2개 제안한다.
   - 예: `.onboarding/`이 없으면 `repo-onboarding`, 커밋되지 않은 변경이 있으면 `impl-review`
4. 설치 상태를 물으면 `knack doctor` 결과를 요약한다.
