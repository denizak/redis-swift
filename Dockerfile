# Build stage
FROM swift:6.0-jammy AS build
WORKDIR /app
COPY . .
RUN swift build -c release

# Runtime stage - use slim variant (200MB smaller than full image)
FROM swift:6.0-jammy-slim
WORKDIR /app

# Install only runtime dependencies
RUN apt-get update && apt-get install -y \
    libcurl4 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/.build/release/redis-swift /app/redis-swift

EXPOSE 6379

CMD ["/app/redis-swift"]
