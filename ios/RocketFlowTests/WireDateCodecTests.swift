import Foundation
import XCTest
@testable import RocketFlow

final class WireDateCodecTests: XCTestCase {
    func testDecodesFractionalAndNonFractionalUTCInstants() throws {
        let fractional = try WireDateCodec.decode("2026-08-22T10:11:12.345678Z")
        let whole = try WireDateCodec.decode("2026-08-22T10:11:12Z")

        XCTAssertEqual(fractional.timeIntervalSince1970, 1_787_393_472.345678, accuracy: 0.001)
        XCTAssertEqual(whole.timeIntervalSince1970, 1_787_393_472, accuracy: 0.001)
    }

    func testEncodesUTCWithFractionalSeconds() throws {
        let date = try WireDateCodec.decode("2026-08-22T10:11:12.125Z")

        XCTAssertEqual(WireDateCodec.encode(date), "2026-08-22T10:11:12.125Z")
    }

    func testRejectsInvalidCalendarDate() {
        XCTAssertNil(LocalDate(rawValue: "2026-02-30"))
        XCTAssertEqual(LocalDate(rawValue: "2026-02-28")?.rawValue, "2026-02-28")
    }
}
