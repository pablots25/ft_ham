//
//  PurchaseRevenue.swift
//  ft_ham
//

import Foundation

/// The revenue attached to an analytics `purchase` event.
///
/// Prefers what the buyer actually paid (`Transaction.price` and
/// `Transaction.currency`) and falls back to the catalog price of the
/// `Product` when the transaction does not carry one. Without a value and a
/// currency, Google Analytics counts the purchase as zero revenue.
struct PurchaseRevenue: Equatable {
    let value: Double?
    let currency: String?

    init(
        price: Decimal?,
        currency: Locale.Currency?,
        fallbackPrice: Decimal? = nil,
        fallbackCurrencyCode: String? = nil
    ) {
        if let price {
            value = NSDecimalNumber(decimal: price).doubleValue
            self.currency = currency?.identifier ?? fallbackCurrencyCode
        } else if let fallbackPrice {
            value = NSDecimalNumber(decimal: fallbackPrice).doubleValue
            self.currency = fallbackCurrencyCode ?? currency?.identifier
        } else {
            value = nil
            self.currency = currency?.identifier ?? fallbackCurrencyCode
        }
    }
}
