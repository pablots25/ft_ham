//
//  CQModifierView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 02/19/26.
//

import SwiftUI

// MARK: - Selection View for CQ Modifier
struct CQModifierSelectionView: View {
    @AppStorage("cqModifier") var cqModifierRaw: String = CQModifier.none.rawValue
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section {
                selectionRow(for: .none)
            }
            
            Section(CQModifier.Group.geographic.localizedName) {
                ForEach(CQModifier.modifiers(for: .geographic)) { modifier in
                    selectionRow(for: modifier)
                }
            }
            
            Section(CQModifier.Group.activations.localizedName) {
                ForEach(CQModifier.modifiers(for: .activations)) { modifier in
                    selectionRow(for: modifier)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
        .navigationTitle(Text("CQ Modifier"))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func selectionRow(for modifier: CQModifier) -> some View {
        Button {
            cqModifierRaw = modifier.rawValue
            dismiss()
        } label: {
            HStack {
                Text(modifier.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                if cqModifierRaw == modifier.rawValue {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
    }
}

// MARK: - Main CQ Modifier View
struct CQModifierView: View {
    @AppStorage("cqModifier") var cqModifierRaw: String = CQModifier.none.rawValue
    @AppStorage("myPotaRef") var myPotaRef: String = ""
    @AppStorage("mySotaRef") var mySotaRef: String = ""
    @AppStorage("myWwffRef") var myWwffRef: String = ""
    @AppStorage("myIotaRef") var myIotaRef: String = ""
    
    private var cqModifier: CQModifier {
        CQModifier(rawValue: cqModifierRaw) ?? .none
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                CQModifierSelectionView()
            } label: {
                HStack {
                    Text("CQ Modifier", comment: "Configuration section title")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                        .frame(maxWidth: 50)
                    
                    Text(cqModifier.displayName)
                        .foregroundStyle(.secondary)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            referenceFieldView
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var referenceFieldView: some View {
        if let label = cqModifier.referenceLabel,
           let placeholder = cqModifier.referencePlaceholder {
            HStack {
                Text(label)
                TextField(
                    placeholder,
                    text: referenceBinding(for: cqModifier)
                )
                .textFieldStyle(.roundedBorder)
                .textCase(.uppercase)
                .autocapitalization(.allCharacters)
            }
        }
    }
    
    private func referenceBinding(for modifier: CQModifier) -> Binding<String> {
        switch modifier {
        case .pota: return $myPotaRef
        case .sota: return $mySotaRef
        case .wwff: return $myWwffRef
        case .iota: return $myIotaRef
        default: return .constant("")
        }
    }
}

#Preview {
    NavigationStack {
        CQModifierView()
    }
}

