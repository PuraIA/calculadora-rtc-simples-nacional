# ============================================================
# Stage 1: Build do JAR e Geração do Banco SQLite (Flyway)
# ============================================================
FROM maven:3.9-eclipse-temurin-21 AS builder

WORKDIR /build

# 1. Cache das dependências do Maven
COPY pom.xml .
RUN mvn dependency:go-offline --batch-mode

# 2. Baixa os scripts Flyway do repositório oficial da Receita Federal
#    (necessários para gerar o banco SQLite calculadora-pro.db)
RUN git clone --depth 1 --filter=blob:none --sparse \
      https://github.com/ReceitaFederal/calculadora-rtc-regime-regular.git .flyway-src && \
    cd .flyway-src && \
    git sparse-checkout set flyway && \
    cd /build && \
    cp -r .flyway-src/flyway ./flyway && \
    rm -rf .flyway-src

# 3. Gera o banco SQLite (./calculadora/db/calculadora-pro.db)
RUN mkdir -p ./calculadora/db && \
    mvn flyway:migrate \
      -Dflyway.configFiles=./flyway/flyway-pro.conf \
      --batch-mode \
      --errors

# 4. Compila a aplicação e gera o JAR (pulando os testes no build de imagem)
COPY src ./src
RUN mvn package -DskipTests --batch-mode --errors

# ============================================================
# Stage 2: Runtime enxuto com JRE 21
# ============================================================
FROM eclipse-temurin:21-jre-noble

WORKDIR /app

# Copia o banco SQLite gerado e o JAR compilado
COPY --from=builder /build/calculadora/db/calculadora-pro.db ./calculadora/db/calculadora-pro.db
COPY --from=builder /build/target/api-simples-nacional.jar ./app.jar

# Variáveis de ambiente padrão (podem ser sobrescritas no Dokploy)
ENV SPRING_PROFILES_ACTIVE=offline \
    SERVER_PORT=8082 \
    MANAGEMENT_SERVER_PORT=9103 \
    APP_CORS_ALLOWED_ORIGINS=http://localhost:4200 \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"

# Porta principal da API (8082) e porta de métricas/healthcheck (9103)
EXPOSE 8082 9103

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://localhost:${MANAGEMENT_SERVER_PORT}/health || exit 1

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
