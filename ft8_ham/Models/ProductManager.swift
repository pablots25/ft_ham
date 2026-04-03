//
//  ProductManager.swift
//  ft_ham
//
//  Created by Pablo Turrion on 16/11/25.
//

import StoreKit

@MainActor
class ProductManager: ObservableObject {
    private let logger = AppLogger(category: "PRODUCTS")
    
    @Published var products: [Product] = []
    
    /// Check if the user has made any purchases
    static func hasMadeAnyPurchase() async -> Bool {
        for await result in Transaction.all {
            if case .verified(_) = result {
                return true
            }
        }
        return false
    }
    
    func fetchProducts() async {
        do {
            let fetched = try await Product.products(for: [
                "coffe_small",
                "coffe_medium",
                "coffee_large",
            ])
            self.products = fetched
            logger.info("Successfully loaded \(fetched.count) products")
        } catch {
            logger.error("Failed to load products: \(error.localizedDescription)")
        }
    }
    
    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        
        switch result {
        case let .success(verification):
            let transaction = try verification.payloadValue
            await transaction.finish()
            
            logger.info("Purchase successful: \(transaction.productID)")
            
            AnalyticsManager.shared.logPurchaseCompleted(
                productID: transaction.productID,
                value: NSDecimalNumber(decimal: product.price).doubleValue,
                currency: product.priceFormatStyle.currencyCode
            )
            
            ProductManager.showSuccessPrompt()
            
        case .userCancelled:
            logger.info("Purchase cancelled by user")
        case .pending:
            logger.info("Purchase pending")
        @unknown default:
            logger.error("Unknown purchase result")
            break
        }
    }
    
    private static func showSuccessPrompt() {
        let alert = UIAlertController(
            title: NSLocalizedString("Thank you!", comment: "Purchase success title"),
            message: NSLocalizedString("Your donation helps us make the app even better. We really appreciate your support!", comment: "Purchase success message"),
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Dismiss button"), style: .default))
        
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = scene.windows.first?.rootViewController {
            
            let topVC = rootVC.presentedViewController ?? rootVC
            topVC.present(alert, animated: true)
        }
    }
    
}
