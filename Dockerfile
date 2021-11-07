FROM eclipse-temurin:17-focal AS openjdk

WORKDIR /app
CMD ["java", "App.java"]
COPY App.java /app/App.java


FROM ghcr.io/graalvm/graalvm-ce:latest as graalvm



FROM openjdk as jdk
