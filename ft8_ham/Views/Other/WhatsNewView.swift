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
                // Background gradient
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
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 48))
                                .foregroundColor(.blue)
                            
                            Text("what_new_title")
                                .font(.title.bold())
                            
                            Text("Version \(currentVersion)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 12)
                        
                        // Features list
                        VStack(spacing: 16) {
                            whatsNewItem(
                                icon: "waveform",
                                color: .orange,
                                title: "what_new_feature1_title",
                                description: "what_new_feature1_desc"
                            )
                            
                            whatsNewItem(
                                icon: "speedometer",
                                color: .green,
                                title: "what_new_feature2_title",
                                description: "what_new_feature2_desc"
                            )
                            
                            whatsNewItem(
                                icon: "moon.stars.fill",
                                color: .blue,
                                title: "what_new_feature3_title",
                                description: "what_new_feature3_desc"
                            )
                            
                            whatsNewItem(
                                icon: "ant.fill",
                                color: .red,
                                title: "what_new_feature4_title",
                                description: "what_new_feature4_desc"
                            )
                            
                            whatsNewItem(
                                icon: "hand.thumbsup.fill",
                                color: .purple,
                                title: "what_new_feature5_title",
                                description: "what_new_feature5_desc"
                            )
                        }
                        .padding(.horizontal, 20)
                        
                        // Bug fixes section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("what_new_bugfixes")
                                    .font(.headline)
                            }
                            .padding(.horizontal, 20)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                bugFixItem("what_new_bugfix1")
                                bugFixItem("what_new_bugfix2")
                                bugFixItem("what_new_bugfix3")
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.top, 8)
                        
                        // Close button
                        Button {
                            AppVersionManager.shared.markWhatsNewAsViewed()
                            dismiss()
                        } label: {
                            Text("what_new_continue")
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
            .navigationTitle("what_new_nav_title")
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
    private func whatsNewItem(
        icon: String,
        color: Color,
        title: String,
        description: String
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 40, alignment: .center)
                .padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private func bugFixItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.caption.bold())
                .foregroundColor(.green)
                .padding(.top, 2)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    WhatsNewView()
}
