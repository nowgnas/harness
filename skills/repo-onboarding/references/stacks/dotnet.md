# .NET (C#) 탐색 가이드

## 스택 판별
| 신호 | 의미 |
|---|---|
| `<TargetFramework>net6.0`~`net9.0` | 현대 .NET (ASP.NET Core) |
| `netcoreapp3.1`, `net5.0` | EOL 런타임 — 리스크로 기록 |
| `<TargetFrameworkVersion>v4.x`, `packages.config`, `Web.config`, `Global.asax` | .NET Framework 레거시 (ASP.NET MVC 5 / Web API 2 / WebForms / WCF) |
| `Program.cs`에 `WebApplication.CreateBuilder` | Minimal hosting (.NET 6+) — DI·미들웨어가 모두 Program.cs에 |
| `Startup.cs` `ConfigureServices` / `Configure` | 구형 호스팅 모델 |
| `Domain` / `Application` / `Infrastructure` / `Api`(`WebApi`) 프로젝트 | Clean Architecture — 의존 방향: Api → Application → Domain, Infrastructure → Application |
| `Directory.Build.props` / `Directory.Packages.props` | 공통 빌드 속성 / 중앙 패키지 버전 관리 |

## 어디부터 볼까
1. `.sln` — 프로젝트 목록과 폴더 구조. 각 `.csproj`의 `<ProjectReference>`로 의존 그래프를 그린다
2. 실행 프로젝트의 `Program.cs`(또는 `Startup.cs`)
   - `builder.Services.Add...` → 무엇이 DI에 등록되나 (확장 메서드 `AddInfrastructure()` 등은 따라 들어간다)
   - `app.Use...` 순서 → 미들웨어 파이프라인 (인증, 예외 처리, CORS, 로깅)
   - `app.Map...` / `MapControllers()` → 라우팅
3. `appsettings.json` + `appsettings.{Environment}.json` — 섹션 이름만 정리 (**연결 문자열·키 값 기록 금지**)
4. `Properties/launchSettings.json` — 로컬 실행 프로파일, 포트, `ASPNETCORE_ENVIRONMENT`

## 유용한 검색 패턴
```bash
git grep -nE '\[ApiController\]|: *ControllerBase' -- '*.cs'
git grep -nE '\[Http(Get|Post|Put|Delete|Patch)|\.Map(Get|Post|Put|Delete|Patch|Group)\(' -- '*.cs'
git grep -nE ': *(BackgroundService|IHostedService)|IConsumer<|RecurringJob\.' -- '*.cs'
git grep -nE 'IRequestHandler<|INotificationHandler<|IPipelineBehavior<' -- '*.cs'
git grep -nE ': *DbContext|DbSet<|OnModelCreating|IEntityTypeConfiguration<' -- '*.cs'
git grep -nE 'Add(Scoped|Transient|Singleton)<' -- '*.cs'
git grep -nE 'AddHttpClient|IHttpClientFactory|RestService\.For' -- '*.cs'
git grep -nE 'Configure<|IOptions(Snapshot|Monitor)?<' -- '*.cs'   # 설정 바인딩
```

## 관점별 포인트
- **라우팅**: `[Route("api/[controller]")]`의 `[controller]`는 클래스명에서 `Controller` 접미사를 뺀 값. `MapGroup` 접두사, API 버저닝(`[ApiVersion]`)
- **CQRS/MediatR**: 컨트롤러는 `_mediator.Send(new XCommand(...))`만 호출 → 실제 로직은 `IRequestHandler<XCommand, T>` 구현체. 공통 처리는 `IPipelineBehavior`(검증, 트랜잭션, 로깅)
- **DI 수명**: Singleton이 Scoped(예: DbContext)를 잡고 있으면 버그 후보
- **EF Core**: `DbContext` 설정(`OnModelCreating`, `IEntityTypeConfiguration`), 관계·인덱스, `Migrations/` 이력, `AsNoTracking`, `Include`(N+1), `SaveChanges` 호출 위치 = 트랜잭션 경계, 동시성 토큰(`RowVersion`)
- **Dapper/ADO.NET**: SQL 문자열 위치, 저장 프로시저 호출(`CommandType.StoredProcedure`) → 로직이 DB에 있을 수 있음
- **메시징**: MassTransit(`IConsumer<T>`, `AddMassTransit` 설정의 엔드포인트), Azure Service Bus, Confluent.Kafka, 재시도/아웃박스 설정
- **백그라운드**: `BackgroundService.ExecuteAsync` 루프, Hangfire 대시보드/잡 등록, Quartz 트리거
- **설정**: Options 패턴(`services.Configure<T>(config.GetSection("X"))`), user-secrets(`UserSecretsId`), Azure Key Vault
- **예외/응답**: 예외 처리 미들웨어, `ProblemDetails`, `IExceptionHandler`(.NET 8), 필터
- **인증/인가**: `AddAuthentication().AddJwtBearer(...)`, `[Authorize(Policy=...)]`, `AddAuthorization` 정책 정의
- **로깅/관측성**: Serilog(`UseSerilog`, sink 설정), OpenTelemetry, `MapHealthChecks`

## 로컬 실행/테스트
```bash
dotnet --info                          # SDK 확인 (global.json 요구 버전과 비교)
dotnet restore && dotnet build
dotnet run --project src/<Api프로젝트> --launch-profile <프로파일>
dotnet test
dotnet ef migrations list --project <Infrastructure> --startup-project <Api>   # dotnet-ef 도구 필요
```

## 레거시 .NET Framework
- 진입: `Global.asax.cs`(`Application_Start`), `App_Start/RouteConfig.cs`, `WebApiConfig.cs`, `FilterConfig.cs`
- DI: Unity / Autofac / Ninject 컨테이너 설정 파일 찾기
- 데이터: EF6(`.edmx` 모델), ADO.NET, 저장 프로시저 비중이 높음
- WCF: `*.svc`, `Web.config`의 `<system.serviceModel>`
- Windows 전용(IIS, Windows 서비스) 여부 → 로컬 실행 가능성(macOS에서 불가)을 QUESTIONS.md에 기록

## 흔한 함정
- 소스 생성기/`partial` 클래스로 코드가 나뉘어 있음
- `async void`, `.Result`/`.Wait()` 동기 블로킹 — 리스크로 기록
- 확장 메서드 기반 DI 등록이 여러 프로젝트에 흩어져 있어 등록 위치 추적이 필요
