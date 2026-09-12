#!/usr/bin/env bash
# repo-scan.sh — 레포 지문 채취. LLM 없이 스택/구조/진입점 단서를 Markdown으로 출력한다.
# 사용: repo-scan.sh [레포 루트]   (macOS bash 3.2 호환)
# 설정 파일은 경로만 출력하고 내용(시크릿 가능성)은 읽지 않는다.
set -u

ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "디렉터리를 찾을 수 없음: $ROOT" >&2; exit 1; }
ROOT="$(pwd)"

IS_GIT=0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && IS_GIT=1

FILES="$(mktemp)"
trap 'rm -f "$FILES"' EXIT

EXCLUDE_RE='(^|/)(node_modules|\.git|build|target|bin|obj|out|dist|\.gradle|\.idea|\.vs|vendor|\.venv|\.onboarding)/'
if [ $IS_GIT -eq 1 ]; then
  git ls-files -co --exclude-standard | grep -Ev "$EXCLUDE_RE" > "$FILES"
else
  find . -type f | sed 's|^\./||' | grep -Ev "$EXCLUDE_RE" > "$FILES"
fi

SRC_RE='\.(java|kt|kts|scala|groovy|cs|vb|fs|go|py|rb|js|ts|php|rs|sql)$'
BUILD_RE='(^|/)(pom\.xml|[^/]*\.gradle|[^/]*\.gradle\.kts|libs\.versions\.toml)$'

# 경로 정규식에 맞는 파일 목록
paths() { grep -E "$1" "$FILES" 2>/dev/null; }
# 경로 정규식 + 내용 정규식에 맞는 파일 목록
grep_files() {
  paths "$1" | tr '\n' '\0' | xargs -0 grep -lE "$2" /dev/null 2>/dev/null
}
# 경로 정규식 + 내용 정규식에 맞는 줄 수
count_matches() {
  paths "$1" | tr '\n' '\0' | xargs -0 grep -hE "$2" /dev/null 2>/dev/null | wc -l | tr -d ' '
}
# 목록을 "a, b, c 외 N개" 형태로
sample() {
  awk -v max="${1:-5}" '{ if (NR <= max) s = s (NR > 1 ? ", " : "") "`" $0 "`" } END { if (NR > max) s = s " 외 " NR - max "개"; print s }'
}

has_path() { [ -n "$(paths "$1" | head -1)" ]; }

# 규칙 테이블 처리. 형식: 모드~라벨~경로정규식~내용정규식
#   모드 f: 매칭 파일 수 / m: 매칭 줄 수 / p: 경로만(내용 정규식 없음)
run_rules() {
  local found=0 mode label pre cre n list
  while IFS='~' read -r mode label pre cre; do
    [ -z "$mode" ] && continue
    case "$mode" in
      p) list="$(paths "$pre")" ;;
      *) list="$(grep_files "$pre" "$cre")" ;;
    esac
    [ -z "$list" ] && continue
    n="$(printf '%s\n' "$list" | wc -l | tr -d ' ')"
    if [ "$mode" = m ]; then
      echo "- **$label**: $(count_matches "$pre" "$cre")건 / ${n}파일 — $(printf '%s\n' "$list" | sample 3)"
    else
      echo "- **$label**: ${n}파일 — $(printf '%s\n' "$list" | sample 4)"
    fi
    found=1
  done
  [ $found -eq 0 ] && echo "- (탐지된 항목 없음)"
}

JAVA='\.(java|kt)$'
CS='\.cs$'

# ─────────────────────────────────────────────
echo "# Repo Scan: $(basename "$ROOT")"
echo
echo "- 경로: \`$ROOT\`"
echo "- 스캔 시각: $(date '+%Y-%m-%d %H:%M')"
echo "- 대상 파일 수: $(wc -l < "$FILES" | tr -d ' ') (빌드 산출물/의존성 디렉터리 제외)"
echo "> 이 결과는 정규식 기반 단서다. 사실 여부는 실제 코드로 확인할 것."
echo

echo "## Git"
if [ $IS_GIT -eq 1 ]; then
  remote="$(git remote get-url origin 2>/dev/null | sed -E 's#(://)[^@/]+@#\1#')"
  echo "- origin: ${remote:-(없음)}"
  echo "- 브랜치: $(git branch --show-current 2>/dev/null)"
  if git rev-parse HEAD >/dev/null 2>&1; then
    echo "- HEAD: \`$(git rev-parse --short HEAD)\` $(git log -1 --format='%ad %s' --date=short)"
    echo "- 총 커밋: $(git rev-list --count HEAD) (최초 $(git log --reverse --format=%ad --date=short | head -1))"
    echo "- 최근 90일 커밋: $(git rev-list --count --since='90 days ago' HEAD)"
    contrib="$(git shortlog -sn --since='6 months ago' HEAD 2>/dev/null | head -5 | sed 's/^ */  - /')"
    if [ -n "$contrib" ]; then
      echo "- 최근 6개월 주요 기여자 (문의 대상 후보):"
      printf '%s\n' "$contrib"
    else
      echo "- 최근 6개월 주요 기여자: 없음"
    fi
  fi
else
  echo "- git 저장소 아님"
fi
echo

echo "## 파일 구성 (확장자 상위)"
sed -n 's/.*\.\([A-Za-z0-9]*\)$/\1/p' "$FILES" | tr 'A-Z' 'a-z' | sort | uniq -c | sort -rn | head -12 |
  awk '{ printf "- .%s: %s\n", $2, $1 }'
echo

echo "## 빌드 · 매니페스트"
run_rules <<'EOF'
p~Maven~(^|/)pom\.xml$~
p~Gradle~(^|/)(build|settings)\.gradle(\.kts)?$~
p~Gradle 버전 카탈로그~libs\.versions\.toml$~
p~.NET 솔루션~\.sln$~
p~.NET 프로젝트~\.(csproj|fsproj|vbproj)$~
p~.NET 공통 빌드 설정~(^|/)(Directory\.(Build|Packages)\.props|global\.json|NuGet\.config)$~
p~Node~(^|/)package\.json$~
p~Go~(^|/)go\.mod$~
p~Python~(^|/)(pyproject\.toml|requirements[^/]*\.txt|setup\.py)$~
p~Makefile~(^|/)Makefile$~
EOF
echo

# ── Java / Kotlin ─────────────────────────────
if has_path "$BUILD_RE"; then
  echo "## Java/Kotlin 스택"
  build_files="$(paths "$BUILD_RE")"
  printf '%s\n' "$build_files" | tr '\n' '\0' |
    xargs -0 grep -hE '(sourceCompatibility|targetCompatibility|JavaLanguageVersion\.of|JavaVersion\.VERSION_|<java\.version>|jvmTarget|<maven\.compiler\.(source|target|release)>|jvmToolchain)' /dev/null 2>/dev/null |
    sed -E 's/^[[:space:]]+//' | sort -u | head -4 | sed 's/^/- Java 버전 단서: `/; s/$/`/'
  boot="$(printf '%s\n' "$build_files" | tr '\n' '\0' |
    xargs -0 grep -hE "org\.springframework\.boot['\"]?\)? +version|spring-?[bB]oot *= *\"|springBootVersion" /dev/null 2>/dev/null | head -1 | sed -E 's/^[[:space:]]+//')"
  if [ -z "$boot" ]; then
    boot="$(paths '(^|/)pom\.xml$' | tr '\n' '\0' |
      xargs -0 grep -hA3 -E 'spring-boot-(starter-parent|dependencies)' /dev/null 2>/dev/null | grep -m1 -oE '<version>[^<]+' | sed 's/<version>/spring-boot /')"
  fi
  [ -n "$boot" ] && echo "- Spring Boot 단서: \`$boot\`"
  deps=""
  for kv in \
    'spring-boot-starter-web:Spring MVC' 'webflux:WebFlux' 'data-jpa:JPA' 'hibernate:Hibernate' \
    'mybatis:MyBatis' 'querydsl:Querydsl' 'jooq:jOOQ' 'spring-boot-starter-jdbc:JDBC' \
    'spring-kafka:Kafka' 'kafka-clients:Kafka' 'amqp:RabbitMQ' 'data-redis:Redis' 'redisson:Redisson' \
    'spring-boot-starter-security:Spring Security' 'oauth2:OAuth2' 'jjwt:JWT' 'openfeign:OpenFeign' \
    'resilience4j:Resilience4j' 'flyway:Flyway' 'liquibase:Liquibase' 'spring-batch:Spring Batch' \
    'boot-starter-batch:Spring Batch' 'quartz:Quartz' 'shedlock:ShedLock' 'actuator:Actuator' \
    'micrometer:Micrometer' 'springdoc:springdoc' 'springfox:Springfox' 'elasticsearch:Elasticsearch' \
    'mongodb:MongoDB' 'grpc:gRPC' 'spring-cloud:Spring Cloud' 'lombok:Lombok' 'mapstruct:MapStruct' \
    'testcontainers:Testcontainers' 'junit-jupiter:JUnit5' 'mockito:Mockito' 'kotest:Kotest' \
    'egovframework:전자정부프레임워크'; do
    key="${kv%%:*}"; name="${kv#*:}"
    if printf '%s\n' "$build_files" | tr '\n' '\0' | xargs -0 grep -qi -- "$key" /dev/null 2>/dev/null; then
      case ", $deps, " in *", $name, "*) ;; *) deps="${deps:+$deps, }$name" ;; esac
    fi
  done
  echo "- 주요 의존성: ${deps:-(키워드 매칭 없음)}"
  mods="$(paths '(^|/)settings\.gradle(\.kts)?$' | tr '\n' '\0' | xargs -0 grep -hE '^[[:space:]]*include' /dev/null 2>/dev/null |
    grep -oE "['\"][^'\"]+['\"]" | tr -d "'\"" | sort -u)"
  [ -z "$mods" ] && mods="$(paths '(^|/)pom\.xml$' | tr '\n' '\0' | xargs -0 grep -hoE '<module>[^<]+' /dev/null 2>/dev/null | sed 's/<module>//' | sort -u)"
  [ -n "$mods" ] && echo "- 모듈 ($(printf '%s\n' "$mods" | wc -l | tr -d ' ')개): $(printf '%s\n' "$mods" | sample 15)"
  echo
fi

# ── .NET ──────────────────────────────────────
if has_path '\.(sln|csproj|fsproj|vbproj)$'; then
  echo "## .NET 스택"
  projs="$(paths '\.(csproj|fsproj|vbproj)$')"
  tf="$(printf '%s\n' "$projs" | tr '\n' '\0' | xargs -0 grep -hoE '<TargetFrameworks?>[^<]+|<TargetFrameworkVersion>[^<]+' /dev/null 2>/dev/null |
    sed -E 's/<[A-Za-z]+>//' | tr ';' '\n' | sort | uniq -c | sort -rn | awk '{ printf "%s%s(%s)", (NR>1?", ":""), $2, $1 }')"
  echo "- TargetFramework: ${tf:-(미확인)}"
  case "$tf" in *v4.*|*net4*) echo "- ⚠️ .NET Framework(레거시) 프로젝트 포함 — Web.config / Global.asax / packages.config 확인" ;; esac
  sdk="$(paths '(^|/)global\.json$' | head -1)"
  [ -n "$sdk" ] && echo "- SDK 고정: \`$sdk\` $(grep -oE '"version"[^,}]*' "$sdk" | head -1)"
  pkgs="$( { printf '%s\n' "$projs"; paths '(^|/)Directory\.Packages\.props$'; } | tr '\n' '\0' |
    xargs -0 grep -hoE '<Package(Reference|Version) +Include="[^"]+"' /dev/null 2>/dev/null |
    sed -E 's/.*Include="([^"]+)"/\1/' | sort | uniq -c | sort -rn | awk '{ print $2 }')"
  [ -n "$pkgs" ] && echo "- NuGet 패키지 ($(printf '%s\n' "$pkgs" | wc -l | tr -d ' ')종, 사용 빈도순): $(printf '%s\n' "$pkgs" | sample 40)"
  sln="$(paths '\.sln$' | head -1)"
  if [ -n "$sln" ]; then
    echo "- 솔루션 \`$sln\` 프로젝트:"
    grep -E '^Project\(.*proj"' "$sln" | sed -E 's/^Project\("[^"]*"\) = "([^"]+)", "([^"]+)".*/  - \1 (`\2`)/' | head -40 | tr '\\' '/'
  fi
  echo
fi

echo "## 진입점"
run_rules <<EOF
f~Spring Boot 메인~$JAVA~@SpringBootApplication
f~컨트롤러 (Spring)~$JAVA~@(RestController|Controller)([^A-Za-z]|$)
m~요청 매핑 메서드 (Spring)~$JAVA~@(Get|Post|Put|Delete|Patch|Request)Mapping
f~WebFlux 라우터~$JAVA~RouterFunction<
f~WebSocket/STOMP~$JAVA~(@EnableWebSocket|WebSocketConfigurer|WebSocketHandler|@MessageMapping|@ServerEndpoint)
f~Kafka 리스너~$JAVA~@KafkaListener
f~RabbitMQ 리스너~$JAVA~@RabbitListener
f~SQS/JMS 리스너~$JAVA~@(SqsListener|JmsListener)
f~스케줄러~$JAVA~@Scheduled
f~Spring Batch~$JAVA~(JobBuilder|@EnableBatchProcessing|StepBuilder)
f~Runner~$JAVA~implements +(CommandLineRunner|ApplicationRunner)
f~gRPC 서비스 (Java)~$JAVA~(ImplBase|@GrpcService)
f~ASP.NET 호스트~$CS~(WebApplication\.CreateBuilder|CreateHostBuilder|CreateDefaultBuilder|UseStartup<)
f~컨트롤러 (ASP.NET)~$CS~(\[ApiController\]|: *(Controller|ControllerBase|ApiController)([^A-Za-z]|$))
m~HTTP 액션 (ASP.NET)~$CS~\[Http(Get|Post|Put|Delete|Patch)
m~Minimal API 라우트~$CS~\.Map(Get|Post|Put|Delete|Patch|Group)\(
f~BackgroundService/HostedService~$CS~: *(BackgroundService|IHostedService)([^A-Za-z]|$)
f~MediatR 핸들러~$CS~(IRequestHandler<|INotificationHandler<)
f~MassTransit/NServiceBus 컨슈머~$CS~(IConsumer<|IHandleMessages<)
f~Hangfire/Quartz.NET 잡~$CS~(RecurringJob\.|BackgroundJob\.|: *IJob([^A-Za-z]|$))
f~gRPC 서비스 (.NET)~$CS~MapGrpcService<
f~SignalR 허브~$CS~: *Hub(<|[^A-Za-z]|$)
p~WCF 서비스 (레거시)~\.svc$~
p~WebForms (레거시)~\.aspx$~
EOF
echo

echo "## 데이터"
run_rules <<EOF
f~JPA 엔티티~$JAVA~@Entity([^A-Za-z]|$)
f~Spring Data 리포지토리~$JAVA~(extends|:) +[A-Za-z]*(Jpa|Crud|PagingAndSorting|Mongo|Reactive[A-Za-z]*)Repository<
f~MyBatis 매퍼 인터페이스~$JAVA~@Mapper([^A-Za-z]|$)
f~MyBatis 매퍼 XML~\.xml$~<mapper
f~Querydsl~$JAVA~JPAQueryFactory
f~jOOQ~$JAVA~DSLContext
m~@Transactional~$JAVA~@Transactional
f~EF Core DbContext~$CS~: *(DbContext|IdentityDbContext)([^A-Za-z]|<|$)
m~DbSet~$CS~DbSet<
f~Dapper~$CS~using Dapper
m~트랜잭션 (.NET)~$CS~(BeginTransaction|TransactionScope)
p~Flyway 마이그레이션~(^|/)db/migration/~
p~Liquibase changelog~changelog[^/]*\.(xml|ya?ml|sql|json)$~
p~EF Migrations~(^|/)Migrations/[^/]*\.cs$~
p~SQL 파일~\.sql$~
EOF
echo

echo "## 연동"
run_rules <<EOF
f~Feign 클라이언트~$JAVA~@FeignClient
f~RestTemplate/WebClient/RestClient~$JAVA~(RestTemplate|WebClient|RestClient)([^A-Za-z]|$)
f~Kafka 발행 (Java)~$JAVA~KafkaTemplate
f~캐시 (Spring)~$JAVA~@(Cacheable|CacheEvict|CachePut)
f~Security 설정 (Spring)~$JAVA~(SecurityFilterChain|WebSecurityConfigurerAdapter|@EnableWebSecurity)
f~HttpClient (.NET)~$CS~(IHttpClientFactory|AddHttpClient|HttpClient\(|RestService\.For|\[Get\(")
f~캐시 (.NET)~$CS~(IDistributedCache|IMemoryCache|IConnectionMultiplexer)
f~인증 설정 (.NET)~$CS~(AddAuthentication|AddJwtBearer|\[Authorize)
f~Polly 재시도 (.NET)~$CS~(Polly|AddResilienceHandler|AddTransientHttpErrorPolicy)
EOF
echo

echo "## 설정 파일 (경로만)"
run_rules <<'EOF'
p~Spring 설정~(^|/)(application|bootstrap)[^/]*\.(ya?ml|properties)$~
p~ASP.NET 설정~(^|/)appsettings[^/]*\.json$~
p~레거시 .NET 설정~(^|/)(Web|App)(\.[A-Za-z]+)?\.config$~
p~환경변수 파일~(^|/)\.env[^/]*$~
p~로깅 설정~(^|/)(logback[^/]*\.xml|log4j2?[^/]*\.(xml|properties)|nlog\.config|serilog[^/]*\.json)$~
p~launchSettings~(^|/)launchSettings\.json$~
EOF
echo

echo "## 인프라 · CI/CD"
run_rules <<'EOF'
p~Dockerfile~(^|/)Dockerfile[^/]*$~
p~docker-compose~(^|/)(docker-)?compose[^/]*\.ya?ml$~
p~Helm 차트~(^|/)Chart\.yaml$~
f~K8s 매니페스트~\.ya?ml$~^kind: *(Deployment|StatefulSet|CronJob|Ingress|ConfigMap)
p~Terraform~\.tf$~
p~GitHub Actions~^\.github/workflows/~
p~Jenkins~(^|/)Jenkinsfile[^/]*$~
p~GitLab CI~(^|/)\.gitlab-ci\.ya?ml$~
p~Azure Pipelines~(^|/)azure-pipelines[^/]*\.ya?ml$~
EOF
echo

echo "## 테스트"
run_rules <<EOF
p~Java/Kotlin 테스트 소스~(^|/)src/test/.*\.(java|kt)$~
f~@SpringBootTest~$JAVA~@SpringBootTest
f~Testcontainers~\.(java|kt|cs)$~(Testcontainers|@Container|ContainerBuilder)
p~.NET 테스트 프로젝트~(Test|Tests|Spec|Specs)[^/]*\.csproj$~
f~.NET 테스트 클래스~$CS~(\[Fact\]|\[Theory\]|\[Test\]|\[TestMethod\])
EOF
echo

echo "## 문서"
run_rules <<'EOF'
p~README~(^|/)README[^/]*$~
p~docs 디렉터리~^docs?/~
p~ADR~(^|/)(adr|ADR|decisions)/~
p~API 명세~(^|/)(openapi|swagger)[^/]*\.(ya?ml|json)$~
p~에이전트 지침~(^|/)(CLAUDE|AGENTS)\.md$~
EOF
echo

echo "## 핫스팟 (최근 6개월 변경 빈도 상위 소스)"
if [ $IS_GIT -eq 1 ] && git rev-parse HEAD >/dev/null 2>&1; then
  hot="$(git log --since='6 months ago' --name-only --pretty=format: 2>/dev/null | grep -E "$SRC_RE" | sort | uniq -c | sort -rn | head -15)"
  if [ -n "$hot" ]; then printf '%s\n' "$hot" | awk '{ printf "- %s회 `%s`\n", $1, $2 }'; else echo "- (최근 6개월 변경 없음)"; fi
else
  echo "- (git 이력 없음)"
fi
echo

echo "## 큰 소스 파일 (줄 수 상위)"
paths "$SRC_RE" | tr '\n' '\0' | xargs -0 wc -l 2>/dev/null | grep -vE ' total$' | sort -rn | head -10 |
  awk '{ printf "- %s줄 `%s`\n", $1, $2 }'
echo

echo "## TODO/FIXME 밀집"
paths "$SRC_RE" | tr '\n' '\0' | xargs -0 grep -cE '(TODO|FIXME|HACK|XXX)' /dev/null 2>/dev/null | grep -v ':0$' |
  sort -t: -k2 -rn | head -5 | awk -F: '{ printf "- %s건 `%s`\n", $2, $1 }'
