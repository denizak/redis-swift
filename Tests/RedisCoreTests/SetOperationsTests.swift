import XCTest
import RedisCore

final class SetOperationsTests: XCTestCase {
    func testSAddCreatesSetAndReturnsCount() {
        let store = KeyValueStore()
        
        switch store.sadd("myset", members: ["a", "b", "c"]) {
        case .success(let count):
            XCTAssertEqual(count, 3)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testSAddIgnoresDuplicates() {
        let store = KeyValueStore()
        
        _ = store.sadd("myset", members: ["a", "b"])
        
        switch store.sadd("myset", members: ["b", "c"]) {
        case .success(let count):
            XCTAssertEqual(count, 1) // only 'c' is new
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testSMembersReturnsAllMembers() {
        let store = KeyValueStore()
        
        _ = store.sadd("myset", members: ["b", "a", "c"])
        
        switch store.smembers("myset") {
        case .success(let members):
            XCTAssertEqual(Set(members), Set(["a", "b", "c"]))
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testSIsMemberChecksExistence() {
        let store = KeyValueStore()
        
        _ = store.sadd("myset", members: ["a", "b"])
        
        switch store.sismember("myset", member: "a") {
        case .success(let exists):
            XCTAssertTrue(exists)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
        
        switch store.sismember("myset", member: "missing") {
        case .success(let exists):
            XCTAssertFalse(exists)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testSRemRemovesMembersAndReturnsCount() {
        let store = KeyValueStore()
        
        _ = store.sadd("myset", members: ["a", "b", "c"])
        
        switch store.srem("myset", members: ["b", "missing"]) {
        case .success(let count):
            XCTAssertEqual(count, 1) // only 'b' was removed
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testSInterReturnsIntersection() {
        let store = KeyValueStore()
        
        _ = store.sadd("set1", members: ["a", "b", "c"])
        _ = store.sadd("set2", members: ["b", "c", "d"])
        _ = store.sadd("set3", members: ["c", "d", "e"])
        
        switch store.sinter(["set1", "set2", "set3"]) {
        case .success(let result):
            XCTAssertEqual(Set(result), Set(["c"]))
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testSUnionReturnsUnion() {
        let store = KeyValueStore()
        
        _ = store.sadd("set1", members: ["a", "b"])
        _ = store.sadd("set2", members: ["b", "c"])
        
        switch store.sunion(["set1", "set2"]) {
        case .success(let result):
            XCTAssertEqual(Set(result), Set(["a", "b", "c"]))
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testSCardReturnsCardinality() {
        let store = KeyValueStore()
        
        _ = store.sadd("myset", members: ["a", "b", "c"])
        
        switch store.scard("myset") {
        case .success(let count):
            XCTAssertEqual(count, 3)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
        
        switch store.scard("missing") {
        case .success(let count):
            XCTAssertEqual(count, 0)
        case .failure:
            XCTFail("should return 0 for missing key")
        }
    }
    
    func testSAddFailsOnWrongType() {
        let store = KeyValueStore()
        
        store.set("string", value: "value")
        
        switch store.sadd("string", members: ["a"]) {
        case .success:
            XCTFail("should fail on wrong type")
        case .failure(let error):
            XCTAssertEqual(error, .wrongType)
        }
    }
}
