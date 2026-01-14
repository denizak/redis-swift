# Mini Redis in Swift (Learning Project)

This is a **minimal Redis-like server** written in Swift. It supports a tiny subset of Redis commands and the RESP protocol so you can connect with `redis-cli` or `nc`.

## What it supports

- `PING [message]`
- `ECHO message`
- `SET key value`
- `GET key`
- `DEL key`
- `EXISTS key`
- `INCR key`
- `EXPIRE key seconds`
- `TTL key`
- `MSET key value [key value ...]`
- `MGET key [key ...]`
- `LPUSH key value [value ...]`
- `LRANGE key start stop`
- `KEYS pattern`
- `QUIT`

## Step-by-step learning path

### 1) Start a TCP server
- The server uses SwiftNIO (`ServerBootstrap`) to accept TCP connections.
- Look for `RedisHandler` and `Server.run()`.

### 2) RESP basics (Redis Serialization Protocol)
- A command comes in as an array of bulk strings:
  - `*<count>\r\n$<len>\r\n<bytes>\r\n...`
- The parser reads these chunks and converts them to `[String]` commands.
- See `RespParser` in the source.

### 2a) Inline commands (handy for learning)
- You can also send a single line command like `PING` or `SET a b`.
- Inline commands can end with either `\r\n` or `\n`.
- This is useful with `nc` or `telnet`.

### 3) Encode replies
- Redis replies are formatted as:
  - Simple string: `+OK\r\n`
  - Error: `-ERR message\r\n`
  - Integer: `:1\r\n`
  - Bulk string: `$3\r\nfoo\r\n`
  - Null bulk: `$-1\r\n`
- See `RespEncoder`.

### 4) In-memory key/value store
- A `KeyValueStore` holds keys and values in memory.
- A serial `DispatchQueue` makes access thread-safe.

### 5) Command handling
- Commands are handled in `RedisHandler.handle(command:)`.
- Each command maps to a RESP response.

### 6) Basic key expiration
- `EXPIRE` stores a timestamp in memory.
- `TTL` returns seconds remaining, `-1` for no expiry, `-2` if missing/expired.
- Expired keys are cleaned on access (lazy expiration).

### 7) Putting it together
- `RedisHandler` reads bytes from the socket, parses commands, and sends RESP replies.
- Multiple clients can connect at once.

## Try it

Build and run the server:

```bash
swift build
swift run
```

## Linux

Build and run on Linux:

```bash
swift build
swift run
```

## Docker

Build and run with Docker:

```bash
docker build -t mini-redis-swift .
docker run --rm -p 6379:6379 mini-redis-swift
```

### Deploy & use in Docker

Run the container and connect from your host:

```bash
docker run --rm -p 6379:6379 mini-redis-swift
redis-cli -p 6379 PING
```

Or use netcat from your host:

```bash
printf "PING\n" | nc 127.0.0.1 6379
```

## Test harness

Run the unit tests:

```bash
swift test
```

Test with redis-cli (if installed):

```bash
redis-cli -p 6379 PING
redis-cli -p 6379 SET foo bar
redis-cli -p 6379 GET foo
redis-cli -p 6379 EXPIRE foo 5
redis-cli -p 6379 TTL foo
redis-cli -p 6379 MSET a 1 b 2 c 3
redis-cli -p 6379 MGET a b c missing
redis-cli -p 6379 LPUSH mylist a b c
redis-cli -p 6379 LRANGE mylist 0 -1
redis-cli -p 6379 KEYS "*"
```

Test with netcat (no Redis tools required):

```bash
printf "*1\r\n$4\r\nPING\r\n" | nc 127.0.0.1 6379
```

Inline command example:

```bash
printf "PING\n" | nc 127.0.0.1 6379
```

## Next steps (optional)

- Add `EXPIRE` and `TTL` support with a timestamp store.
- Implement `MGET` and `MSET`.
- Add a simple RDB-like snapshot on shutdown.
