import XCTest
import RedisCore

final class RespParserTests: XCTestCase {
    func testParseInlineCommand() {
        var buffer = Data("PING\r\n".utf8)

        switch RespParser.parseCommand(from: &buffer) {
        case .command(let command):
            XCTAssertEqual(command, ["PING"])
            XCTAssertTrue(buffer.isEmpty)
        default:
            XCTFail("expected command")
        }
    }

    func testParseArrayCommand() {
        let raw = "*2\r\n$3\r\nGET\r\n$3\r\nkey\r\n"
        var buffer = Data(raw.utf8)

        switch RespParser.parseCommand(from: &buffer) {
        case .command(let command):
            XCTAssertEqual(command, ["GET", "key"])
            XCTAssertTrue(buffer.isEmpty)
        default:
            XCTFail("expected command")
        }
    }

    func testParseIncompleteBulk() {
        let raw = "*2\r\n$3\r\nGET\r\n$3\r\nke"
        var buffer = Data(raw.utf8)

        switch RespParser.parseCommand(from: &buffer) {
        case .incomplete:
            XCTAssertFalse(buffer.isEmpty)
        default:
            XCTFail("expected incomplete")
        }
    }

    func testParseMultipleCommandsFromBuffer() {
        let raw = "PING\r\nPING\r\n"
        var buffer = Data(raw.utf8)

        switch RespParser.parseCommand(from: &buffer) {
        case .command(let command):
            XCTAssertEqual(command, ["PING"])
        default:
            XCTFail("expected first command")
        }

        switch RespParser.parseCommand(from: &buffer) {
        case .command(let command):
            XCTAssertEqual(command, ["PING"])
            XCTAssertTrue(buffer.isEmpty)
        default:
            XCTFail("expected second command")
        }
    }
}
