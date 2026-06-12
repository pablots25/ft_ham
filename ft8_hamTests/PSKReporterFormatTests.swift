// PSKReporterFormatTests.swift
// ft8_hamTests
//
// Regression tests for PSK Reporter packet correctness.
//
// Bug fixed: The decoderSoftware field (IPFIX 30351.8) was formatted as
// "FT Ham - X.Y.Z" instead of "FT Ham vX.Y.Z". The official PSK Reporter
// spec (pskreporter.info/pskdev.html) uses "v" as the separator, e.g.
// "Homebrew v5.6". The wrong format caused the "Using:" label to be absent
// or unparseable on the PSK Reporter statistics page.
//
// Second bug fixed: PSKReporterReporter was creating a new NWConnection per
// packet, giving every packet a different UDP source port. PSK Reporter caches
// templates by IP+port; without a stable port the server cannot decode packets
// that omit the template (sent after the first 3).

import XCTest
@testable import ft8_ham

@MainActor
final class PSKReporterFormatTests: XCTestCase {

    // MARK: - decoderSoftware format

    /// The decoderSoftware string exposed by the stub (and by the real implementation
    /// when the premium package is present) must use space-v as the separator, matching
    /// the official PSK Reporter spec example: "Homebrew v5.6".
    func test_decoderSoftware_usesVPrefix() {
        let reporter = PremiumFeatures.pskReporter
        XCTAssertTrue(
            reporter.decoderSoftware.hasPrefix("FT Ham v"),
            "decoderSoftware must start with 'FT Ham v' per PSK Reporter spec. Got: \(reporter.decoderSoftware)"
        )
    }

    func test_decoderSoftware_doesNotContainDashSeparator() {
        let reporter = PremiumFeatures.pskReporter
        XCTAssertFalse(
            reporter.decoderSoftware.contains(" - "),
            "decoderSoftware must not contain ' - ' separator. Got: \(reporter.decoderSoftware)"
        )
    }

    func test_decoderSoftware_containsVersionNumber() {
        let reporter = PremiumFeatures.pskReporter
        let parts = reporter.decoderSoftware.split(separator: "v", maxSplits: 1)
        XCTAssertEqual(parts.count, 2,
                       "decoderSoftware must contain a 'v' followed by a version. Got: \(reporter.decoderSoftware)")
        let versionPart = String(parts[1])
        // Version should look like "1.0", "1.2.3", etc.
        let versionComponents = versionPart.split(separator: ".")
        XCTAssertTrue(versionComponents.count >= 1,
                      "Version part should have at least one numeric component. Got: \(versionPart)")
        XCTAssertNotNil(Int(versionComponents[0]),
                        "First version component should be numeric. Got: \(versionComponents[0])")
    }

    /// Stub format must match the real implementation's format contract.
    func test_decoderSoftware_stubMatchesExpectedFormat() {
        let stub = PSKReporterStub.shared
        XCTAssertTrue(
            stub.decoderSoftware.hasPrefix("FT Ham v"),
            "Stub decoderSoftware must follow the same format contract. Got: \(stub.decoderSoftware)"
        )
    }
}
