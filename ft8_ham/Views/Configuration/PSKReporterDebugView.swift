//
//  PSKReporterDebugView.swift
//  ft8_ham
//
//  Created by Copilot on 2026-02-26.
//

import SwiftUI

struct PSKReporterDebugView: View {
    @ObservedObject private var reporter = PSKReporterReporter.shared
    @EnvironmentObject private var viewModel: FT8ViewModel
    @State private var showFullLog = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🐛 PSK Reporter Debug")
                    .font(.headline)
                Spacer()
                Button {
                    // Clear debug log
                    reporter.debugLog.removeAll()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.blue)
                }
            }
            
            // Integration status
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: viewModel.pskReporterEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(viewModel.pskReporterEnabled ? .green : .red)
                    Text(viewModel.pskReporterEnabled ? "Integration Active" : "Integration Disabled")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                
                if viewModel.pskReporterEnabled {
                    if viewModel.callsign.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Callsign not configured - reports will not be sent")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    } else if reporter.stats.sent > 0 {
                        Text("✓ Reports sent successfully to PSK Reporter")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else {
                        Text("⏳ Waiting for decoded messages to report")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(6)
            .background(Color(.systemGray6))
            .cornerRadius(6)
            
            // Link to PSK Reporter
            Link("View on PSK Reporter →", destination: URL(string: "https://pskreporter.info/pskmap.html")!)
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.top, 4)

            // Stats
            VStack(spacing: 6) {
                HStack(spacing: 20) {
                    StatItem(label: "Sent", value: "\(reporter.stats.sent)", color: .blue)
                    StatItem(label: "Success", value: "\(reporter.stats.successful)", color: .green)
                    StatItem(label: "Held", value: "\(reporter.stats.heldBack)", color: .orange)
                    StatItem(label: "Errors", value: "\(reporter.stats.errors)", color: .red)
                }
                .font(.caption)
                
                // Success rate
                if reporter.stats.sent > 0 {
                    let successRate = Double(reporter.stats.successful) / Double(reporter.stats.sent) * 100
                    HStack {
                        Text("Success Rate:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f%%", successRate))
                            .font(.caption2.bold())
                            .foregroundStyle(successRate > 90 ? .green : (successRate > 70 ? .orange : .red))
                    }
                }
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(6)
            
            // Test mode indicator
            if reporter.isTestMode {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Test Mode Active")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(6)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
            
            // Last error
            if let error = reporter.lastError {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                .padding(6)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }
            
            // Last report info
            if let report = reporter.lastReport {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Last Report:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let packet = reporter.lastPacket {
                            Text("\(packet.count) bytes")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("\(report.senderCallsign) → \(report.receiverCallsign)")
                        .font(.caption.monospaced())
                    HStack {
                        Text("Frequency: \(report.frequencyHz)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text("SNR: \(report.snr) dB")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text("\(String(format: "%.3f", Double(report.frequencyHz) / 1_000_000)) MHz")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("Mode: \(report.mode == .ft8 ? "FT8" : "FT4")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
                .background(Color(.systemGray6))
                .cornerRadius(6)
            } else if viewModel.pskReporterEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No reports sent yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Waiting for decoded RX messages...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
                .background(Color(.systemGray6))
                .cornerRadius(6)
            }
            

            
            // Debug log toggle
            Button {
                showFullLog.toggle()
            } label: {
                HStack {
                    Image(systemName: showFullLog ? "chevron.down" : "chevron.right")
                    Text("Debug Log (\(reporter.debugLog.count))")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            
            if showFullLog {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(reporter.debugLog.indices.reversed(), id: \.self) { idx in
                            Text(reporter.debugLog[idx])
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 150)
                .background(Color(.systemGray6))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

private struct StatItem: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    PSKReporterDebugView()
        .padding()
}
