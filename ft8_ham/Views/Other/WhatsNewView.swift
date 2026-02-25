//
//  WhatsNewView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 16/02/26.
//

import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) var dismiss
    
    private let currentVersion = AppVersionManager.shared.currentVersion
    private let remoteConfig = RemoteConfigProvider()
    
    private var whatsNewConfig: WhatsNewConfig.WhatsNewSettings? {
        let config = remoteConfig.getWhatsNewConfig()
        return config.whatsNew.enabled ? config.whatsNew : nil
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.blue.opacity(0.1),
                        Color.purple.opacity(0.1)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 48))
                                .foregroundColor(.blue)
                            
                            Text("What's New")
                                .font(.title.bold())
                            
                            Text("Version \(currentVersion)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 12)
                        
                        // Content - only show if config is available
                        if let config = whatsNewConfig {
                            contentView(config: config)
                        } else {
                            // No content available - this shouldn't normally be shown
                            Text("No updates available")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 20)
                        }
                        
                        // Close button
                        Button {
                            AppVersionManager.shared.markWhatsNewAsViewed()
                            dismiss()
                        } label: {
                            Text("Let's Go")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                    }
                }
            }
            .navigationTitle("What's New in FT Ham")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        AppVersionManager.shared.markWhatsNewAsViewed()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func contentView(config: WhatsNewConfig.WhatsNewSettings) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Features Section
            if !config.features.isEmpty {
                Text("✨ New Features")
                    .font(.headline)
                    .padding(.top, 8)
                
                ForEach(config.features) { item in
                    whatsNewSection(title: item.title, description: item.description)
                }
            }
            
            // Improvements Section
            if !config.improvements.isEmpty {
                Divider()
                    .padding(.vertical, 8)
                
                Text("🚀 Improvements")
                    .font(.headline)
                    .padding(.top, 8)
                
                ForEach(config.improvements) { item in
                    whatsNewSection(title: item.title, description: item.description)
                }
            }
            
            // Bug Fixes Section
            if !config.bugFixes.isEmpty {
                Divider()
                    .padding(.vertical, 8)
                
                Text("🐛 Bug Fixes")
                    .font(.headline)
                    .padding(.top, 8)
                
                ForEach(config.bugFixes) { item in
                    whatsNewSection(title: item.title, description: item.description)
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder
    private func whatsNewSection(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    WhatsNewView()
}
