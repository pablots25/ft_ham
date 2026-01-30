//
//  HelpView.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 01/01/26.
//

import SwiftUI

struct HelpView: View {
    
    // MARK: - Sample tutorial/help content
    private let helpSections: [(title: String, text: String)] = [
        ("Introduction", "Welcome to FT8 Ham! This app allows you to monitor and transmit FT8 signals directly from your device. You can view ongoing QSOs, control audio input/output, and manage your settings."),
        ("Getting Started", "1. Connect your radio or SDR device.\n2. Configure audio input and output.\n3. Set your callsign and grid locator.\n4. Tap 'Start' to begin monitoring FT8 signals."),
        ("Using the Decoder", "The decoder will automatically display received messages. Use the 'Clear' button to reset the log and 'Export Logs' to save the session for later analysis."),
        ("Tips & Tricks", "• Adjust input gain carefully to avoid clipping.\n• Monitor multiple frequencies if your hardware allows.\n• Check your logs regularly for interesting DX opportunities."),
        ("Support", "If you encounter any issues, check our online documentation or contact support via email at support@ft8ham.com."),
    ]
    
    // MARK: - Protocol table data
    private struct ProtocolRow: Identifiable {
        let id = UUID()
        let protocolName: String
        let slotDuration: String
        let evenCycle: String
        let oddCycle: String
    }
    
    private let protocolRows: [ProtocolRow] = [
        ProtocolRow(protocolName: "FT8", slotDuration: "15.0s", evenCycle: "0s, 30s", oddCycle: "15s, 45s"),
        ProtocolRow(protocolName: "FT4", slotDuration: "7.5s", evenCycle: "0s, 15s, 30s, 45s", oddCycle: "7.5s, 22.5s, 37.5s, 52.5s")
    ]
    
    // MARK: - Message sequence table
    private struct MessageRow: Identifiable {
        let id = UUID()
        let index: String
        let typicalMessage: String
        let purpose: String
        let state: String
    }
    
    private let messageRows: [MessageRow] = [
        MessageRow(index: "0", typicalMessage: "CQ EA4ABC IN80", purpose: "General call", state: "idle"),
        MessageRow(index: "1", typicalMessage: "DXCALL EA4ABC IN80", purpose: "Respond to a CQ (send your Grid)", state: "calling"),
        MessageRow(index: "2", typicalMessage: "DXCALL EA4ABC -12", purpose: "Send signal report", state: "calling / waitingForReply"),
        MessageRow(index: "3", typicalMessage: "DXCALL EA4ABC R-12", purpose: "Confirm report + send yours", state: "sendingReport"),
        MessageRow(index: "4", typicalMessage: "DXCALL EA4ABC RRR", purpose: "Confirm everything received", state: "waitingForRRR"),
        MessageRow(index: "5", typicalMessage: "DXCALL EA4ABC 73", purpose: "End of QSO", state: "sending73")
    ]
    
    // MARK: - Grid columns
    private let protocolColumns: [GridItem] = [
        GridItem(.flexible(minimum: 60), spacing: 8, alignment: .leading),
        GridItem(.flexible(minimum: 80), spacing: 8, alignment: .leading),
        GridItem(.flexible(minimum: 100), spacing: 8, alignment: .leading),
        GridItem(.flexible(minimum: 100), spacing: 8, alignment: .leading)
    ]
    
    private let messageColumns: [GridItem] = [
        GridItem(.flexible(minimum: 30), spacing: 8, alignment: .leading),
        GridItem(.flexible(minimum: 120), spacing: 8, alignment: .leading),
        GridItem(.flexible(minimum: 150), spacing: 8, alignment: .leading),
        GridItem(.flexible(minimum: 100), spacing: 8, alignment: .leading)
    ]
    
    // MARK: - Row Views
    @ViewBuilder
    private func protocolRowView(_ row: ProtocolRow, index: Int) -> some View {
        Group {
            Text(row.protocolName)
            Text(row.slotDuration)
            Text(row.evenCycle)
            Text(row.oddCycle)
        }
        .font(.system(size: 13, design: .monospaced))
        .padding(6)
        .frame(minWidth: 80, alignment: .leading)
        .background(index % 2 == 0 ? Color(.systemGray5) : Color(.systemGray6))
        .cornerRadius(4)
    }
    
    @ViewBuilder
    private func messageRowView(_ row: MessageRow, index: Int) -> some View {
        Group {
            Text(row.index)
            Text(row.typicalMessage)
            Text(row.purpose)
            Text(row.state)
        }
        .font(.system(size: 13, design: .monospaced))
        .padding(6)
        .frame(minWidth: 80, alignment: .leading)
        .background(index % 2 == 0 ? Color(.systemGray5) : Color(.systemGray6))
        .cornerRadius(4)
    }
    
    // MARK: - Header Views
    private var protocolHeader: some View {
        Group {
            Text("Protocol").font(.subheadline.bold())
            Text("Slot Duration").font(.subheadline.bold())
            Text("Even Cycle").font(.subheadline.bold())
            Text("Odd Cycle").font(.subheadline.bold())
        }
    }
    
    private var messageHeader: some View {
        Group {
            Text("Index").font(.subheadline.bold())
            Text("Typical Message").font(.subheadline.bold())
            Text("Purpose").font(.subheadline.bold())
            Text("Associated State").font(.subheadline.bold())
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // MARK: - Help Sections
                    ForEach(helpSections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.title3.bold())
                                .foregroundStyle(Color.accentColor)
                            Text(section.text)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding()
                        .frame(maxWidth: geometry.size.width * 0.95, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)
                    }
                    
                    // MARK: - Protocol Table
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Protocol Timing Table")
                            .font(.headline.bold())
                            .foregroundStyle(Color.accentColor)
                        
                        ScrollView(.horizontal, showsIndicators: true) {
                            LazyVGrid(columns: protocolColumns, spacing: 4) {
                                protocolHeader
                                ForEach(Array(protocolRows.enumerated()), id: \.element.id) { index, row in
                                    protocolRowView(row, index: index)
                                }
                            }
                            .padding(4)
                            .background(Color(.systemGray5).opacity(0.3))
                            .cornerRadius(8)
                            .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
                        }
                    }
                    .padding(.horizontal)
                    
                    // MARK: - Message Sequence Table
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FT8 Message Sequence")
                            .font(.headline.bold())
                            .foregroundStyle(Color.accentColor)
                        
                        ScrollView(.horizontal, showsIndicators: true) {
                            LazyVGrid(columns: messageColumns, spacing: 4) {
                                messageHeader
                                ForEach(Array(messageRows.enumerated()), id: \.element.id) { index, row in
                                    messageRowView(row, index: index)
                                }
                            }
                            .padding(4)
                            .background(Color(.systemGray5).opacity(0.3))
                            .cornerRadius(8)
                            .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
                        }
                    }
                    .padding(.horizontal)
                    
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Help")
    }
}

struct HelpView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            HelpView()
        }
    }
}
