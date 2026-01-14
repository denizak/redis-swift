import Foundation
import NIO
import RedisCore

final class RedisHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private var buffer = Data()
    private let store: KeyValueStore

    init(store: KeyValueStore) {
        self.store = store
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var byteBuffer = unwrapInboundIn(data)
        if let bytes = byteBuffer.readBytes(length: byteBuffer.readableBytes) {
            buffer.append(contentsOf: bytes)
        }

        while true {
            switch RespParser.parseCommand(from: &buffer) {
            case .command(let command):
                let response = handle(command: command)
                send(response, context: context)
            case .error(let message):
                send(RespResponse(data: RespEncoder.error(message), closeConnection: false), context: context)
                return
            case .incomplete:
                return
            }
        }
    }

    private func handle(command: [String]) -> RespResponse {
        guard let head = command.first else {
            return RespResponse(data: RespEncoder.error("empty command"), closeConnection: false)
        }

        let name = head.uppercased()
        let args = Array(command.dropFirst())

        switch name {
        case "PING":
            if let message = args.first {
                return RespResponse(data: RespEncoder.bulk(message), closeConnection: false)
            }
            return RespResponse(data: RespEncoder.simple("PONG"), closeConnection: false)
        case "ECHO":
            guard let message = args.first else {
                return wrongArgs("echo")
            }
            return RespResponse(data: RespEncoder.bulk(message), closeConnection: false)
        case "SET":
            guard args.count >= 2 else {
                return wrongArgs("set")
            }

            let key = args[0]
            let value = args[1]
            let options = Array(args.dropFirst(2))

            switch parseSetOptions(options) {
            case .success(let expiry):
                store.set(key, value: value, expiry: expiry)
            case .failure(.syntaxError):
                return RespResponse(data: RespEncoder.error("syntax error"), closeConnection: false)
            case .failure(.invalidExpireTime):
                return RespResponse(data: RespEncoder.error("invalid expire time in set"), closeConnection: false)
            }

            return RespResponse(data: RespEncoder.simple("OK"), closeConnection: false)
        case "GET":
            guard let key = args.first else {
                return wrongArgs("get")
            }
            if store.isList(key) {
                return RespResponse(data: RespEncoder.error(StoreError.wrongType.message), closeConnection: false)
            }
            return RespResponse(data: RespEncoder.bulk(store.get(key)), closeConnection: false)
        case "DEL":
            guard !args.isEmpty else {
                return wrongArgs("del")
            }
            return RespResponse(data: RespEncoder.integer(store.del(args)), closeConnection: false)
        case "EXISTS":
            guard !args.isEmpty else {
                return wrongArgs("exists")
            }
            return RespResponse(data: RespEncoder.integer(store.exists(args)), closeConnection: false)
        case "INCR":
            guard let key = args.first else {
                return wrongArgs("incr")
            }
            switch store.incr(key) {
            case .success(let value):
                return RespResponse(data: RespEncoder.integer(value), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "INCRBY":
            guard args.count >= 2 else {
                return wrongArgs("incrby")
            }
            guard let amount = Int(args[1]) else {
                return RespResponse(data: RespEncoder.error("value is not an integer or out of range"), closeConnection: false)
            }
            switch store.incrBy(args[0], amount: amount) {
            case .success(let value):
                return RespResponse(data: RespEncoder.integer(value), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "DECR":
            guard let key = args.first else {
                return wrongArgs("decr")
            }
            switch store.decr(key) {
            case .success(let value):
                return RespResponse(data: RespEncoder.integer(value), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "DECRBY":
            guard args.count >= 2 else {
                return wrongArgs("decrby")
            }
            guard let amount = Int(args[1]) else {
                return RespResponse(data: RespEncoder.error("value is not an integer or out of range"), closeConnection: false)
            }
            switch store.decrBy(args[0], amount: amount) {
            case .success(let value):
                return RespResponse(data: RespEncoder.integer(value), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "EXPIRE":
            guard args.count >= 2 else {
                return wrongArgs("expire")
            }
            guard let seconds = Int(args[1]) else {
                return RespResponse(data: RespEncoder.error("value is not an integer or out of range"), closeConnection: false)
            }
            return RespResponse(data: RespEncoder.integer(store.expire(args[0], seconds: seconds)), closeConnection: false)
        case "TTL":
            guard let key = args.first else {
                return wrongArgs("ttl")
            }
            return RespResponse(data: RespEncoder.integer(store.ttl(key)), closeConnection: false)
        case "MSET":
            guard args.count >= 2, args.count % 2 == 0 else {
                return wrongArgs("mset")
            }
            var pairs: [(String, String)] = []
            pairs.reserveCapacity(args.count / 2)
            var index = 0
            while index < args.count {
                pairs.append((args[index], args[index + 1]))
                index += 2
            }
            store.mset(pairs)
            return RespResponse(data: RespEncoder.simple("OK"), closeConnection: false)
        case "MGET":
            guard !args.isEmpty else {
                return wrongArgs("mget")
            }
            return RespResponse(data: RespEncoder.array(store.mget(args)), closeConnection: false)
        case "LPUSH":
            guard args.count >= 2 else {
                return wrongArgs("lpush")
            }
            let key = args[0]
            let values = Array(args.dropFirst())
            switch store.lpush(key, values: values) {
            case .success(let count):
                return RespResponse(data: RespEncoder.integer(count), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "RPUSH":
            guard args.count >= 2 else {
                return wrongArgs("rpush")
            }
            let key = args[0]
            let values = Array(args.dropFirst())
            switch store.rpush(key, values: values) {
            case .success(let count):
                return RespResponse(data: RespEncoder.integer(count), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "LLEN":
            guard let key = args.first else {
                return wrongArgs("llen")
            }
            switch store.llen(key) {
            case .success(let count):
                return RespResponse(data: RespEncoder.integer(count), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "LRANGE":
            guard args.count >= 3 else {
                return wrongArgs("lrange")
            }
            guard let start = Int(args[1]), let stop = Int(args[2]) else {
                return RespResponse(data: RespEncoder.error("value is not an integer or out of range"), closeConnection: false)
            }
            switch store.lrange(args[0], start: start, stop: stop) {
            case .success(let values):
                return RespResponse(data: RespEncoder.array(values.map { Optional($0) }), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "KEYS":
            guard let pattern = args.first else {
                return wrongArgs("keys")
            }
            let keys = store.keys(pattern: pattern)
            return RespResponse(data: RespEncoder.array(keys.map { Optional($0) }), closeConnection: false)
        case "SADD":
            guard args.count >= 2 else {
                return wrongArgs("sadd")
            }
            let key = args[0]
            let members = Array(args.dropFirst())
            switch store.sadd(key, members: members) {
            case .success(let count):
                return RespResponse(data: RespEncoder.integer(count), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "SMEMBERS":
            guard let key = args.first else {
                return wrongArgs("smembers")
            }
            switch store.smembers(key) {
            case .success(let members):
                return RespResponse(data: RespEncoder.array(members.map { Optional($0) }), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "SISMEMBER":
            guard args.count >= 2 else {
                return wrongArgs("sismember")
            }
            switch store.sismember(args[0], member: args[1]) {
            case .success(let exists):
                return RespResponse(data: RespEncoder.integer(exists ? 1 : 0), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "SREM":
            guard args.count >= 2 else {
                return wrongArgs("srem")
            }
            let key = args[0]
            let members = Array(args.dropFirst())
            switch store.srem(key, members: members) {
            case .success(let count):
                return RespResponse(data: RespEncoder.integer(count), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "SINTER":
            guard !args.isEmpty else {
                return wrongArgs("sinter")
            }
            switch store.sinter(args) {
            case .success(let members):
                return RespResponse(data: RespEncoder.array(members.map { Optional($0) }), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "SUNION":
            guard !args.isEmpty else {
                return wrongArgs("sunion")
            }
            switch store.sunion(args) {
            case .success(let members):
                return RespResponse(data: RespEncoder.array(members.map { Optional($0) }), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "SCARD":
            guard let key = args.first else {
                return wrongArgs("scard")
            }
            switch store.scard(key) {
            case .success(let count):
                return RespResponse(data: RespEncoder.integer(count), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "HSET":
            guard args.count >= 3 else {
                return wrongArgs("hset")
            }
            switch store.hset(args[0], field: args[1], value: args[2]) {
            case .success(let count):
                return RespResponse(data: RespEncoder.integer(count), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "HGET":
            guard args.count >= 2 else {
                return wrongArgs("hget")
            }
            switch store.hget(args[0], field: args[1]) {
            case .success(let value):
                return RespResponse(data: RespEncoder.bulk(value), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "HDEL":
            guard args.count >= 2 else {
                return wrongArgs("hdel")
            }
            let key = args[0]
            let fields = Array(args.dropFirst())
            switch store.hdel(key, fields: fields) {
            case .success(let count):
                return RespResponse(data: RespEncoder.integer(count), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "HEXISTS":
            guard args.count >= 2 else {
                return wrongArgs("hexists")
            }
            switch store.hexists(args[0], field: args[1]) {
            case .success(let exists):
                return RespResponse(data: RespEncoder.integer(exists ? 1 : 0), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "HGETALL":
            guard let key = args.first else {
                return wrongArgs("hgetall")
            }
            switch store.hgetall(key) {
            case .success(let pairs):
                let flattened = pairs.flatMap { [$0.0, $0.1] }
                return RespResponse(data: RespEncoder.array(flattened.map { Optional($0) }), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "HKEYS":
            guard let key = args.first else {
                return wrongArgs("hkeys")
            }
            switch store.hkeys(key) {
            case .success(let keys):
                return RespResponse(data: RespEncoder.array(keys.map { Optional($0) }), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "HVALS":
            guard let key = args.first else {
                return wrongArgs("hvals")
            }
            switch store.hvals(key) {
            case .success(let values):
                return RespResponse(data: RespEncoder.array(values.map { Optional($0) }), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "HLEN":
            guard let key = args.first else {
                return wrongArgs("hlen")
            }
            switch store.hlen(key) {
            case .success(let count):
                return RespResponse(data: RespEncoder.integer(count), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "ZADD":
            guard args.count >= 3, args.count % 2 == 1 else {
                return wrongArgs("zadd")
            }
            let key = args[0]
            var members: [(Double, String)] = []
            var index = 1
            while index < args.count {
                guard let score = Double(args[index]) else {
                    return RespResponse(data: RespEncoder.error("value is not a valid float"), closeConnection: false)
                }
                members.append((score, args[index + 1]))
                index += 2
            }
            switch store.zadd(key, members: members) {
            case .success(let count):
                return RespResponse(data: RespEncoder.integer(count), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "ZRANGE":
            guard args.count >= 3 else {
                return wrongArgs("zrange")
            }
            guard let start = Int(args[1]), let stop = Int(args[2]) else {
                return RespResponse(data: RespEncoder.error("value is not an integer or out of range"), closeConnection: false)
            }
            let withScores = args.count >= 4 && args[3].uppercased() == "WITHSCORES"
            switch store.zrange(args[0], start: start, stop: stop, withScores: withScores) {
            case .success(let members):
                return RespResponse(data: RespEncoder.array(members.map { Optional($0) }), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "ZRANK":
            guard args.count >= 2 else {
                return wrongArgs("zrank")
            }
            switch store.zrank(args[0], member: args[1]) {
            case .success(let rank):
                if let rank {
                    return RespResponse(data: RespEncoder.integer(rank), closeConnection: false)
                } else {
                    return RespResponse(data: RespEncoder.bulk(nil), closeConnection: false)
                }
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "ZREM":
            guard args.count >= 2 else {
                return wrongArgs("zrem")
            }
            let key = args[0]
            let members = Array(args.dropFirst())
            switch store.zrem(key, members: members) {
            case .success(let count):
                return RespResponse(data: RespEncoder.integer(count), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "ZSCORE":
            guard args.count >= 2 else {
                return wrongArgs("zscore")
            }
            switch store.zscore(args[0], member: args[1]) {
            case .success(let score):
                if let score {
                    return RespResponse(data: RespEncoder.bulk(String(score)), closeConnection: false)
                } else {
                    return RespResponse(data: RespEncoder.bulk(nil), closeConnection: false)
                }
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "ZCARD":
            guard let key = args.first else {
                return wrongArgs("zcard")
            }
            switch store.zcard(key) {
            case .success(let count):
                return RespResponse(data: RespEncoder.integer(count), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "QUIT":
            return RespResponse(data: RespEncoder.simple("OK"), closeConnection: true)
        default:
            return RespResponse(data: RespEncoder.error("unknown command '\(head)'"), closeConnection: false)
        }
    }

    private func wrongArgs(_ name: String) -> RespResponse {
        RespResponse(data: RespEncoder.error("wrong number of arguments for '\(name)' command"), closeConnection: false)
    }

    private enum SetOptionError: Error {
        case syntaxError
        case invalidExpireTime
    }

    private func parseSetOptions(_ options: [String]) -> Result<SetExpiry?, SetOptionError> {
        guard !options.isEmpty else {
            return .success(nil)
        }

        var expiry: SetExpiry?
        var index = 0
        while index < options.count {
            let option = options[index].uppercased()
            switch option {
            case "EX", "PX":
                guard index + 1 < options.count else {
                    return .failure(.syntaxError)
                }
                guard let value = Int(options[index + 1]), value > 0 else {
                    return .failure(.invalidExpireTime)
                }
                expiry = option == "EX" ? .seconds(value) : .milliseconds(value)
                index += 2
            default:
                return .failure(.syntaxError)
            }
        }

        return .success(expiry)
    }

    private func send(_ response: RespResponse, context: ChannelHandlerContext) {
        var out = context.channel.allocator.buffer(capacity: response.data.count)
        out.writeBytes(response.data)
        let writeFuture = context.writeAndFlush(self.wrapOutboundOut(out))
        if response.closeConnection {
            writeFuture.whenComplete { _ in
                context.close(promise: nil)
            }
        }
    }
}

public enum Server {
    public static func run(host: String = "0.0.0.0", port: Int = 6379) {
        let store = KeyValueStore()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

        do {
            let bootstrap = ServerBootstrap(group: group)
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { channel in
                    channel.pipeline.addHandler(RedisHandler(store: store))
                }
                .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)

            let channel = try bootstrap.bind(host: host, port: port).wait()
            let signalSources = installShutdownSignals(channel: channel)
            print("mini-redis server listening on \(host):\(port)")
            try channel.closeFuture.wait()
            signalSources.forEach { $0.cancel() }
        } catch {
            print("failed to start server: \(error)")
        }

        do {
            try group.syncShutdownGracefully()
        } catch {
            print("failed to shutdown event loop: \(error)")
        }
    }

    private static func installShutdownSignals(channel: Channel) -> [DispatchSourceSignal] {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let queue = DispatchQueue(label: "redis-swift.signal")
        let makeSource: (Int32) -> DispatchSourceSignal = { signal in
            let source = DispatchSource.makeSignalSource(signal: signal, queue: queue)
            source.setEventHandler {
                channel.close(promise: nil)
            }
            source.resume()
            return source
        }

        return [makeSource(SIGINT), makeSource(SIGTERM)]
    }
}
