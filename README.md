# Mini Redis in Swift (Learning Project)

This is a **minimal Redis-like server** written in Swift. It supports a tiny subset of Redis commands and the RESP protocol so you can connect with `redis-cli` or `nc`.

## What it supports

**Strings:**
- `PING [message]`
- `ECHO message`
- `SET key value [EX seconds] [PX milliseconds]` — set with optional expiration
- `GET key`
- `DEL key [key ...]` — delete one or more keys
- `EXISTS key [key ...]` — count existing keys
- `INCR key` — increment by 1
- `INCRBY key amount` — increment by amount
- `DECR key` — decrement by 1
- `DECRBY key amount` — decrement by amount
- `EXPIRE key seconds`
- `TTL key`
- `MSET key value [key value ...]`
- `MGET key [key ...]`

**Lists:**
- `LPUSH key value [value ...]` — prepend to list
- `RPUSH key value [value ...]` — append to list
- `LLEN key` — get list length
- `LRANGE key start stop`

**Sets:**
- `SADD key member [member ...]` — add members to set
- `SMEMBERS key` — get all members
- `SISMEMBER key member` — check membership
- `SREM key member [member ...]` — remove members
- `SINTER key [key ...]` — set intersection
- `SUNION key [key ...]` — set union
- `SCARD key` — get cardinality (size)

**Hashes:**
- `HSET key field value` — set hash field
- `HGET key field` — get hash field
- `HDEL key field [field ...]` — delete hash fields
- `HEXISTS key field` — check field exists
- `HGETALL key` — get all fields and values
- `HKEYS key` — get all field names
- `HVALS key` — get all values
- `HLEN key` — get number of fields

**Sorted Sets:**
- `ZADD key score member [score member ...]` — add members with scores
- `ZRANGE key start stop [WITHSCORES]` — get range by rank
- `ZRANK key member` — get rank of member
- `ZREM key member [member ...]` — remove members
- `ZSCORE key member` — get score of member
- `ZCARD key` — get cardinality (size)

**Keys:**
- `KEYS pattern` — supports `*`, `?`, and `[...]` glob patterns

**Connection:**
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
# Strings
redis-cli -p 6379 PING
redis-cli -p 6379 SET foo bar EX 10
redis-cli -p 6379 GET foo
redis-cli -p 6379 TTL foo
redis-cli -p 6379 INCR counter
redis-cli -p 6379 INCRBY counter 5
redis-cli -p 6379 DECR counter
redis-cli -p 6379 DEL foo counter
redis-cli -p 6379 EXISTS key1 key2 key3
redis-cli -p 6379 MSET a 1 b 2 c 3
redis-cli -p 6379 MGET a b c missing

# Lists
redis-cli -p 6379 LPUSH mylist first second
redis-cli -p 6379 RPUSH mylist third fourth
redis-cli -p 6379 LLEN mylist
redis-cli -p 6379 LRANGE mylist 0 -1

# Sets
redis-cli -p 6379 SADD myset a b c
redis-cli -p 6379 SMEMBERS myset
redis-cli -p 6379 SISMEMBER myset a
redis-cli -p 6379 SCARD myset
redis-cli -p 6379 SADD set1 a b c
redis-cli -p 6379 SADD set2 b c d
redis-cli -p 6379 SINTER set1 set2
redis-cli -p 6379 SUNION set1 set2

# Hashes
redis-cli -p 6379 HSET user:1 name Alice
redis-cli -p 6379 HSET user:1 age 30
redis-cli -p 6379 HGET user:1 name
redis-cli -p 6379 HGETALL user:1
redis-cli -p 6379 HKEYS user:1
redis-cli -p 6379 HLEN user:1

# Sorted Sets
redis-cli -p 6379 ZADD leaderboard 100 alice 200 bob 150 charlie
redis-cli -p 6379 ZRANGE leaderboard 0 -1
redis-cli -p 6379 ZRANGE leaderboard 0 -1 WITHSCORES
redis-cli -p 6379 ZRANK leaderboard alice
redis-cli -p 6379 ZSCORE leaderboard bob
redis-cli -p 6379 ZCARD leaderboard

# Keys pattern matching
redis-cli -p 6379 SET alpha 1
redis-cli -p 6379 SET beta 2
redis-cli -p 6379 KEYS "a*"
redis-cli -p 6379 KEYS "?eta"
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

Want to add more features? Here are some ideas:

- **Persistence**: Save/load snapshots to disk (RDB-like format)
- **Pub/Sub**: `PUBLISH`, `SUBSCRIBE`, `UNSUBSCRIBE` channels
- **More set operations**: `SDIFF`, `SDIFFSTORE`, `SINTERSTORE`, `SUNIONSTORE`
- **More sorted set ops**: `ZREVRANGE`, `ZRANGEBYSCORE`, `ZINCRBY`, `ZCOUNT`
- **String operations**: `APPEND`, `STRLEN`, `GETRANGE`, `SETRANGE`
- **Bit operations**: `SETBIT`, `GETBIT`, `BITCOUNT`
- **Transactions**: `MULTI`, `EXEC`, `DISCARD`
- **Lua scripting**: `EVAL` for server-side scripts
- **Expiry for all types**: Currently only strings have TTL support
