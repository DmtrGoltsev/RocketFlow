FROM maven:3.9-eclipse-temurin-21@sha256:f192d0389be99807761e2aa70e0fecba8f33918e5762d268ba6643f487eed1e6 AS build

WORKDIR /workspace

COPY pom.xml ./
COPY src ./src

RUN mvn -B -Dmaven.test.skip=true package \
    && cp target/rocketflow-backend-*.jar target/app.jar

FROM eclipse-temurin:21-jre@sha256:bdb940ff345a6f3d074a84c12923668744b39a7037d886c85a4a7608b7e9ba1b

WORKDIR /app

COPY --from=build /workspace/target/app.jar ./app.jar

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
