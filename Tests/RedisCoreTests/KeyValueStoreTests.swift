import XCTest
import RedisCore

final class KeyValueStoreTests: XCTestCase {
    func testMSetAndMGetRoundTrip() {
        let store = KeyValueStore()

        store.mset([("a", "1"), ("b", "2"), ("c", "3")])
        let values = store.mget(["a", "b", "c"])

        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values[0], "1")
        XCTAssertEqual(values[1], "2")
        XCTAssertEqual(values[2], "3")
    }

    func testMGetIncludesNilForMissingKeys() {
        let store = KeyValueStore()

        store.set("a", value: "1")
        let values = store.mget(["a", "missing", "b"])

        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values[0], "1")
        XCTAssertNil(values[1])
        XCTAssertNil(values[2])
    }

    func testLPushAndLRangeRoundTrip() {
        let store = KeyValueStore()

        let countResult = store.lpush("list", values: ["one", "two", "three"])
        switch countResult {
        case .success(let count):
            XCTAssertEqual(count, 3)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }

        let rangeResult = store.lrange("list", start: 0, stop: 1)
        switch rangeResult {
        case .success(let range):
            XCTAssertEqual(range, ["three", "two"])
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }

    func testLRangeNegativeIndices() {
        let store = KeyValueStore()

        _ = store.lpush("list", values: ["a", "b", "c", "d"])
        let rangeResult = store.lrange("list", start: -2, stop: -1)

        switch rangeResult {
        case .success(let range):
            XCTAssertEqual(range, ["b", "a"])
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
}
