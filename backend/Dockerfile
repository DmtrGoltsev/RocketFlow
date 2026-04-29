FROM maven:3.9-eclipse-temurin-21 AS build

WORKDIR /workspace

COPY pom.xml ./
COPY src ./src

RUN mvn -B -Dmaven.test.skip=true package \
    && cp target/rocketflow-backend-*.jar target/app.jar

FROM eclipse-temurin:21-jre

WORKDIR /app

COPY --from=build /workspace/target/app.jar ./app.jar

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
