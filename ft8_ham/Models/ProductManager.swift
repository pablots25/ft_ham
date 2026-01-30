//
//  ProductManager.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 16/11/25.
//

import StoreKit

@MainActor
class ProductManager: ObservableObject {
    private let logger = AppLogger(category: "PRODUCTS")
    
    @Published var products: [Product] = []
    
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
            title: "Thank you!",
            message: "Your donation helps us make the app even better. We really appreciate your support!",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = scene.windows.first?.rootViewController {
            
            let topVC = rootVC.presentedViewController ?? rootVC
            topVC.present(alert, animated: true)
        }
    }
    
}
