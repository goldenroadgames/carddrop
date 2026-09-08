import SwiftUI
import ContactsUI

/// Full contact info captured when the "To" nickname field's contact picker is
/// used, so the rest of the create flow (address step, digital-send recipient
/// slots) already has this recipient's details in memory without asking again.
struct PickedContactInfo {
    let nickname: String       // contact's nickname, else given name, else organization name
    let firstName: String
    let lastName: String
    let street: String
    let city: String
    let state: String
    let zip: String
    let country: String
    let email: String
    let phone: String
}

/// Wraps CNContactPickerViewController for the Names step's "To" field. Resolves
/// a nickname-priority display name (nickname → given name → organization name)
/// while also capturing the contact's formal name, address, email, and phone —
/// so a contact picked here fully populates the recipient in memory, ready to
/// prefill the To/From address step and the digital-send recipient sheets.
///
/// CNContactPickerViewController's didSelect delegate hands back a CNContact that
/// isn't guaranteed to include nickname/organization — those aren't part of the
/// default set the picker fetches — so this re-fetches the contact by identifier
/// with the exact keys needed.
struct ContactNamePickerView: UIViewControllerRepresentable {
    var onSelect: (PickedContactInfo) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactNamePickerView
        init(_ parent: ContactNamePickerView) { self.parent = parent }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {}

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let keysToFetch: [CNKeyDescriptor] = [
                CNContactNicknameKey as CNKeyDescriptor,
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactPostalAddressesKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor
            ]
            let resolved = (try? CNContactStore().unifiedContact(withIdentifier: contact.identifier, keysToFetch: keysToFetch)) ?? contact

            let nickname = [resolved.nickname, resolved.givenName, resolved.organizationName]
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""

            let postal = resolved.postalAddresses.first?.value

            let emailPriority = [CNLabelHome, CNLabelWork]
            var email = ""
            for label in emailPriority {
                if let match = resolved.emailAddresses.first(where: { $0.label == label }) {
                    email = match.value as String; break
                }
            }
            if email.isEmpty { email = resolved.emailAddresses.first.map { $0.value as String } ?? "" }

            let phonePriority = [CNLabelPhoneNumberiPhone, CNLabelPhoneNumberMobile, CNLabelHome, CNLabelWork]
            var phone = ""
            for label in phonePriority {
                if let match = resolved.phoneNumbers.first(where: { $0.label == label }) {
                    phone = match.value.stringValue; break
                }
            }
            if phone.isEmpty { phone = resolved.phoneNumbers.first.map { $0.value.stringValue } ?? "" }

            parent.onSelect(PickedContactInfo(
                nickname: nickname,
                firstName: resolved.givenName,
                lastName: resolved.familyName,
                street: postal?.street ?? "",
                city: postal?.city ?? "",
                state: postal?.state ?? "",
                zip: postal?.postalCode ?? "",
                country: postal?.country ?? "",
                email: email,
                phone: phone
            ))
        }
    }
}
