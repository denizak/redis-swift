import XCTest
import RedisCore

final class KeyValueStoreAdvancedTests: XCTestCase {
    func testDelMultipleKeysReturnsCount() {
        let store = KeyValueStore()

        store.set("a", value: "1")
        store.set("b", value: "2")
        _ = store.lpush("list", values: ["x"])

        let removed = store.del(["a", "list", "missing"])
        XCTAssertEqual(removed, 2)
        XCTAssertEqual(store.get("a"), nil)
        XCTAssertEqual(store.get("b"), "2")
    }

    func testExistsMultipleKeysCountsOnlyExisting() {
        let store = KeyValueStore()

        store.set("a", value: "1")
        _ = store.lpush("list", values: ["x"])

        let count = store.exists(["a", "list", "missing"])
        XCTAssertEqual(count, 2)
    }

    func testRPushAndLLen() {
        let store = KeyValueStore()

        switch store.rpush("list", values: ["a", "b"]) {
        case .success(let count):
            XCTAssertEqual(count, 2)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }

        switch store.llen("list") {
        case .success(let count):
            XCTAssertEqual(count, 2)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }

    func testIncrDecrByCommands() {
        let store = KeyValueStore()

        store.set("counter", value: "10")

        switch store.incrBy("counter", amount: 5) {
        case .success(let value):
            XCTAssertEqual(value, 15)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }

        switch store.decr("counter") {
        case .success(let value):
            XCTAssertEqual(value, 14)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }

        switch store.decrBy("counter", amount: 4) {
        case .success(let value):
            XCTAssertEqual(value, 10)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSetWithExpirySecondsUpdatesTTL() {
        let store = KeyValueStore()

        store.set("temp", value: "1", expiry: .seconds(10))
        let ttl = store.ttl("temp")
        XCTAssertTrue(ttl <= 10)
        XCTAssertTrue(ttl >= 0)
    }

    func testSetWithExpiryMillisecondsUpdatesTTL() {
        let store = KeyValueStore()

        store.set("temp", value: "1", expiry: .milliseconds(1500))
        let ttl = store.ttl("temp")
        XCTAssertTrue(ttl <= 2)
        XCTAssertTrue(ttl >= 0)
    }

    func testKeysPatternMatchingWithQuestionAndClass() {
        let store = KeyValueStore()

        store.set("abc", value: "1")
        store.set("axc", value: "2")
        store.set("az", value: "3")
        store.set("abb", value: "4")

        XCTAssertEqual(store.keys(pattern: "a?c"), ["abc", "axc"])
        XCTAssertEqual(store.keys(pattern: "ab[bc]"), ["abb", "abc"])
    }
}
