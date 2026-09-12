#!/usr/bin/env bash
# smoke.sh — 임시 HOME에서 install.sh 와 repo-scan.sh 를 검증한다. 실제 설정은 건드리지 않는다.
set -u
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" CODEX_HOME="$TMP/home/.codex"
mkdir -p "$HOME/.claude" "$CODEX_HOME"
INSTALL="$HARNESS_DIR/install.sh"
FAIL=0

ok()   { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }
contains() { grep -qF -- "$2" "$1" 2>/dev/null; }

echo "▶ 스킬 구조"
for f in "$HARNESS_DIR"/skills/*/SKILL.md; do
  d="$(dirname "$f")"; s="$(basename "$d")"
  check "$s: frontmatter name 일치" '[ "$(sed -n "s/^name: *//p" "$f" | head -1)" = "$s" ]'
  check "$s: description 존재" 'grep -qE "^description: .{20,}" "$f"'
  missing=""
  for ref in $(grep -oE '(\.\./[a-z-]+/)?(references|templates|scripts)/[A-Za-z0-9_./-]+\.(md|sh)' "$f" | sort -u); do
    [ -e "$d/$ref" ] || missing="$missing $ref"
  done
  check "$s: 참조 파일 존재${missing:+ (없음:$missing)}" '[ -z "$missing" ]'
done
check "USAGE.md 에 모든 스킬 안내" '( for s in $(ls "$HARNESS_DIR/skills"); do grep -q "\`$s\`" "$HARNESS_DIR/skills/harness-help/USAGE.md" || exit 1; done )'
check "core/AGENTS.md 에 모든 스킬 등록" '( for s in $(ls "$HARNESS_DIR/skills"); do grep -q "\`$s\`" "$HARNESS_DIR/core/AGENTS.md" || exit 1; done )'

echo "▶ 글로벌 설치"
printf '@RTK.md\n' > "$HOME/.claude/CLAUDE.md"
printf '# existing codex rules\n' > "$CODEX_HOME/AGENTS.md"
"$INSTALL" --global --agents claude,codex --dry-run > "$TMP/dry.txt"
check "dry-run 은 아무것도 만들지 않음" '[ ! -e "$HOME/.claude/skills" ] && [ "$(cat "$HOME/.claude/CLAUDE.md")" = "@RTK.md" ]'
"$INSTALL" --global --agents claude,codex > "$TMP/out1.txt"
for s in $(ls "$HARNESS_DIR/skills"); do
  check "claude 스킬 링크: $s" '[ "$(readlink "$HOME/.claude/skills/'$s'")" = "$HARNESS_DIR/skills/'$s'" ]'
  check "codex 스킬 링크: $s" '[ "$(readlink "$HOME/.agents/skills/'$s'")" = "$HARNESS_DIR/skills/'$s'" ]'
done
for a in "$HARNESS_DIR"/adapters/claude/agents/*.md; do
  check "claude 서브에이전트 링크: $(basename "$a")" '[ "$(readlink "$HOME/.claude/agents/$(basename "$a")")" = "$a" ]'
done
H="$HOME/.local/bin/harness"
check "harness CLI 링크" '[ "$(readlink "$H")" = "$HARNESS_DIR/bin/harness" ]'
check "harness help (심링크 경유)" '"$H" help | grep -q "하네스 사용법"'
check "harness help <스킬>" '"$H" help bug-fix | grep -q "^name: bug-fix"'
check "harness skills 가 모든 스킬 출력" '[ "$("$H" skills | wc -l | tr -d " ")" = "$(ls "$HARNESS_DIR/skills" | wc -l | tr -d " ")" ]'
check "harness 잘못된 명령은 실패" '! "$H" nope >/dev/null 2>&1'
check "CLAUDE.md 기존 내용 보존" '[ "$(head -1 "$HOME/.claude/CLAUDE.md")" = "@RTK.md" ]'
check "CLAUDE.md import 블록" 'contains "$HOME/.claude/CLAUDE.md" "@$HARNESS_DIR/core/AGENTS.md"'
check "Codex AGENTS.md 기존 내용 보존" 'contains "$CODEX_HOME/AGENTS.md" "# existing codex rules"'
check "Codex AGENTS.md 규칙 블록" 'contains "$CODEX_HOME/AGENTS.md" "Personal Harness — Core Rules"'

echo "▶ 재설치 (멱등성)"
sum1="$(cat "$HOME/.claude/CLAUDE.md" "$CODEX_HOME/AGENTS.md" | cksum)"
"$INSTALL" --global --agents claude,codex > "$TMP/out2.txt"
check "두 번째 실행은 변경 0건" 'contains "$TMP/out2.txt" "변경 0건"'
check "지시 파일 내용 동일" '[ "$sum1" = "$(cat "$HOME/.claude/CLAUDE.md" "$CODEX_HOME/AGENTS.md" | cksum)" ]'
check "블록은 하나만 존재" '[ "$(grep -c "harness:start" "$HOME/.claude/CLAUDE.md")" = 1 ]'

echo "▶ 충돌 처리"
rm "$HOME/.claude/skills/trace-flow"; mkdir -p "$HOME/.claude/skills/trace-flow"; echo mine > "$HOME/.claude/skills/trace-flow/SKILL.md"
"$INSTALL" --global --agents claude > "$TMP/out3.txt"
check "기존 디렉터리는 SKIP" 'contains "$TMP/out3.txt" "SKIP" && [ ! -L "$HOME/.claude/skills/trace-flow" ]'
"$INSTALL" --global --agents claude --force > "$TMP/out4.txt"
check "--force 는 링크로 교체" '[ -L "$HOME/.claude/skills/trace-flow" ]'
check "--force 는 원본 백업" '[ -n "$(find "$HOME/.harness-backups" -path "*trace-flow/SKILL.md" 2>/dev/null)" ]'

echo "▶ 상태"
"$INSTALL" --status --agents claude,codex > "$TMP/status.txt"
check "상태: MISSING/STALE 없음" '! grep -qE "MISSING|STALE|CONFLICT" "$TMP/status.txt"'

echo "▶ 제거"
"$INSTALL" --uninstall --agents claude,codex > "$TMP/out5.txt"
check "claude 스킬 링크 제거" '[ ! -e "$HOME/.claude/skills/repo-onboarding" ]'
check "codex 스킬 링크 제거" '[ ! -e "$HOME/.agents/skills/repo-onboarding" ]'
check "harness CLI 링크 제거" '[ ! -e "$HOME/.local/bin/harness" ]'
check "CLAUDE.md 원상복구" '[ "$(cat "$HOME/.claude/CLAUDE.md")" = "@RTK.md" ]'
check "Codex AGENTS.md 원상복구" '[ "$(cat "$CODEX_HOME/AGENTS.md")" = "# existing codex rules" ]'

echo "▶ 프로젝트 모드"
P="$TMP/proj"; mkdir -p "$P"; git -C "$P" init -q
"$INSTALL" --project "$P" --agents claude,codex > "$TMP/out6.txt"
check "프로젝트 claude 스킬 링크" '[ -L "$P/.claude/skills/repo-onboarding" ]'
check "프로젝트 codex 스킬 링크" '[ -L "$P/.agents/skills/repo-onboarding" ]'
check ".git/info/exclude 등록" 'contains "$P/.git/info/exclude" "/.claude/skills/repo-onboarding"'
check "git status 에 링크가 안 보임" '[ -z "$(git -C "$P" status --porcelain)" ]'
"$INSTALL" --project "$P" --agents claude,codex --uninstall > /dev/null
check "프로젝트 제거" '[ ! -e "$P/.claude/skills/repo-onboarding" ] && ! contains "$P/.git/info/exclude" "harness:start"'

echo "▶ repo-scan: Spring 픽스처"
S="$TMP/spring"; mkdir -p "$S/src/main/java/com/acme/order" "$S/src/main/resources/db/migration" "$S/src/test/java/com/acme"
cat > "$S/build.gradle" <<'EOF'
plugins { id 'org.springframework.boot' version '3.2.5' }
java { sourceCompatibility = JavaVersion.VERSION_17 }
dependencies {
  implementation 'org.springframework.boot:spring-boot-starter-web'
  implementation 'org.springframework.boot:spring-boot-starter-data-jpa'
  implementation 'org.springframework.kafka:spring-kafka'
}
EOF
printf "include 'order-api', 'order-core'\n" > "$S/settings.gradle"
cat > "$S/src/main/java/com/acme/order/OrderController.java" <<'EOF'
@RestController
@RequestMapping("/orders")
class OrderController {
  @GetMapping("/{id}") Order get() { return null; }
  @PostMapping Order create() { return null; }
  @KafkaListener(topics = "payments") void on(String m) {}
}
EOF
printf '@Entity\nclass Order { }\n' > "$S/src/main/java/com/acme/order/Order.java"
printf 'spring.datasource.password: s3cr3t-value\n' > "$S/src/main/resources/application.yml"
printf 'create table orders(id bigint);\n' > "$S/src/main/resources/db/migration/V1__init.sql"
printf 'FROM eclipse-temurin:17\n' > "$S/Dockerfile"
(cd "$S" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init)
bash "$HARNESS_DIR/skills/repo-onboarding/scripts/repo-scan.sh" "$S" > "$TMP/spring.md" 2> "$TMP/spring.err"
check "Spring Boot 버전 탐지" 'contains "$TMP/spring.md" "3.2.5"'
check "Java 17 탐지" 'contains "$TMP/spring.md" "VERSION_17"'
check "의존성 탐지 (JPA, Kafka)" 'contains "$TMP/spring.md" "JPA" && contains "$TMP/spring.md" "Kafka"'
check "모듈 탐지" 'contains "$TMP/spring.md" "order-core"'
check "컨트롤러/매핑 탐지" 'contains "$TMP/spring.md" "컨트롤러 (Spring)" && contains "$TMP/spring.md" "요청 매핑 메서드 (Spring)**: 3건"'
check "Kafka 리스너 탐지" 'contains "$TMP/spring.md" "Kafka 리스너"'
check "JPA 엔티티 / Flyway 탐지" 'contains "$TMP/spring.md" "JPA 엔티티" && contains "$TMP/spring.md" "Flyway"'
check "시크릿 값 미노출" '! contains "$TMP/spring.md" "s3cr3t"'
check "stderr 없음" '[ ! -s "$TMP/spring.err" ]'

echo "▶ repo-scan: .NET 픽스처"
D="$TMP/dotnet"; mkdir -p "$D/src/Api/Controllers" "$D/src/Infra/Migrations"
cat > "$D/App.sln" <<'EOF'
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Api", "src\Api\Api.csproj", "{1}"
EndProject
Project("{2150E333-8FDC-42A3-9474-1A3956D46DE8}") = "src", "src", "{2}"
EndProject
EOF
cat > "$D/src/Api/Api.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
  <ItemGroup>
    <PackageReference Include="MediatR" Version="12.0.0" />
    <PackageReference Include="Microsoft.EntityFrameworkCore.SqlServer" Version="8.0.0" />
  </ItemGroup>
</Project>
EOF
printf 'var builder = WebApplication.CreateBuilder(args);\nvar app = builder.Build();\napp.MapGet("/health", () => "ok");\n' > "$D/src/Api/Program.cs"
printf '[ApiController]\n[Route("api/[controller]")]\npublic class OrdersController : ControllerBase {\n  [HttpGet] public IActionResult Get() => Ok();\n}\n' > "$D/src/Api/Controllers/OrdersController.cs"
printf 'public class AppDb : DbContext { public DbSet<Order> Orders { get; set; } }\npublic class Worker : BackgroundService { }\n' > "$D/src/Infra/AppDb.cs"
printf '// migration\n' > "$D/src/Infra/Migrations/20240101_Init.cs"
printf '{ "ConnectionStrings": { "Db": "Password=hunter2" } }\n' > "$D/src/Api/appsettings.json"
bash "$HARNESS_DIR/skills/repo-onboarding/scripts/repo-scan.sh" "$D" > "$TMP/dotnet.md" 2> "$TMP/dotnet.err"
check "TargetFramework 탐지" 'contains "$TMP/dotnet.md" "net8.0"'
check "NuGet 패키지 탐지" 'contains "$TMP/dotnet.md" "MediatR"'
check "솔루션 프로젝트 목록 (폴더 제외)" 'contains "$TMP/dotnet.md" "- Api (" && ! contains "$TMP/dotnet.md" "- src ("'
check "ASP.NET 호스트/컨트롤러/액션" 'contains "$TMP/dotnet.md" "ASP.NET 호스트" && contains "$TMP/dotnet.md" "컨트롤러 (ASP.NET)" && contains "$TMP/dotnet.md" "HTTP 액션"'
check "Minimal API 탐지" 'contains "$TMP/dotnet.md" "Minimal API"'
check "BackgroundService 탐지" 'contains "$TMP/dotnet.md" "BackgroundService/HostedService"'
check "DbContext / EF Migrations 탐지" 'contains "$TMP/dotnet.md" "EF Core DbContext" && contains "$TMP/dotnet.md" "EF Migrations"'
check "시크릿 값 미노출" '! contains "$TMP/dotnet.md" "hunter2"'
check "stderr 없음" '[ ! -s "$TMP/dotnet.err" ]'

echo
if [ $FAIL -eq 0 ]; then echo "PASS"; else echo "FAIL: ${FAIL}건"; cp "$TMP"/*.md "$TMP"/*.txt "${SMOKE_KEEP:-/dev/null}" 2>/dev/null; exit 1; fi
