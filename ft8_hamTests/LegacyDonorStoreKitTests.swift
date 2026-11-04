//
//  LegacyDonorStoreKitTests.swift
//  ft8_hamTests
//
//  Runs PremiumManager.loadPremiumStatus against a StoreKit test session, so
//  finished tips really come back from `Transaction.all`. Tips in a test session
//  are always dated now, so each test moves the cutoff around that moment.
//

import XCTest
import StoreKit
import StoreKitTest
@testable import ft8_ham

@MainActor
final class LegacyDonorStoreKitTests: XCTestCase {

    private var session: SKTestSession!
    private var configURL: URL!
    private var savedDebugPremium: Any?

    override func setUp() async throws {
        try await super.setUp()
        // The debug override would unlock premium before any transaction is read.
        savedDebugPremium = UserDefaults.standard.object(forKey: "debug_premium_enabled")
        UserDefaults.standard.set(false, forKey: "debug_premium_enabled")

        configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacyDonor-\(UUID().uuidString).storekit")
        try Self.configuration.write(to: configURL, atomically: true, encoding: .utf8)
        session = try SKTestSession(contentsOf: configURL)
        session.disableDialogs = true
        session.clearTransactions()
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        session = nil
        if let configURL { try? FileManager.default.removeItem(at: configURL) }
        UserDefaults.standard.set(savedDebugPremium, forKey: "debug_premium_enabled")
        try await super.tearDown()
    }

    private func manager(cutoff: Date) -> PremiumManager {
        PremiumManager(fetcher: NoProductFetcher(), observesTransactions: false, donationCutoff: cutoff)
    }

    private func buyAndFinishTip(_ id: String = "coffee_large") async throws -> Transaction {
        guard #available(iOS 17, *) else { throw XCTSkip("SKTestSession.buyProduct(identifier:) needs iOS 17") }
        let transaction = try await session.buyProduct(identifier: id)
        // Only finished consumables count as purchase history.
        await transaction.finish()
        return transaction
    }

    /// The test session applies refunds asynchronously, so `Transaction.all` can
    /// still show the tip as unrevoked right after `refundTransaction`.
    private func waitUntilRevoked(_ id: UInt64, timeout: Duration = .seconds(5)) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            for await result in Transaction.all {
                if case let .verified(transaction) = result,
                   transaction.id == id, transaction.revocationDate != nil {
                    return
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Refund of transaction \(id) never showed up in Transaction.all")
    }

    private func requireConsumableHistory() throws {
        guard #available(iOS 18, *) else {
            throw XCTSkip("Finished consumables only show up in Transaction.all on iOS 18+")
        }
    }

    // MARK: - Tests

    func test_finishedTipBeforeCutoff_unlocksPremiumAsLegacyDonor() async throws {
        try requireConsumableHistory()
        for id in PremiumManager.donationProductIDs.sorted() {
            session.clearTransactions()
            _ = try await buyAndFinishTip(id)
            let sut = manager(cutoff: Date().addingTimeInterval(86_400))

            await sut.loadPremiumStatus()

            XCTAssertTrue(sut.isPremiumUnlocked, id)
            XCTAssertTrue(sut.isLegacyDonor, id)
            XCTAssertFalse(sut.isBetaUser, id)
        }
    }

    func test_tipAfterCutoff_doesNotUnlockPremium() async throws {
        try requireConsumableHistory()
        _ = try await buyAndFinishTip()
        let sut = manager(cutoff: Date().addingTimeInterval(-86_400))

        await sut.loadPremiumStatus()

        XCTAssertFalse(sut.isPremiumUnlocked)
        XCTAssertFalse(sut.isLegacyDonor)
    }

    /// A tip bought today follows the real cutoff: premium until the 1.3.0
    /// phased release ends, nothing after it.
    func test_tipToday_withDefaultCutoff_followsTheRealCutoff() async throws {
        try requireConsumableHistory()
        _ = try await buyAndFinishTip()
        let sut = PremiumManager(fetcher: NoProductFetcher(), observesTransactions: false)

        await sut.loadPremiumStatus()

        XCTAssertEqual(sut.isPremiumUnlocked, Date() < PremiumManager.legacyDonationCutoff)
    }

    func test_refundedLegacyTip_revokesPremium() async throws {
        try requireConsumableHistory()
        let transaction = try await buyAndFinishTip()
        let sut = manager(cutoff: Date().addingTimeInterval(86_400))
        await sut.loadPremiumStatus()
        XCTAssertTrue(sut.isPremiumUnlocked)

        let revoked = expectation(forNotification: .premiumRevoked, object: nil)
        try session.refundTransaction(identifier: UInt(transaction.id))
        try await waitUntilRevoked(transaction.id)
        await sut.loadPremiumStatus()

        await fulfillment(of: [revoked], timeout: 2)
        XCTAssertFalse(sut.isPremiumUnlocked)
        XCTAssertFalse(sut.isLegacyDonor)
    }

    func test_noPurchases_doesNotUnlockPremium() async throws {
        let sut = manager(cutoff: Date().addingTimeInterval(86_400))

        await sut.loadPremiumStatus()

        XCTAssertFalse(sut.isPremiumUnlocked)
        XCTAssertFalse(sut.isLegacyDonor)
    }

    // MARK: - StoreKit configuration

    /// The three tip products as they exist in App Store Connect.
    private static let configuration: String = {
        let products = PremiumManager.donationProductIDs.sorted().enumerated().map { index, id in
            """
            {
              "displayPrice" : "\(index + 1).99",
              "familyShareable" : false,
              "internalID" : "\(9_000_000 + index)",
              "localizations" : [
                { "description" : "\(id)", "displayName" : "\(id)", "locale" : "en_US" }
              ],
              "productID" : "\(id)",
              "referenceName" : "\(id)",
              "type" : "Consumable"
            }
            """
        }
        return """
        {
          "identifier" : "LegacyDonorStoreKitTests",
          "nonRenewingSubscriptions" : [],
          "products" : [\(products.joined(separator: ","))],
          "settings" : {},
          "subscriptionGroups" : [],
          "version" : { "major" : 3, "minor" : 0 }
        }
        """
    }()
}

private struct NoProductFetcher: ProductFetching {
    func fetchProducts(for identifiers: [String]) async throws -> [Product] { [] }
}
