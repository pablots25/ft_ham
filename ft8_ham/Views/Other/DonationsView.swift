//
//  DonationsView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 16/11/25.
//

import SwiftUI

// MARK: - Tip Jar View

struct TipJarView: View {
    @ObservedObject var manager: ProductManager

    var body: some View {
        VStack(spacing: 15) {
            Text("☕️ Support my app with a coffee")
                .font(.title3)
                .multilineTextAlignment(.center)

            if manager.products.isEmpty {
                ProgressView("Loading...")
            } else {
                ForEach(manager.products, id: \.id) { product in
                    Button("\(product.displayName) – \(product.displayPrice)") {
                        Task {
                            try? await manager.purchase(product)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Main Support Screen

struct SupportView: View {
    @StateObject private var manager = ProductManager()

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                TipJarView(manager: manager)

                Text(
                    "The app works the same even if you don’t donate. These donations are optional and help support its maintenance."
                )
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .foregroundStyle(.gray)
                Text("For app usage policies and donations, see our Privacy Policy and Terms of Use.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .foregroundStyle(.gray)
            }
            .padding()
        }
        .task {
            await manager.fetchProducts()
        }
    }
}

// MARK: - Preview

struct SupportView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SupportView()
        }
    }
}
