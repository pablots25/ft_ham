//
//  PurchaseRevenueTests.swift
//  ft8_hamTests
//

import XCTest
@testable import ft8_ham

/// Purchases must reach Analytics with a value and a currency, otherwise
/// Google Analytics counts them as zero revenue. Before this fix, purchases
/// completing outside `purchase()` on iOS 16 were logged without either.
final class PurchaseRevenueTests: XCTestCase {

    private let euro = Locale.Currency("EUR")

    func testUsesTransactionPriceAndCurrency() {
        let revenue = PurchaseRevenue(price: Decimal(string: "4.99"), currency: euro)

        XCTAssertEqual(revenue.value ?? 0, 4.99, accuracy: 0.0001)
        XCTAssertEqual(revenue.currency, "EUR")
    }

    func testTransactionPriceWinsOverCatalogPrice() {
        // An offer code or promotion makes the paid price lower than the catalog price.
        let revenue = PurchaseRevenue(
            price: Decimal(string: "1.99"),
            currency: euro,
            fallbackPrice: Decimal(string: "4.99"),
            fallbackCurrencyCode: "USD"
        )

        XCTAssertEqual(revenue.value ?? 0, 1.99, accuracy: 0.0001)
        XCTAssertEqual(revenue.currency, "EUR")
    }

    func testFallsBackToCatalogPriceWhenTransactionHasNone() {
        let revenue = PurchaseRevenue(
            price: nil,
            currency: nil,
            fallbackPrice: Decimal(string: "2.99"),
            fallbackCurrencyCode: "USD"
        )

        XCTAssertEqual(revenue.value ?? 0, 2.99, accuracy: 0.0001)
        XCTAssertEqual(revenue.currency, "USD")
    }

    func testFillsMissingTransactionCurrencyFromCatalog() {
        let revenue = PurchaseRevenue(
            price: Decimal(string: "0.99"),
            currency: nil,
            fallbackPrice: Decimal(string: "0.99"),
            fallbackCurrencyCode: "GBP"
        )

        XCTAssertEqual(revenue.value ?? 0, 0.99, accuracy: 0.0001)
        XCTAssertEqual(revenue.currency, "GBP")
    }

    func testZeroPriceIsReportedAsZeroNotMissing() {
        let revenue = PurchaseRevenue(price: 0, currency: euro)

        XCTAssertEqual(revenue.value, 0)
        XCTAssertEqual(revenue.currency, "EUR")
    }

    func testNoPriceAnywhereLeavesValueEmpty() {
        let revenue = PurchaseRevenue(price: nil, currency: nil)

        XCTAssertNil(revenue.value)
        XCTAssertNil(revenue.currency)
    }
}
