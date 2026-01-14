import XCTest
import RedisCore

final class HashOperationsTests: XCTestCase {
    func testHSetCreatesHashAndReturnsNewFieldCount() {
        let store = KeyValueStore()
        
        switch store.hset("user:1", field: "name", value: "Alice") {
        case .success(let count):
            XCTAssertEqual(count, 1)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testHSetUpdatesExistingField() {
        let store = KeyValueStore()
        
        _ = store.hset("user:1", field: "name", value: "Alice")
        
        switch store.hset("user:1", field: "name", value: "Bob") {
        case .success(let count):
            XCTAssertEqual(count, 0) // no new field
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testHGetRetrievesFieldValue() {
        let store = KeyValueStore()
        
        _ = store.hset("user:1", field: "name", value: "Alice")
        _ = store.hset("user:1", field: "age", value: "30")
        
        switch store.hget("user:1", field: "name") {
        case .success(let value):
            XCTAssertEqual(value, "Alice")
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
        
        switch store.hget("user:1", field: "missing") {
        case .success(let value):
            XCTAssertNil(value)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testHDelRemovesFieldsAndReturnsCount() {
        let store = KeyValueStore()
        
        _ = store.hset("user:1", field: "name", value: "Alice")
        _ = store.hset("user:1", field: "age", value: "30")
        
        switch store.hdel("user:1", fields: ["age", "missing"]) {
        case .success(let count):
            XCTAssertEqual(count, 1) // only 'age' was removed
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testHExistsChecksFieldExistence() {
        let store = KeyValueStore()
        
        _ = store.hset("user:1", field: "name", value: "Alice")
        
        switch store.hexists("user:1", field: "name") {
        case .success(let exists):
            XCTAssertTrue(exists)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
        
        switch store.hexists("user:1", field: "missing") {
        case .success(let exists):
            XCTAssertFalse(exists)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testHGetAllReturnsAllFieldsAndValues() {
        let store = KeyValueStore()
        
        _ = store.hset("user:1", field: "name", value: "Alice")
        _ = store.hset("user:1", field: "age", value: "30")
        
        switch store.hgetall("user:1") {
        case .success(let pairs):
            XCTAssertEqual(pairs.count, 2)
            XCTAssertTrue(pairs.contains(where: { $0.0 == "name" && $0.1 == "Alice" }))
            XCTAssertTrue(pairs.contains(where: { $0.0 == "age" && $0.1 == "30" }))
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testHKeysReturnsAllFieldNames() {
        let store = KeyValueStore()
        
        _ = store.hset("user:1", field: "name", value: "Alice")
        _ = store.hset("user:1", field: "age", value: "30")
        
        switch store.hkeys("user:1") {
        case .success(let keys):
            XCTAssertEqual(Set(keys), Set(["name", "age"]))
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testHValsReturnsAllValues() {
        let store = KeyValueStore()
        
        _ = store.hset("user:1", field: "name", value: "Alice")
        _ = store.hset("user:1", field: "age", value: "30")
        
        switch store.hvals("user:1") {
        case .success(let values):
            XCTAssertEqual(Set(values), Set(["Alice", "30"]))
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testHLenReturnsFieldCount() {
        let store = KeyValueStore()
        
        _ = store.hset("user:1", field: "name", value: "Alice")
        _ = store.hset("user:1", field: "age", value: "30")
        
        switch store.hlen("user:1") {
        case .success(let count):
            XCTAssertEqual(count, 2)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testHSetFailsOnWrongType() {
        let store = KeyValueStore()
        
        store.set("string", value: "value")
        
        switch store.hset("string", field: "f", value: "v") {
        case .success:
            XCTFail("should fail on wrong type")
        case .failure(let error):
            XCTAssertEqual(error, .wrongType)
        }
    }
}
