//
//  ContactView.swift
//  ft_ham
//
//  Created by Pablo Turrion on 16/02/26.
//

import SwiftUI
import MessageUI

// MARK: - Mail Composer

struct MailComposer: UIViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss
    
    let toRecipients = ["ftham@turrion.dev"]
    let subject = "FT8 Ham App Feedback"
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mail = MFMailComposeViewController()
        mail.mailComposeDelegate = context.coordinator
        mail.setToRecipients(toRecipients)
        mail.setSubject(subject)
        return mail
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        
        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            dismiss()
        }
    }
}

// MARK: - Contact View

struct ContactView: View {
    @State private var showMailComposer = false
    
    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Text("Send Feedback")
                .font(.headline)
            
            if MFMailComposeViewController.canSendMail() {
                Button(action: { showMailComposer = true }) {
                    HStack {
                        Image(systemName: "envelope.fill")
                        Text("Send Email")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal)
        .sheet(isPresented: $showMailComposer) {
            MailComposer()
        }
    }
}

// MARK: - Preview

#Preview {
    ContactView()
}
