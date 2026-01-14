import XCTest
import RedisCore

final class RespEncoderTests: XCTestCase {
    func testSimpleString() {
        let data = RespEncoder.simple("OK")
        XCTAssertEqual(String(data: data, encoding: .utf8), "+OK\r\n")
    }

    func testErrorString() {
        let data = RespEncoder.error("boom")
        XCTAssertEqual(String(data: data, encoding: .utf8), "-ERR boom\r\n")
    }

    func testInteger() {
        let data = RespEncoder.integer(42)
        XCTAssertEqual(String(data: data, encoding: .utf8), ":42\r\n")
    }

    func testBulkNil() {
        let data = RespEncoder.bulk(nil)
        XCTAssertEqual(String(data: data, encoding: .utf8), "$-1\r\n")
    }

    func testArrayWithNil() {
        let data = RespEncoder.array(["a", nil])
        XCTAssertEqual(String(data: data, encoding: .utf8), "*2\r\n$1\r\na\r\n$-1\r\n")
    }
}
