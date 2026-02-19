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
                        
                        // Content
                        VStack(alignment: .leading, spacing: 16) {
                            Text("✨ New Features")
                                .font(.headline)
                                .padding(.top, 8)
                            
                            whatsNewSection(
                                title: "🔗 Contacts Management",
                                description: "Improved contact handling and integration throughout the app."
                            )
                            
                            whatsNewSection(
                                title: "🌍 Country Display in Grid",
                                description: "See the country associated with each callsign directly in the grid view."
                            )
                            
                            whatsNewSection(
                                title: "📍 Callsign Location Detection",
                                description: "Automatic location inference based on callsign prefix."
                            )
                            
                            whatsNewSection(
                                title: "🗺️ Map Controls",
                                description: "Customize which map elements are visible."
                            )
                            
                            Divider()
                                .padding(.vertical, 8)
                            
                            Text("🚀 Improvements")
                                .font(.headline)
                                .padding(.top, 8)
                            
                            whatsNewSection(
                                title: "🔊 AutoCQ Smart Behavior",
                                description: "AutoCQ won't call CQ if the DX is already in your QSO list."
                            )
                            
                            whatsNewSection(
                                title: "📅 Dynamic Log Files",
                                description: "Timestamped log files (FT_HAM_Log_YYYYMMDD_HHMMSS) prevent overwriting and organize logs automatically."
                            )
                            
                            whatsNewSection(
                                title: "📤 Better Log Export",
                                description: "• Export only recent logs\n• Select specific date ranges\n• Incremental export support"
                            )
                            
                            whatsNewSection(
                                title: "💬 App Prompts",
                                description: "Improved consistency and usability of in-app notifications."
                            )
                            
                            Divider()
                                .padding(.vertical, 8)
                            
                            Text("🐛 Bug Fixes")
                                .font(.headline)
                                .padding(.top, 8)
                            
                            whatsNewSection(
                                title: "⚡ Auto TX & Logging",
                                description: "Fixed interleaved QSO entries that were incorrectly marked as invalid when report exchanges weren't sequential."
                            )
                            
                            whatsNewSection(
                                title: "📻 Callsign Switching",
                                description: "Fixed issue where the app could continue transmitting to the previous station instead of switching to the new target callsign."
                            )
                            
                            whatsNewSection(
                                title: "🔧 General Improvements",
                                description: "Various stability and performance enhancements."
                            )
                        }
                        .padding(.horizontal, 20)
                        
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
