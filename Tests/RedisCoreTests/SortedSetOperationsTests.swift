import XCTest
import RedisCore

final class SortedSetOperationsTests: XCTestCase {
    func testZAddCreatesSortedSetAndReturnsCount() {
        let store = KeyValueStore()
        
        switch store.zadd("leaderboard", members: [(1.0, "alice"), (2.0, "bob")]) {
        case .success(let count):
            XCTAssertEqual(count, 2)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testZAddUpdatesExistingMemberScore() {
        let store = KeyValueStore()
        
        _ = store.zadd("leaderboard", members: [(1.0, "alice")])
        
        switch store.zadd("leaderboard", members: [(5.0, "alice")]) {
        case .success(let count):
            XCTAssertEqual(count, 0) // no new member
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
        
        // Verify score was updated
        switch store.zscore("leaderboard", member: "alice") {
        case .success(let score):
            XCTAssertEqual(score, 5.0)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testZRangeReturnsOrderedByScore() {
        let store = KeyValueStore()
        
        _ = store.zadd("leaderboard", members: [(3.0, "charlie"), (1.0, "alice"), (2.0, "bob")])
        
        switch store.zrange("leaderboard", start: 0, stop: -1, withScores: false) {
        case .success(let members):
            XCTAssertEqual(members, ["alice", "bob", "charlie"])
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testZRangeWithScoresReturnsInterleavedScoresAndMembers() {
        let store = KeyValueStore()
        
        _ = store.zadd("leaderboard", members: [(2.0, "bob"), (1.0, "alice")])
        
        switch store.zrange("leaderboard", start: 0, stop: -1, withScores: true) {
        case .success(let result):
            XCTAssertEqual(result, ["alice", "1.0", "bob", "2.0"])
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testZRangeWithNegativeIndices() {
        let store = KeyValueStore()
        
        _ = store.zadd("leaderboard", members: [(1.0, "a"), (2.0, "b"), (3.0, "c"), (4.0, "d")])
        
        switch store.zrange("leaderboard", start: -3, stop: -1, withScores: false) {
        case .success(let members):
            XCTAssertEqual(members, ["b", "c", "d"])
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testZRankReturnsRankByScore() {
        let store = KeyValueStore()
        
        _ = store.zadd("leaderboard", members: [(3.0, "charlie"), (1.0, "alice"), (2.0, "bob")])
        
        switch store.zrank("leaderboard", member: "alice") {
        case .success(let rank):
            XCTAssertEqual(rank, 0)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
        
        switch store.zrank("leaderboard", member: "charlie") {
        case .success(let rank):
            XCTAssertEqual(rank, 2)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
        
        switch store.zrank("leaderboard", member: "missing") {
        case .success(let rank):
            XCTAssertNil(rank)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testZRemRemovesMembersAndReturnsCount() {
        let store = KeyValueStore()
        
        _ = store.zadd("leaderboard", members: [(1.0, "alice"), (2.0, "bob"), (3.0, "charlie")])
        
        switch store.zrem("leaderboard", members: ["bob", "missing"]) {
        case .success(let count):
            XCTAssertEqual(count, 1) // only 'bob' was removed
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testZScoreReturnsScore() {
        let store = KeyValueStore()
        
        _ = store.zadd("leaderboard", members: [(42.5, "alice")])
        
        switch store.zscore("leaderboard", member: "alice") {
        case .success(let score):
            XCTAssertEqual(score, 42.5)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
        
        switch store.zscore("leaderboard", member: "missing") {
        case .success(let score):
            XCTAssertNil(score)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
    }
    
    func testZCardReturnsCardinality() {
        let store = KeyValueStore()
        
        _ = store.zadd("leaderboard", members: [(1.0, "a"), (2.0, "b"), (3.0, "c")])
        
        switch store.zcard("leaderboard") {
        case .success(let count):
            XCTAssertEqual(count, 3)
        case .failure(let error):
            XCTFail("unexpected error: \(error)")
        }
        
        switch store.zcard("missing") {
        case .success(let count):
            XCTAssertEqual(count, 0)
        case .failure:
            XCTFail("should return 0 for missing key")
        }
    }
    
    func testZAddFailsOnWrongType() {
        let store = KeyValueStore()
        
        store.set("string", value: "value")
        
        switch store.zadd("string", members: [(1.0, "a")]) {
        case .success:
            XCTFail("should fail on wrong type")
        case .failure(let error):
            XCTAssertEqual(error, .wrongType)
        }
    }
}
