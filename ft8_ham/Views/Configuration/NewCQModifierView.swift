//
//  NewCQModifierView.swift
//  ft_ham
//
//  CQ Modifier views adapted for the new Settings-style configuration.
//

import SwiftUI

// MARK: - Selection View for CQ Modifier (Settings-style)
struct NewCQModifierSelectionView: View {
    @AppStorage("cqModifier") var cqModifierRaw: String = CQModifier.none.rawValue
    @AppStorage("cqModifierOther") var cqModifierOther: String = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Group {
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

            Section(CQModifier.Group.custom.localizedName) {
                selectionRow(for: .other)
            }
            }
            .padding(.horizontal)
        }
        .settingsFormStyle(title: "CQ Modifier")
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
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}

// MARK: - Main CQ Modifier View (Settings-style)
struct NewCQModifierView: View {
    @AppStorage("cqModifier") var cqModifierRaw: String = CQModifier.none.rawValue
    @AppStorage("cqModifierOther") var cqModifierOther: String = ""
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
                NewCQModifierSelectionView()
            } label: {
                HStack {
                    Text("CQ Modifier", comment: "Configuration section title")

                    Spacer()

                    Text(selectedModifierDisplay)
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            referenceFieldView
        }
    }
    
    @ViewBuilder
    private var referenceFieldView: some View {
        if cqModifier == .other {
            HStack {
                Text(String(localized: "Custom modifier:"))
                TextField(
                    String(localized: "e.g. WWA"),
                    text: $cqModifierOther
                )
                .textFieldStyle(.roundedBorder)
                .textCase(.uppercase)
                .autocapitalization(.allCharacters)
                .onChange(of: cqModifierOther) { value in
                    cqModifierOther = sanitizeCustomModifier(value)
                }
            }
        }

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

    private var selectedModifierDisplay: String {
        if cqModifier == .other {
            let custom = sanitizeCustomModifier(cqModifierOther)
            return custom.isEmpty ? String(localized: "Others") : "\(String(localized: "Others")): \(custom)"
        }
        return cqModifier.displayName
    }

    private func sanitizeCustomModifier(_ value: String) -> String {
        let upper = value.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = upper.filter { $0.isLetter || $0.isNumber || $0 == "/" }
        return String(filtered.prefix(4))
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
        NewCQModifierView()
    }
}
