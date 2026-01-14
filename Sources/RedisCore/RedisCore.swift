import Foundation

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

public enum SetExpiry: Sendable {
    case seconds(Int)
    case milliseconds(Int)
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

    public func set(_ key: String, value: String, expiry: SetExpiry?) {
        queue.sync {
            storage[key] = value
            lists.removeValue(forKey: key)
            expiries.removeValue(forKey: key)

            if let expiry {
                let deadline: Date
                switch expiry {
                case .seconds(let seconds):
                    deadline = Date().addingTimeInterval(TimeInterval(seconds))
                case .milliseconds(let milliseconds):
                    deadline = Date().addingTimeInterval(TimeInterval(milliseconds) / 1000)
                }
                expiries[key] = deadline
            }
        }
    }

    public func del(_ key: String) -> Int {
        del([key])
    }

    public func del(_ keys: [String]) -> Int {
        queue.sync {
            var removedCount = 0
            for key in keys {
                let removed = storage.removeValue(forKey: key)
                let removedList = lists.removeValue(forKey: key)
                expiries.removeValue(forKey: key)
                if removed != nil || removedList != nil {
                    removedCount += 1
                }
            }
            return removedCount
        }
    }

    public func exists(_ key: String) -> Int {
        exists([key])
    }

    public func exists(_ keys: [String]) -> Int {
        queue.sync {
            var count = 0
            for key in keys {
                if isExpired(key) {
                    remove(key)
                    continue
                }
                if storage[key] != nil || lists[key] != nil {
                    count += 1
                }
            }
            return count
        }
    }

    public func incr(_ key: String) -> Result<Int, StoreError> {
        increment(key, by: 1)
    }

    public func incrBy(_ key: String, amount: Int) -> Result<Int, StoreError> {
        increment(key, by: amount)
    }

    public func decr(_ key: String) -> Result<Int, StoreError> {
        increment(key, by: -1)
    }

    public func decrBy(_ key: String, amount: Int) -> Result<Int, StoreError> {
        increment(key, by: -amount)
    }

    private func increment(_ key: String, by amount: Int) -> Result<Int, StoreError> {
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
            let next = number + amount
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

    public func rpush(_ key: String, values: [String]) -> Result<Int, StoreError> {
        queue.sync {
            if isExpired(key) {
                remove(key)
            }
            if storage[key] != nil {
                return .failure(.wrongType)
            }
            var list = lists[key] ?? []
            list.append(contentsOf: values)
            lists[key] = list
            return .success(list.count)
        }
    }

    public func llen(_ key: String) -> Result<Int, StoreError> {
        queue.sync {
            if isExpired(key) {
                remove(key)
                return .success(0)
            }
            if storage[key] != nil {
                return .failure(.wrongType)
            }
            return .success(lists[key]?.count ?? 0)
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

        if !pattern.contains("*") && !pattern.contains("?") && !pattern.contains("[") {
            return pattern == key
        }

        let regexPattern = "^" + globToRegex(pattern) + "$"

        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return false
        }
        let range = NSRange(key.startIndex..<key.endIndex, in: key)
        return regex.firstMatch(in: key, range: range) != nil
    }

    private func globToRegex(_ pattern: String) -> String {
        var result = ""
        var chars = Array(pattern)
        var index = 0
        var escaping = false

        while index < chars.count {
            let char = chars[index]

            if escaping {
                result.append(NSRegularExpression.escapedPattern(for: String(char)))
                escaping = false
                index += 1
                continue
            }

            if char == "\\" {
                escaping = true
                index += 1
                continue
            }

            switch char {
            case "*":
                result.append(".*")
            case "?":
                result.append(".")
            case "[":
                if let (classPattern, advance) = parseCharacterClass(chars, start: index) {
                    result.append(classPattern)
                    index += advance
                    continue
                } else {
                    result.append("\\[")
                }
            default:
                result.append(NSRegularExpression.escapedPattern(for: String(char)))
            }

            index += 1
        }

        if escaping {
            result.append("\\\\")
        }

        return result
    }

    private func parseCharacterClass(_ chars: [Character], start: Int) -> (String, Int)? {
        guard start < chars.count, chars[start] == "[" else {
            return nil
        }

        var index = start + 1
        if index >= chars.count {
            return nil
        }

        var negate = false
        if chars[index] == "!" {
            negate = true
            index += 1
        }

        var classContent = ""
        while index < chars.count {
            let char = chars[index]
            if char == "]" {
                let prefix = negate ? "[^" : "["
                return (prefix + classContent + "]", index - start + 1)
            }

            if "\\^-".contains(char) {
                classContent.append("\\" + String(char))
            } else {
                classContent.append(char)
            }
            index += 1
        }

        return nil
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

