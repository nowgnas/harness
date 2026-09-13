# 흐름 추적 세부 절차

trace-flow 스킬의 단계별 세부. `harness show ref tracing --section <번호>`로 필요한 단계만 읽는다.

## 1. 진입점 찾기
- Spring: 클래스 레벨 `@RequestMapping` + 메서드 레벨 매핑을 합쳐 경로를 맞춘다. `server.servlet.context-path`도 확인한다.
- .NET: `[Route("api/[controller]")]` 토큰 치환, `MapGroup` 접두사, 컨벤션 라우팅(`MapControllerRoute`)을 고려한다.
- 메시지: `@KafkaListener(topics=...)`, `IConsumer<T>`. 토픽 이름이 설정값(`${...}`, `IOptions`)이면 설정 파일까지 따라간다.

## 2. 진입 전 공통 처리
- Filter / Interceptor / AOP(`@Aspect`) / `@ControllerAdvice`
- ASP.NET 미들웨어 파이프라인(`app.Use...` 순서), Action Filter, MediatR `IPipelineBehavior`
- 인증/인가, 검증(`@Valid`, FluentValidation), 로깅/트레이싱

## 3. 호출 체인
- 컨트롤러 → 서비스 → 도메인 → 리포지토리 순서로 따라간다.
- 인터페이스는 실제 구현체를 찾는다. 구현이 여럿이면 선택 조건(`@Qualifier`, `@Profile`, `@ConditionalOn...`, DI 등록 코드)을 적는다.
- MediatR `Send(new XCommand)` → `IRequestHandler<XCommand, ...>` 구현체로 점프한다.
- Spring 이벤트(`ApplicationEventPublisher` → `@EventListener`/`@TransactionalEventListener`)도 따라간다.

## 4. 데이터 접근
- 실행되는 쿼리: JPA 메서드명 쿼리/`@Query`/Querydsl, MyBatis mapper XML, EF LINQ/`FromSql`, Dapper SQL
- 대상 테이블, 트랜잭션 경계(`@Transactional` 위치·전파 속성, `SaveChanges`/`BeginTransaction`)
- N+1, 지연 로딩 가능성이 보이면 표시

## 5. 부수효과
- 외부 API 호출(대상, 타임아웃, 재시도, 서킷브레이커)
- 이벤트/메시지 발행(토픽, 트랜잭션 커밋 전/후 여부, 아웃박스 패턴 여부)
- 캐시 읽기/쓰기/무효화, 파일/스토리지

## 6. 응답과 실패 경로
- 성공 응답 형태(DTO), 주요 예외가 어떤 HTTP 상태/에러코드로 매핑되는지
- 부분 실패 시 롤백·보상 처리 여부
