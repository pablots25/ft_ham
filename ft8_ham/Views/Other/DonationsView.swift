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

            switch manager.loadingState {
            case .idle, .loading:
                ProgressView("Loading...")
            case .loaded:
                ForEach(manager.products, id: \.id) { product in
                    Button("\(product.displayName) – \(product.displayPrice)") {
                        Task {
                            try? await manager.purchase(product)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .failed:
                VStack(spacing: 10) {
                    Text("Could not load donation options.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await manager.fetchProducts() }
                    }
                    .buttonStyle(.bordered)
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
            VStack(spacing: 10) {
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
