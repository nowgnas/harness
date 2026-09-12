---
name: trace-flow
description: 백엔드 요청 흐름 하나를 진입점부터 끝까지 추적한다. API 엔드포인트(예 "POST /orders"), 메시지 토픽/큐, 배치 잡, 특정 메서드가 어디서 시작해 어떤 서비스·DB·외부 호출·이벤트를 거치는지 시퀀스로 정리. "이 API 어떻게 동작해", "흐름 따라가줘", "호출 흐름", "trace this endpoint" 같은 요청에 사용. Java/Spring, .NET 지원.
---

# Trace Flow

하나의 실행 흐름을 진입점부터 응답/종료까지 추적해 시퀀스 문서로 만든다.

## 입력
- HTTP: `METHOD /path` (예: `POST /api/orders`)
- 메시지: 토픽/큐 이름 또는 컨슈머 클래스
- 배치/스케줄: 잡 이름 또는 클래스
- 메서드: `ClassName.method`

입력이 모호하면 후보를 찾아 제시하고 하나를 고르게 한다.

## 절차

1. **진입점 찾기**
   - Spring: 클래스 레벨 `@RequestMapping` + 메서드 레벨 매핑을 합쳐서 경로를 맞춘다. `server.servlet.context-path`도 확인한다.
   - .NET: `[Route("api/[controller]")]` 토큰 치환, `MapGroup` 접두사, 컨벤션 라우팅(`MapControllerRoute`)을 고려한다.
   - 메시지: `@KafkaListener(topics=...)`, `IConsumer<T>`, 토픽 이름이 설정값(`${...}`, `IOptions`)이면 설정 파일까지 따라간다.

2. **진입 전 공통 처리** — 요청이 핸들러에 닿기 전에 거치는 것
   - Filter / Interceptor / AOP(`@Aspect`) / `@ControllerAdvice`
   - ASP.NET 미들웨어 파이프라인 (`app.Use...` 순서), Action Filter, MediatR `IPipelineBehavior`
   - 인증/인가, 검증(`@Valid`, FluentValidation), 로깅/트레이싱

3. **호출 체인 따라가기** — 컨트롤러 → 서비스 → 도메인 → 리포지토리
   - 인터페이스는 실제 구현체를 찾는다(구현이 여럿이면 어떤 조건으로 주입되는지: `@Qualifier`, `@Profile`, `@ConditionalOn...`, DI 등록 코드).
   - MediatR `Send(new XCommand)` → `IRequestHandler<XCommand, ...>` 구현체로 점프.
   - Spring 이벤트(`ApplicationEventPublisher` → `@EventListener`/`@TransactionalEventListener`)도 따라간다.

4. **데이터 접근**
   - 실행되는 쿼리: JPA 메서드명 쿼리/`@Query`/Querydsl, MyBatis mapper XML, EF LINQ/`FromSql`, Dapper SQL
   - 대상 테이블, 트랜잭션 경계(`@Transactional` 위치·전파 속성, `SaveChanges`/`BeginTransaction`)
   - N+1, 지연 로딩 가능성이 보이면 표시

5. **부수효과**
   - 외부 API 호출(대상, 타임아웃, 재시도, 서킷브레이커)
   - 이벤트/메시지 발행 (토픽, 트랜잭션 커밋 전/후 여부, 아웃박스 패턴 여부)
   - 캐시 읽기/쓰기/무효화, 파일/스토리지

6. **응답과 실패 경로**
   - 성공 응답 형태(DTO), 주요 예외가 어떤 HTTP 상태/에러코드로 매핑되는지
   - 부분 실패 시 롤백·보상 처리 여부

## 출력

`.onboarding/flows/<slug>.md` (없으면 `mkdir -p .onboarding/flows && printf '*\n' > .onboarding/.gitignore`)에 저장하고 요약을 보고한다.

````markdown
# <흐름 이름> (`POST /api/orders`)

> 기준 커밋: <sha> · 작성일: <YYYY-MM-DD>

## 요약
<3줄 이내: 무엇을 하고, 무엇을 바꾸고, 무엇을 발행하는가>

## 시퀀스
```mermaid
sequenceDiagram
  participant C as Client
  participant API as OrderController
  ...
```

## 단계별 상세
| # | 위치 | 하는 일 | 비고 |
|---|---|---|---|
| 1 | `OrderController.java:42` | 요청 검증 후 서비스 호출 | `@Valid` |

## 데이터 변경
| 테이블/엔티티 | 연산 | 트랜잭션 |
|---|---|---|

## 부수효과
- 이벤트/외부 호출/캐시

## 실패 경로
- 예외 → 응답 매핑

## 관찰 & 리스크
- (근거와 함께)
````

## 규칙
- 모든 단계에 `path:line` 근거. 동적 디스패치 등으로 확정 못 하면 `(추정)`과 후보를 함께 적는다.
- 추적 깊이는 비즈니스 로직까지. 프레임워크/라이브러리 내부로는 들어가지 않는다.
