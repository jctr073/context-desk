import XCTest
@testable import ContextDesk

/// Pins the mapping from HTTP status + provider `error.type` to the
/// coarse `APIErrorKind` the UI routes on (auth → reopen key sheet,
/// rateLimited → retry banner, etc.).
final class APIErrorKindTests: XCTestCase {
    func test401HTTPStatusMapsToAuth() {
        XCTAssertEqual(APIErrorKind.classify(httpStatus: 401, providerErrorType: nil), .auth)
    }

    func test403HTTPStatusMapsToAuth() {
        XCTAssertEqual(APIErrorKind.classify(httpStatus: 403, providerErrorType: nil), .auth)
    }

    func test429HTTPStatusMapsToRateLimited() {
        XCTAssertEqual(APIErrorKind.classify(httpStatus: 429, providerErrorType: nil), .rateLimited)
    }

    func test529HTTPStatusMapsToOverloaded() {
        XCTAssertEqual(APIErrorKind.classify(httpStatus: 529, providerErrorType: nil), .overloaded)
    }

    func testGeneric5xxMapsToServer() {
        XCTAssertEqual(APIErrorKind.classify(httpStatus: 502, providerErrorType: nil), .server)
        XCTAssertEqual(APIErrorKind.classify(httpStatus: 503, providerErrorType: nil), .server)
    }

    func testProviderTypeOverridesHTTPStatusForRateLimit() {
        // SSE error events ride on a 200 status; the type field is the
        // truth.
        XCTAssertEqual(APIErrorKind.classify(httpStatus: 200, providerErrorType: "rate_limit_error"), .rateLimited)
    }

    func testProviderTypeOverloaded() {
        XCTAssertEqual(APIErrorKind.classify(httpStatus: nil, providerErrorType: "overloaded_error"), .overloaded)
    }

    func testProviderTypeAuth() {
        XCTAssertEqual(APIErrorKind.classify(httpStatus: nil, providerErrorType: "invalid_api_key"), .auth)
        XCTAssertEqual(APIErrorKind.classify(httpStatus: nil, providerErrorType: "authentication_error"), .auth)
        XCTAssertEqual(APIErrorKind.classify(httpStatus: nil, providerErrorType: "permission_error"), .auth)
    }

    func test200WithoutTypeMapsToOther() {
        XCTAssertEqual(APIErrorKind.classify(httpStatus: 200, providerErrorType: nil), .other)
    }

    func testNilStatusAndTypeMapsToOther() {
        XCTAssertEqual(APIErrorKind.classify(httpStatus: nil, providerErrorType: nil), .other)
    }
}
