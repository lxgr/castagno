import XCTest
@testable import CastagnoCore

final class ConnectionFailureTests: XCTestCase {
    func testNetworkDownKeepsRawCodeAndProvidesActionableGuidance() throws {
        let failure = ConnectionFailure(error: NSError(domain: NSPOSIXErrorDomain, code: 50))
        XCTAssertEqual(failure.domain, NSPOSIXErrorDomain)
        XCTAssertEqual(failure.code, 50)
        XCTAssertTrue(failure.networkUnavailable)
        XCTAssertTrue(failure.guidance.contains("Local Network"))
        XCTAssertEqual(try JSONDecoder().decode(ConnectionFailure.self, from: JSONEncoder().encode(failure)), failure)
    }

    func testWrappedNetworkDownIsRecognizedButRefusedConnectionIsNotMisdiagnosed() {
        let wrapped = NSError(domain: "Wrapper", code: 1, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 50)
        ])
        XCTAssertTrue(ConnectionFailure(error: wrapped).networkUnavailable)
        XCTAssertFalse(ConnectionFailure(error: NSError(domain: NSPOSIXErrorDomain, code: 61)).networkUnavailable)
    }
}
