FROM swift:6.0-jammy AS build
WORKDIR /app
COPY . .
RUN swift build -c release

FROM swift:6.0-jammy
WORKDIR /app
COPY --from=build /app/.build/release/redis-swift /app/redis-swift
EXPOSE 6379
CMD ["/app/redis-swift"]
