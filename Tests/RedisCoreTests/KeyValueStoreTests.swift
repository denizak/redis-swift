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
}
