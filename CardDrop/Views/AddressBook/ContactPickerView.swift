import SwiftUI
import ContactsUI

/// Wraps CNContactPickerViewController. No permission prompt needed —
/// iOS handles access internally through the picker UI.
struct ContactPickerView: UIViewControllerRepresentable {
    var onSelect: (String, String, String, String) -> Void   // (name, address, email, phone)

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactPickerView
        init(_ parent: ContactPickerView) { self.parent = parent }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            var address = ""
            if let postal = contact.postalAddresses.first?.value {
                address = PostcardDraft.formatAddress(
                    street: postal.street,
                    city: postal.city,
                    state: postal.state,
                    zip: postal.postalCode,
                    country: postal.country
                )
            }

            // Email: prefer home, then work, then first available
            let emailPriority = [CNLabelHome, CNLabelWork]
            var email = ""
            for label in emailPriority {
                if let match = contact.emailAddresses.first(where: { $0.label == label }) {
                    email = match.value as String; break
                }
            }
            if email.isEmpty { email = contact.emailAddresses.first.map { $0.value as String } ?? "" }

            // Phone: prefer iPhone/mobile, then home, then work, then first available
            let phonePriority = [CNLabelPhoneNumberiPhone, CNLabelPhoneNumberMobile, CNLabelHome, CNLabelWork]
            var phone = ""
            for label in phonePriority {
                if let match = contact.phoneNumbers.first(where: { $0.label == label }) {
                    phone = match.value.stringValue; break
                }
            }
            if phone.isEmpty { phone = contact.phoneNumbers.first.map { $0.value.stringValue } ?? "" }

            parent.onSelect(name, address, email, phone)
        }
    }
}
