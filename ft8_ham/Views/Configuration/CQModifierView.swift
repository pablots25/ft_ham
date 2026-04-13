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
    @AppStorage("cqModifierOther") var cqModifierOther: String = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                selectionRow(for: .none)
                
                Divider()
            
                Text(CQModifier.Group.geographic.localizedName)
                    .font(.headline)

                ForEach(CQModifier.modifiers(for: .geographic)) { modifier in
                    selectionRow(for: modifier)
                }
                
                Divider()
            
                Text(CQModifier.Group.activations.localizedName)
                    .font(.headline)

                ForEach(CQModifier.modifiers(for: .activations)) { modifier in
                    selectionRow(for: modifier)
                }
                
                Divider()

                Text(CQModifier.Group.custom.localizedName)
                    .font(.headline)

                selectionRow(for: .other)
            }
            .padding(.horizontal)
        }
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
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}

// MARK: - Main CQ Modifier View
struct CQModifierView: View {
    @AppStorage("cqModifier") var cqModifierRaw: String = CQModifier.none.rawValue
    @AppStorage("cqModifierOther") var cqModifierOther: String = ""
    @AppStorage("myPotaRef") var myPotaRef: String = ""
    @AppStorage("mySotaRef") var mySotaRef: String = ""
    @AppStorage("myWwffRef") var myWwffRef: String = ""
    @AppStorage("myIotaRef") var myIotaRef: String = ""
    @AppStorage("autoCQReplyEnabled") private var autoCQReplyEnabled: Bool = false
    @AppStorage("autoQSOLogging") private var autoQSOLogging: Bool = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingActivationModeAlert = false
    
    private var cqModifier: CQModifier {
        CQModifier(rawValue: cqModifierRaw) ?? .none
    }

    private var isActivationModifier: Bool {
        cqModifier.group == .activations
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                CQModifierSelectionView()
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
                .cornerRadius(8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            referenceFieldView

            if isActivationModifier {
                Button("Apply Activation Mode") {
                    showingActivationModeAlert = true
                }
                .font(.subheadline)
                .padding(.top, 4)
                .alert("Apply Activation Mode?", isPresented: $showingActivationModeAlert) {
                    Button("Apply") {
                        autoCQReplyEnabled = true
                        autoQSOLogging = true
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will enable Auto CQ Reply and Auto QSO Logging.")
                }
            }
        }
        .padding(.horizontal, horizontalSizeClass == .compact ? 20 : 0)
        .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
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
            let binding = referenceBinding(for: cqModifier)
            let isValid = cqModifier.isValidReference(binding.wrappedValue)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label)
                    TextField(
                        placeholder,
                        text: binding
                    )
                    .textFieldStyle(.roundedBorder)
                    .textCase(.uppercase)
                    .autocapitalization(.allCharacters)
                    .onChange(of: binding.wrappedValue) { value in
                        let sanitized = sanitizeActivationReference(value, for: cqModifier)
                        if sanitized != value {
                            binding.wrappedValue = sanitized
                        }
                    }

                    if !binding.wrappedValue.isEmpty {
                        Image(systemName: isValid ? "checkmark.circle" : "exclamationmark.circle")
                            .foregroundStyle(isValid ? .green : .red)
                            .animation(.easeInOut, value: isValid)
                    }
                }

                if !binding.wrappedValue.isEmpty, !isValid, let hint = cqModifier.referenceFormatHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .transition(.opacity)
                }
            }
        }
    }

    private var selectedModifierDisplay: String {
        if cqModifier == .other {
            let custom = sanitizeCustomModifier(cqModifierOther)
            return custom.isEmpty ? String(localized: "Others") : "\(String(localized: "Others")): \(custom)"
        }
        // For activation modifiers, show the reference if set
        if cqModifier.requiresReference {
            let ref = referenceBinding(for: cqModifier).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ref.isEmpty {
                return "\(cqModifier.rawValue): \(ref)"
            }
        }
        return cqModifier.displayName
    }

    private func sanitizeCustomModifier(_ value: String) -> String {
        let upper = value.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = upper.filter { $0.isLetter || $0.isNumber || $0 == "/" }
        return String(filtered.prefix(4))
    }

    /// Sanitizes activation references — allows letters, digits, hyphens, slashes and commas (for multiple POTA refs).
    private func sanitizeActivationReference(_ value: String, for modifier: CQModifier) -> String {
        let upper = value.uppercased()
        switch modifier {
        case .pota:
            // Allow letters, digits, hyphen, comma, space (for multiple parks)
            return upper.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "," || $0 == " " }
        default:
            // Allow letters, digits, hyphen, slash
            return upper.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "/" }
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

