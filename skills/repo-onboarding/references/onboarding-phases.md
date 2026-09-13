# 온보딩 단계별 절차

repo-onboarding 스킬의 세부 절차. `harness show ref onboarding-phases --section <번호>`로 필요한 단계만 읽는다.

## 0. 지문 채취
- 스크립트 출력(`scan.md`)으로 스택을 판별하고, 해당 스택 참조 문서를 필요한 섹션만 읽는다.
- 스캔 결과는 정규식 기반 단서다. 이후 단계에서 실제 코드로 확인한다.

## 1. 큰 그림
- README, `docs/`, ADR, 위키 링크를 읽는다.
- 모듈/프로젝트 지도: 각 모듈(Gradle subproject, Maven module, .csproj)의 역할과 의존 방향.
- 런타임 구성: 배포되면 무엇이 뜨는가(API 서버, 워커, 배치)와 붙는 인프라(DB, MQ, 캐시, 외부 API).
- 아키텍처 스타일: 레이어드 / 헥사고날 / Clean Architecture / CQRS 중 무엇에 가까운지, 근거와 함께.

## 2. 진입점
외부에서 코드가 실행되는 모든 입구를 표로 만든다.
- HTTP API (컨트롤러, 라우트), gRPC
- 메시지 컨슈머 (Kafka, RabbitMQ, SQS, Azure Service Bus)
- 스케줄러/배치 (Spring Batch, `@Scheduled`, Quartz, Hangfire, `BackgroundService`)
- CLI/초기화 러너 (`CommandLineRunner`, `IHostedService`)

API가 많으면 컨트롤러/리소스 단위로 묶고 개수를 적는다.

## 3. 핵심 흐름 추적
가장 중요한 비즈니스 흐름을 고른다(사용자 지정 > 호출 빈도가 높아 보이는 것 > 핫스팟 파일이 관여하는 것).
`trace-flow` 절차로 진입점 → 비즈니스 로직 → 데이터 접근 → 부수효과까지 추적해 `.onboarding/flows/<slug>.md`에 저장한다.

## 4. 데이터
- 엔티티/테이블 목록과 핵심 관계 (mermaid `erDiagram`, 핵심 10개 이내)
- 데이터 접근 방식: JPA/MyBatis/jOOQ/JDBC, EF Core/Dapper/ADO.NET
- 마이그레이션 도구와 위치, 트랜잭션 경계가 어디서 잡히는지
- 여러 DB/데이터소스가 있으면 각각의 용도

## 5. 연동
- 외부 API 클라이언트 (Feign, WebClient, RestTemplate, HttpClient/Refit): 대상, 타임아웃, 재시도
- 메시징: 발행/구독 토픽·큐 목록
- 캐시: 무엇을 어떤 키로 얼마나
- 인증/인가: 방식(JWT, 세션, OAuth), 필터/미들웨어 위치

## 6. 운영
- 로컬 실행: 필요한 의존성(docker-compose 등), 실행 명령, 필요한 설정/환경변수 **키 이름**
- 테스트: 종류(단위/통합/Testcontainers), 실행 명령
- 설정/프로파일 체계: 환경별 파일과 오버라이드 순서
- 빌드/배포: CI 파이프라인, 컨테이너, K8s/Helm
- 관측성: 로깅 프레임워크, 메트릭, 트레이싱, 헬스체크

## 7. 리스크와 질문
- 핫스팟(자주 바뀌는 파일)과 크고 복잡한 클래스
- 테스트가 없는 핵심 로직, TODO/FIXME 밀집 구역, deprecated 의존성
- 코드만으로 답할 수 없는 것 → `QUESTIONS.md`

## 병렬 실행
서브에이전트가 있으면 단계 0 결과를 넘겨주고 1·2·4·5단계를 관점별로 병렬 위임한 뒤 결과를 합친다.
각 위임에는 스택, 관심 관점, 반환 형식(`주장 — 근거 file:line`)을 명시한다.

## 작성 규칙
- 모든 사실 주장에 근거 `path:line`. 확인 못 한 것은 `(추정)`.
- 코드 전체를 복붙하지 않는다. 핵심 시그니처나 몇 줄만.
- 산출물: `ONBOARDING.md`(메인), `GLOSSARY.md`(용어↔식별자), `QUESTIONS.md`(질문·추정), `flows/*.md`, `scan.md`.
