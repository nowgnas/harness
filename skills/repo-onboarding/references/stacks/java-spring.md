# Java / Kotlin (Spring) 탐색 가이드

## 스택 판별
| 신호 | 의미 |
|---|---|
| `build.gradle(.kts)` + `settings.gradle` `include` | Gradle 멀티모듈 |
| `pom.xml` `<modules>` | Maven 멀티모듈 |
| `org.springframework.boot` 버전 3.x | Java 17+, `jakarta.*` 패키지 |
| 2.x | Java 8/11, `javax.*` 패키지 |
| `web.xml`, `*-servlet.xml`, `context-*.xml` | XML 설정 기반 레거시 Spring MVC |
| `egovframework` 의존성/패키지 | 전자정부 표준프레임워크 (MyBatis/iBATIS, XML 설정 비중 높음) |
| `libs.versions.toml` | 의존성 버전이 카탈로그로 관리됨 → 버전은 여기서 확인 |

## 어디부터 볼까
1. `@SpringBootApplication` 클래스 — 패키지 루트, `@EnableXxx` 목록(스케줄링, 비동기, 배치, JPA 감사 등)이 기능 목록의 힌트
2. `src/main/resources/application*.yml` — 프로파일, 데이터소스, 외부 URL, 토픽 이름 (**값 중 시크릿은 기록 금지**)
3. `@Configuration` 클래스 목록 — `SecurityConfig`, `WebConfig`, `KafkaConfig`, `DataSourceConfig` 등이 인프라 연결 지점
4. 컨트롤러 패키지 → 서비스 → 리포지토리 순서로 대표 흐름 하나

## 유용한 검색 패턴
```bash
git grep -nE '@(Rest)?Controller' -- '*.java' '*.kt'
git grep -nE '@(Get|Post|Put|Delete|Patch|Request)Mapping' -- '*.java' '*.kt'
git grep -nE '@(KafkaListener|RabbitListener|SqsListener|JmsListener|Scheduled)' -- '*.java' '*.kt'
git grep -nE '@Transactional' -- '*.java' '*.kt'
git grep -nE '@(Entity|Table|Document)\b' -- '*.java' '*.kt'
git grep -nE '@FeignClient|WebClient\.|RestTemplate|RestClient' -- '*.java' '*.kt'
git grep -nE 'implements .*(Filter|HandlerInterceptor)|@Aspect|@(Rest)?ControllerAdvice' -- '*.java' '*.kt'
git grep -nE '@(Conditional|Profile)' -- '*.java' '*.kt'   # 환경별로 달라지는 빈
```

## 관점별 포인트
- **라우팅**: 클래스 `@RequestMapping` + 메서드 매핑 결합, `server.servlet.context-path`, 게이트웨이 접두사
- **DI 분기**: 인터페이스 구현이 여러 개면 `@Primary`, `@Qualifier`, `@Profile`, `@ConditionalOnProperty` 확인
- **트랜잭션**: 클래스/메서드 레벨 `@Transactional`, `readOnly`, `propagation`(REQUIRES_NEW 주의), 같은 클래스 내부 호출은 프록시를 타지 않음(self-invocation)
- **JPA**: 연관관계(`@OneToMany` 등)와 fetch 전략, `@EntityGraph`/fetch join, 벌크 연산, `@Version`, 감사(`@CreatedDate`)
- **MyBatis**: 매퍼 인터페이스 ↔ `resources/**/mapper/*.xml` 의 `namespace`/`id` 매칭, 동적 SQL(`<if>`, `<foreach>`)
- **Querydsl**: `Q*` 클래스는 생성물. 커스텀 리포지토리 `*RepositoryImpl`에 복잡 쿼리
- **이벤트**: `ApplicationEventPublisher.publishEvent` → `@EventListener`/`@TransactionalEventListener` (phase 확인), `@Async` 여부
- **메시징**: 리스너 `containerFactory`, 에러 핸들러/DLT, 수동 커밋(ack) 여부, 컨슈머 그룹 id
- **예외**: `@RestControllerAdvice` 에서 예외 → HTTP 상태/에러코드 매핑 표를 만든다
- **보안**: `SecurityFilterChain` 빈의 `requestMatchers` 규칙, 커스텀 필터 순서, `@PreAuthorize`
- **배치**: `Job` → `Step` → Reader/Processor/Writer, chunk 크기, 재시작/스킵 정책, 잡 파라미터

## 로컬 실행/테스트
```bash
./gradlew bootRun --args='--spring.profiles.active=local'
./gradlew test            # 또는 ./gradlew :<module>:test
./mvnw spring-boot:run -Dspring-boot.run.profiles=local
./mvnw test
```
- `docker-compose.yml`, `src/test/resources/application-test.yml`, Testcontainers 사용 여부로 필요한 인프라 파악
- `bootRun`이 실패하면 필요한 환경변수 **키**와 외부 의존성을 QUESTIONS.md에 적는다

## 흔한 함정
- Lombok/MapStruct/Querydsl 생성 코드는 소스에 없다 → `build/generated` 또는 어노테이션으로 추론
- Kotlin: 확장 함수, `companion object`, 코루틴(`suspend`)으로 호출 흐름이 가려질 수 있음
- 설정값이 Spring Cloud Config / Vault / K8s ConfigMap에서 주입되면 레포의 yml만으로는 불완전
