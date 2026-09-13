---
name: trace-flow
description: API·메시지·배치 하나의 실행 흐름을 진입점부터 DB·외부 호출까지 추적해 시퀀스로 정리한다. "POST /orders 흐름 따라가줘", "trace this endpoint" 같은 요청에 사용.
---

# Trace Flow

하나의 실행 흐름을 진입점부터 응답·종료까지 추적해 시퀀스 문서로 만든다.
입력은 `METHOD /path`, 토픽·큐 이름, 배치 잡, `Class.method`. 모호하면 후보를 찾아 제시하고 고르게 한다.
스택별 세부(Spring, .NET): `harness show ref tracing --section <번호>`.

## 단계
1. 진입점 찾기: 라우팅 결합 규칙, 설정값으로 된 토픽 이름까지
2. 진입 전 공통 처리: 필터, 인터셉터, AOP, 미들웨어, 검증, 인증
3. 호출 체인: 인터페이스는 실제 구현체와 선택 조건까지
4. 데이터 접근: 실행 쿼리, 대상 테이블, 트랜잭션 경계
5. 부수효과: 외부 호출, 이벤트 발행 시점, 캐시
6. 응답과 실패 경로: 예외 → 상태·에러코드, 롤백·보상

## 산출물과 완료 기준
`templates/FLOW.md` 형식으로 `.onboarding/flows/<slug>.md`에 저장한다. 폴더가 없으면 `mkdir -p .onboarding/flows && printf '*\n' > .onboarding/.gitignore`.

완료 = 여섯 단계 모두에 `path:line` 근거가 있고(확정 못 하면 `(추정)`과 후보), 시퀀스 다이어그램이 있으며, 3줄 요약을 보고한 상태.
추적은 비즈니스 로직까지만 하고 프레임워크·라이브러리 내부로는 들어가지 않는다.
