# syntax=docker/dockerfile:1.7

# ---------- Stage 1: build ----------
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /workspace
# Copy the POM first (better layer caching); the Maven repo is kept in a BuildKit cache mount
COPY pom.xml .
COPY src ./src
# Unit/integration tests run in the CI pipeline (see .github/workflows/ci-cd.yml);
# the image build only packages the jar.
RUN --mount=type=cache,target=/root/.m2 mvn -B -q -DskipTests package \
 && mv target/todo-summary-assistant-*.jar /workspace/app.jar

# ---------- Stage 2: runtime ----------
FROM eclipse-temurin:17-jre-alpine
# Non-root user (requirement: do not run the container as root)
RUN addgroup -S -g 10001 app && adduser -S -u 10001 -G app -H -s /sbin/nologin app
WORKDIR /app
COPY --from=build --chown=app:app /workspace/app.jar /app/app.jar

USER 10001:10001
EXPOSE 8080

# All configuration is injected at runtime through environment variables
# (SPRING_DATASOURCE_*, COHERE_API_KEY, SLACK_WEBHOOK_URL, ...). See /.env.example
ENV JAVA_OPTS="-XX:MaxRAMPercentage=70 -XX:+ExitOnOutOfMemoryError"

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/actuator/health/liveness || exit 1

# exec so the JVM is PID 1 and receives SIGTERM (graceful shutdown)
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
