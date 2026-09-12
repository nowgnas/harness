# 백엔드 버그의 흔한 원인 (Java/Spring · .NET)

증상에서 출발해 해당 분류의 원인 후보를 가설 목록에 올리고 검증한다.

## 트랜잭션
- **Spring**: 같은 클래스 안에서 호출해 `@Transactional`이 적용되지 않음(self-invocation, 프록시 우회)
- **Spring**: checked 예외는 기본적으로 롤백되지 않음 (`rollbackFor` 확인)
- **Spring**: `readOnly` 트랜잭션에서 쓰기, `REQUIRES_NEW`로 인한 부분 커밋
- **.NET**: `SaveChanges` 누락, 여러 `DbContext` 인스턴스에 걸친 작업, `TransactionScope`와 async 조합(`TransactionScopeAsyncFlowOption`)
- 트랜잭션 안에서 외부 API 호출 → 롤백돼도 외부 호출은 되돌려지지 않음

## 영속성 · ORM
- **JPA**: `LazyInitializationException`(OSIV 꺼짐, 트랜잭션 밖 접근), dirty checking으로 의도하지 않은 UPDATE, 엔티티 `equals/hashCode`, `@Modifying` 쿼리 뒤 영속성 컨텍스트가 오래된 상태
- **EF Core**: 추적/비추적(`AsNoTracking`) 혼동, 같은 키의 엔티티를 두 번 attach, cascade delete, `Include` 누락으로 null 탐색 속성
- **MyBatis**: `resultMap` 매핑 누락, `#{}` 대신 `${}` 사용(인젝션·타입 문제), 동적 SQL 조건 누락

## 동시성
- 확인 후 실행(check-then-act) 경쟁 상태: 중복 생성, 재고 음수
- 싱글톤 빈이나 서비스에 가변 필드
- `@Async`나 스레드풀로 넘어가면 SecurityContext, MDC, 트랜잭션이 전파되지 않음
- **.NET**: Singleton이 Scoped 서비스를 캡처(DbContext 공유), `async void`, `.Result`/`.Wait()` 교착, `DbContext` 동시 사용 예외

## 시간
- 타임존: `LocalDateTime`과 `Instant`/`ZonedDateTime` 혼용, JVM·DB 세션·컨테이너 타임존 차이
- 월말, 윤년, 서머타임, 날짜 경계(자정) 처리
- **.NET**: `DateTime.Now` vs `UtcNow`, `DateTimeKind` 불일치, `DateTimeOffset` 변환

## 숫자 · 금액
- 금액에 `double`/`float` 사용, `BigDecimal`을 `equals`로 비교(스케일 차이), 반올림 모드 불일치
- 정수 오버플로(`int` 합계), `decimal` 스케일 손실

## 문자열 · 인코딩
- 대소문자·공백·유니코드 정규화(NFC/NFD, 한글 자모 분리) 차이로 비교 실패
- EUC-KR과 UTF-8 혼용(레거시 연동, 파일)
- **.NET**: 문화권 의존 비교(`ToUpper()`, `string.Compare`의 CultureInfo), 소수점 구분자

## 직렬화
- 알 수 없는 필드 때문에 역직렬화 실패, enum에 새 값 추가, 날짜 포맷, null과 필드 누락의 구분
- **Jackson**: `FAIL_ON_UNKNOWN_PROPERTIES`, 기본 생성자 없음 / **.NET**: System.Text.Json 대소문자 정책, Newtonsoft와의 동작 차이

## 캐시
- 무효화 누락으로 오래된 값, 캐시 키 충돌(파라미터 누락)
- **Spring**: `@Cacheable` self-invocation
- 클래스를 바꾼 뒤 캐시에 남아 있던 직렬화 데이터의 호환성

## 설정
- 프로파일·환경별 값 차이, 환경변수 오버라이드, 누락된 기본값
- **Spring**: `@Value` 주입 시점, `@ConfigurationProperties` 바인딩 실패 / **.NET**: `appsettings.{Environment}.json` 우선순위, `IOptions` vs `IOptionsSnapshot`

## 메시징
- at-least-once 전달로 인한 중복 수신을 멱등하게 처리하지 않음
- 순서 역전(파티션 키), 커밋 전에 발행해서 롤백된 데이터의 이벤트가 나감
- 포이즌 메시지가 무한 재시도됨, DLQ 미설정

## 외부 연동
- 타임아웃 미설정 → 스레드·커넥션 고갈
- 멱등하지 않은 요청을 재시도해 중복 실행(결제 등)
- 커넥션 풀 크기, **.NET**: 요청마다 `new HttpClient()`로 소켓 고갈

## 쿼리
- `= NULL` 비교, 정렬 키가 유일하지 않아 페이징 결과가 불안정
- IN 절 파라미터 개수 제한, 암묵적 형변환으로 인덱스를 타지 않음, 격리 수준에 따른 조회 결과 차이

## 환경 차이
- 로컬 H2/SQLite와 운영 DB의 방언 차이
- OS 경로 구분자, 파일 시스템 대소문자 구분
- 컨테이너 메모리 제한과 JVM·GC 설정
