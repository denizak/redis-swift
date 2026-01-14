import Foundation
import Network

public struct RespResponse: Sendable {
    public let data: Data
    public let closeConnection: Bool

    public init(data: Data, closeConnection: Bool) {
        self.data = data
        self.closeConnection = closeConnection
    }
}

public enum StoreError: Error {
    case nonInteger
    case wrongType

    public var message: String {
        switch self {
        case .nonInteger:
            return "value is not an integer or out of range"
        case .wrongType:
            return "wrong type"
        }
    }
}

public final class KeyValueStore: @unchecked Sendable {
    private var storage: [String: String] = [:]
    private var lists: [String: [String]] = [:]
    private var expiries: [String: Date] = [:]
    private let queue = DispatchQueue(label: "redis-swift.store")

    public init() {}

    public func get(_ key: String) -> String? {
        queue.sync {
            if isExpired(key) {
                remove(key)
                return nil
            }
            return storage[key]
        }
    }

    public func set(_ key: String, value: String) {
        queue.sync {
            storage[key] = value
            lists.removeValue(forKey: key)
            expiries.removeValue(forKey: key)
        }
    }

    public func del(_ key: String) -> Int {
        queue.sync {
            let removed = storage.removeValue(forKey: key)
            let removedList = lists.removeValue(forKey: key)
            expiries.removeValue(forKey: key)
            return (removed != nil || removedList != nil) ? 1 : 0
        }
    }

    public func exists(_ key: String) -> Int {
        queue.sync {
            if isExpired(key) {
                remove(key)
                return 0
            }
            return (storage[key] == nil && lists[key] == nil) ? 0 : 1
        }
    }

    public func incr(_ key: String) -> Result<Int, StoreError> {
        queue.sync {
            if isExpired(key) {
                remove(key)
            }
            if lists[key] != nil {
                return .failure(.wrongType)
            }
            let current = storage[key] ?? "0"
            guard let number = Int(current) else {
                return .failure(.nonInteger)
            }
            let next = number + 1
            storage[key] = String(next)
            return .success(next)
        }
    }

    public func expire(_ key: String, seconds: Int) -> Int {
        queue.sync {
            if isExpired(key) {
                remove(key)
                return 0
            }
            guard storage[key] != nil || lists[key] != nil else {
                return 0
            }
            if seconds <= 0 {
                remove(key)
                return 1
            }
            expiries[key] = Date().addingTimeInterval(TimeInterval(seconds))
            return 1
        }
    }

    public func ttl(_ key: String) -> Int {
        queue.sync {
            if isExpired(key) {
                remove(key)
                return -2
            }
            guard storage[key] != nil || lists[key] != nil else {
                return -2
            }
            guard let expiry = expiries[key] else {
                return -1
            }
            let remaining = Int(expiry.timeIntervalSinceNow)
            return max(remaining, -2)
        }
    }

    public func mset(_ pairs: [(String, String)]) {
        queue.sync {
            for (key, value) in pairs {
                storage[key] = value
                lists.removeValue(forKey: key)
                expiries.removeValue(forKey: key)
            }
        }
    }

    public func mget(_ keys: [String]) -> [String?] {
        queue.sync {
            keys.map { key in
                if isExpired(key) {
                    remove(key)
                    return nil
                }
                if lists[key] != nil {
                    return nil
                }
                return storage[key]
            }
        }
    }

    public func lpush(_ key: String, values: [String]) -> Result<Int, StoreError> {
        queue.sync {
            if isExpired(key) {
                remove(key)
            }
            if storage[key] != nil {
                return .failure(.wrongType)
            }
            var list = lists[key] ?? []
            for value in values {
                list.insert(value, at: 0)
            }
            lists[key] = list
            return .success(list.count)
        }
    }

    public func lrange(_ key: String, start: Int, stop: Int) -> Result<[String], StoreError> {
        queue.sync {
            if isExpired(key) {
                remove(key)
                return .success([])
            }
            if storage[key] != nil {
                return .failure(.wrongType)
            }
            guard let list = lists[key] else {
                return .success([])
            }

            let count = list.count
            if count == 0 {
                return .success([])
            }

            var startIndex = start
            var stopIndex = stop

            if startIndex < 0 { startIndex = count + startIndex }
            if stopIndex < 0 { stopIndex = count + stopIndex }

            startIndex = max(startIndex, 0)
            stopIndex = min(stopIndex, count - 1)

            if startIndex > stopIndex || startIndex >= count {
                return .success([])
            }

            let slice = list[startIndex...stopIndex]
            return .success(Array(slice))
        }
    }

    public func isList(_ key: String) -> Bool {
        queue.sync { lists[key] != nil }
    }

    public func keys(pattern: String) -> [String] {
        queue.sync {
            var results: [String] = []
            let allKeys = Set(storage.keys).union(lists.keys)

            for key in allKeys {
                if isExpired(key) {
                    remove(key)
                    continue
                }
                if matchesPattern(pattern, key: key) {
                    results.append(key)
                }
            }

            return results.sorted()
        }
    }

    private func isExpired(_ key: String) -> Bool {
        guard let expiry = expiries[key] else {
            return false
        }
        return expiry.timeIntervalSinceNow <= 0
    }

    private func remove(_ key: String) {
        storage.removeValue(forKey: key)
        lists.removeValue(forKey: key)
        expiries.removeValue(forKey: key)
    }

    private func matchesPattern(_ pattern: String, key: String) -> Bool {
        if pattern == "*" {
            return true
        }

        if !pattern.contains("*") {
            return pattern == key
        }

        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
        let regexPattern = "^" + escaped + "$"

        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return false
        }
        let range = NSRange(key.startIndex..<key.endIndex, in: key)
        return regex.firstMatch(in: key, range: range) != nil
    }
}

public enum ParseResult {
    case command([String])
    case incomplete
    case error(String)
}

public struct RespParser {
    private static let crlf = Data([13, 10])
    private static let lf = Data([10])

    public static func parseCommand(from buffer: inout Data) -> ParseResult {
        guard !buffer.isEmpty else { return .incomplete }

        if buffer.first == 42 { // '*'
            return parseArray(from: &buffer)
        }

        return parseInline(from: &buffer)
    }

    private static func parseInline(from buffer: inout Data) -> ParseResult {
        guard let (line, nextIndex) = readLine(in: buffer, from: 0) else {
            return .incomplete
        }

        buffer.removeSubrange(0..<nextIndex)
        let parts = line.split(separator: " ").map { String($0) }
        if parts.isEmpty {
            return .error("empty command")
        }
        return .command(parts)
    }

    private static func parseArray(from buffer: inout Data) -> ParseResult {
        guard let (line, indexAfterLine) = readLine(in: buffer, from: 0) else {
            return .incomplete
        }

        guard line.first == "*" else {
            buffer.removeAll(keepingCapacity: true)
            return .error("invalid array header")
        }

        let countString = String(line.dropFirst())
        guard let count = Int(countString), count >= 0 else {
            buffer.removeAll(keepingCapacity: true)
            return .error("invalid array length")
        }

        var cursor = indexAfterLine
        var items: [String] = []
        items.reserveCapacity(count)

        for _ in 0..<count {
            guard let (bulkHeader, afterBulkHeader) = readLine(in: buffer, from: cursor) else {
                return .incomplete
            }
            guard bulkHeader.first == "$" else {
                buffer.removeAll(keepingCapacity: true)
                return .error("expected bulk string")
            }

            let lengthString = String(bulkHeader.dropFirst())
            guard let length = Int(lengthString), length >= 0 else {
                buffer.removeAll(keepingCapacity: true)
                return .error("invalid bulk length")
            }

            let bytesNeeded = afterBulkHeader + length + 2
            guard buffer.count >= bytesNeeded else {
                return .incomplete
            }

            let valueData = buffer[afterBulkHeader..<(afterBulkHeader + length)]
            guard let value = String(data: valueData, encoding: .utf8) else {
                buffer.removeAll(keepingCapacity: true)
                return .error("invalid utf8 bulk string")
            }

            let crlfStart = afterBulkHeader + length
            let crlfEnd = crlfStart + 2
            guard buffer[crlfStart..<crlfEnd] == crlf else {
                buffer.removeAll(keepingCapacity: true)
                return .error("invalid bulk string terminator")
            }

            items.append(value)
            cursor = crlfEnd
        }

        buffer.removeSubrange(0..<cursor)
        return .command(items)
    }

    private static func readLine(in data: Data, from index: Int) -> (String, Int)? {
        guard index < data.count else { return nil }

        if let range = data.range(of: crlf, options: [], in: index..<data.count) {
            let lineData = data[index..<range.lowerBound]
            guard let line = String(data: lineData, encoding: .utf8) else {
                return nil
            }
            return (line, range.upperBound)
        }

        if let range = data.range(of: lf, options: [], in: index..<data.count) {
            let lineData = data[index..<range.lowerBound]
            guard let line = String(data: lineData, encoding: .utf8) else {
                return nil
            }
            return (line, range.upperBound)
        }

        return nil
    }
}

public struct RespEncoder {
    public static func simple(_ message: String) -> Data {
        "+\(message)\r\n".data(using: .utf8) ?? Data()
    }

    public static func error(_ message: String) -> Data {
        "-ERR \(message)\r\n".data(using: .utf8) ?? Data()
    }

    public static func integer(_ value: Int) -> Data {
        ":\(value)\r\n".data(using: .utf8) ?? Data()
    }

    public static func bulk(_ value: String?) -> Data {
        guard let value else {
            return "$-1\r\n".data(using: .utf8) ?? Data()
        }
        let bytes = Array(value.utf8)
        var data = Data("$\(bytes.count)\r\n".utf8)
        data.append(contentsOf: bytes)
        data.append(contentsOf: [13, 10])
        return data
    }

    public static func array(_ values: [String?]) -> Data {
        var data = Data("*\(values.count)\r\n".utf8)
        for value in values {
            data.append(bulk(value))
        }
        return data
    }
}

@available(macOS 10.14, *)
public final class Client: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "redis-swift.client")
    private var buffer = Data()
    private let store: KeyValueStore

    public init(connection: NWConnection, store: KeyValueStore) {
        self.connection = connection
        self.store = store
    }

    public func start() {
        connection.stateUpdateHandler = { newState in
            if case .failed(let error) = newState {
                print("Connection failed: \(error)")
                self.connection.cancel()
            }
        }
        connection.start(queue: queue)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data {
                self.queue.async {
                    self.buffer.append(data)
                    self.processBuffer()
                }
            }

            if isComplete || error != nil {
                self.connection.cancel()
                return
            }

            self.receive()
        }
    }

    private func processBuffer() {
        while true {
            switch RespParser.parseCommand(from: &buffer) {
            case .command(let command):
                let response = handle(command: command)
                send(response)
            case .error(let message):
                send(RespResponse(data: RespEncoder.error(message), closeConnection: false))
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
                return RespResponse(data: RespEncoder.error("wrong number of arguments for 'echo' command"), closeConnection: false)
            }
            return RespResponse(data: RespEncoder.bulk(message), closeConnection: false)
        case "SET":
            guard args.count >= 2 else {
                return RespResponse(data: RespEncoder.error("wrong number of arguments for 'set' command"), closeConnection: false)
            }
            store.set(args[0], value: args[1])
            return RespResponse(data: RespEncoder.simple("OK"), closeConnection: false)
        case "GET":
            guard let key = args.first else {
                return RespResponse(data: RespEncoder.error("wrong number of arguments for 'get' command"), closeConnection: false)
            }
            if store.isList(key) {
                return RespResponse(data: RespEncoder.error(StoreError.wrongType.message), closeConnection: false)
            }
            return RespResponse(data: RespEncoder.bulk(store.get(key)), closeConnection: false)
        case "DEL":
            guard let key = args.first else {
                return RespResponse(data: RespEncoder.error("wrong number of arguments for 'del' command"), closeConnection: false)
            }
            return RespResponse(data: RespEncoder.integer(store.del(key)), closeConnection: false)
        case "EXISTS":
            guard let key = args.first else {
                return RespResponse(data: RespEncoder.error("wrong number of arguments for 'exists' command"), closeConnection: false)
            }
            return RespResponse(data: RespEncoder.integer(store.exists(key)), closeConnection: false)
        case "INCR":
            guard let key = args.first else {
                return RespResponse(data: RespEncoder.error("wrong number of arguments for 'incr' command"), closeConnection: false)
            }
            switch store.incr(key) {
            case .success(let value):
                return RespResponse(data: RespEncoder.integer(value), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "EXPIRE":
            guard args.count >= 2 else {
                return RespResponse(data: RespEncoder.error("wrong number of arguments for 'expire' command"), closeConnection: false)
            }
            guard let seconds = Int(args[1]) else {
                return RespResponse(data: RespEncoder.error("value is not an integer or out of range"), closeConnection: false)
            }
            return RespResponse(data: RespEncoder.integer(store.expire(args[0], seconds: seconds)), closeConnection: false)
        case "TTL":
            guard let key = args.first else {
                return RespResponse(data: RespEncoder.error("wrong number of arguments for 'ttl' command"), closeConnection: false)
            }
            return RespResponse(data: RespEncoder.integer(store.ttl(key)), closeConnection: false)
        case "MSET":
            guard args.count >= 2, args.count % 2 == 0 else {
                return RespResponse(data: RespEncoder.error("wrong number of arguments for 'mset' command"), closeConnection: false)
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
                return RespResponse(data: RespEncoder.error("wrong number of arguments for 'mget' command"), closeConnection: false)
            }
            return RespResponse(data: RespEncoder.array(store.mget(args)), closeConnection: false)
        case "LPUSH":
            guard args.count >= 2 else {
                return RespResponse(data: RespEncoder.error("wrong number of arguments for 'lpush' command"), closeConnection: false)
            }
            let key = args[0]
            let values = Array(args.dropFirst())
            switch store.lpush(key, values: values) {
            case .success(let count):
                return RespResponse(data: RespEncoder.integer(count), closeConnection: false)
            case .failure(let error):
                return RespResponse(data: RespEncoder.error(error.message), closeConnection: false)
            }
        case "LRANGE":
            guard args.count >= 3 else {
                return RespResponse(data: RespEncoder.error("wrong number of arguments for 'lrange' command"), closeConnection: false)
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
                return RespResponse(data: RespEncoder.error("wrong number of arguments for 'keys' command"), closeConnection: false)
            }
            let keys = store.keys(pattern: pattern)
            return RespResponse(data: RespEncoder.array(keys.map { Optional($0) }), closeConnection: false)
        case "QUIT":
            return RespResponse(data: RespEncoder.simple("OK"), closeConnection: true)
        default:
            return RespResponse(data: RespEncoder.error("unknown command '\(head)'"), closeConnection: false)
        }
    }

    private func send(_ response: RespResponse) {
        connection.send(content: response.data, completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            if response.closeConnection {
                self.connection.cancel()
            }
        })
    }
}

@available(macOS 10.14, *)
public enum Server {
    public static func run() {
        let store = KeyValueStore()
        do {
            let port = NWEndpoint.Port(rawValue: 6379) ?? 6379
            let listener = try NWListener(using: .tcp, on: port)

            listener.newConnectionHandler = { connection in
                let client = Client(connection: connection, store: store)
                client.start()
            }

            listener.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    print("mini-redis server listening on port \(port)")
                case .failed(let error):
                    print("listener failed: \(error)")
                    exit(1)
                default:
                    break
                }
            }

            listener.start(queue: DispatchQueue(label: "redis-swift.listener"))
            dispatchMain()
        } catch {
            print("failed to start listener: \(error)")
            exit(1)
        }
    }
}
