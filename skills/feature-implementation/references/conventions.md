# 프로젝트 컨벤션 파악

새 코드는 "원래 이 팀이 쓴 것처럼" 보여야 한다. 일반적인 모범 사례보다 **레포의 관례가 우선**이다.

## 1. 규칙 문서 먼저
`CONTRIBUTING.md`, `CLAUDE.md`, `AGENTS.md`, `docs/`의 컨벤션 문서, PR 템플릿. 명시된 규칙은 코드에서 관찰한 것보다 우선한다.

## 2. 도구 설정
| 스택 | 확인할 파일 |
|---|---|
| 공통 | `.editorconfig`, pre-commit 훅, CI의 lint 단계 |
| Java/Kotlin | `checkstyle*.xml`, spotless·ktlint·detekt 설정(`build.gradle`), `lombok.config`, `sonar-project.properties` |
| .NET | `.editorconfig`(네이밍 규칙 포함), `Directory.Build.props`(`Nullable`, `TreatWarningsAsErrors`, analyzers), `stylecop.json` |

포맷터가 있으면 직접 맞추지 말고 포맷터를 실행한다.

## 3. 레퍼런스 기능 정하기
구현할 기능과 가장 비슷한 기존 기능 1~2개를 골라 **처음부터 끝까지** 읽는다(API → 서비스 → 도메인 → 저장소 → 테스트).
- 같은 모듈 안의 것 > 다른 모듈의 것
- 최근에 작성된 것 > 오래된 것 (레포에 스타일이 섞여 있으면 최근 스타일이 팀의 방향일 가능성이 높다)
```bash
git log --diff-filter=A --name-only --format='%h %ad %s' --date=short -- 'src/main/**' | head -60   # 최근 추가된 파일
```

## 4. 추출할 항목
| 항목 | 예시 |
|---|---|
| 패키지 구조 | 계층별(`controller/service/repository`) vs 도메인별(`order/…`), 헥사고날(`adapter/in`, `application/port`), Clean Architecture 프로젝트 분리 |
| 개발 방법론 | DDD(애그리거트, 값 객체, 도메인 이벤트), CQRS(Command/Query 분리, MediatR), 헥사고날의 의존 방향 규칙 |
| 네이밍 | `XxxService`/`XxxServiceImpl`, `XxxUseCase`, `XxxCommand`/`XxxQuery`, `XxxHandler`, DTO 접미사(`Request`/`Response`/`Dto`) |
| 계층 간 책임 | 비즈니스 규칙의 위치(엔티티 메서드 vs 서비스), 컨트롤러가 어디까지 하는지 |
| 객체 변환 | MapStruct/AutoMapper, 정적 팩토리(`from`, `of`), 생성자, 확장 메서드 |
| 검증 | Bean Validation(`@Valid`), 도메인 내부 검증, FluentValidation |
| 예외·에러 | 커스텀 예외 계층, 에러코드 enum, 전역 핸들러, `ProblemDetails` |
| 응답 형식 | 공통 래퍼(`ApiResponse<T>`) 사용 여부, 페이징 응답 형태 |
| 트랜잭션 | `@Transactional`을 두는 계층, readOnly 관례, Unit of Work |
| DI | 생성자 주입, `@RequiredArgsConstructor`, C# primary constructor |
| 불변성·null | `record`/`final`/`val`, `Optional` 반환 관례, nullable reference types |
| 로깅 | 로거 선언 방식(`@Slf4j`, `ILogger<T>`), 메시지 형식, 구조화 로깅 |
| 테스트 | 프레임워크, 테스트 이름(`메서드_상황_결과`, `@DisplayName` 한글), given-when-then, fixture 방식, mock 사용 범위, 통합 테스트 기반 클래스 |
| 커밋 | 메시지 형식(Conventional Commits, 티켓 접두사), 한 커밋의 크기 |

## 5. 판단 규칙
- 레퍼런스 기능과 **같은 구조로** 만든다. 파일 배치, 클래스 분리 단위, 메서드 순서까지 맞춘다.
- 레포 안에서 스타일이 충돌하면: 같은 모듈의 것 > 최근의 것 순으로 따르고, 어떤 것을 따랐는지 설계에 적는다.
- 관례가 명백히 잘못된 경우(버그, 보안 문제)에도 조용히 바꾸지 않는다. 설계 단계에서 제안하고 결정을 받는다.
- 헥사고날·Clean Architecture에서는 의존 방향(도메인이 인프라에 의존하지 않음)을 반드시 지킨다.
