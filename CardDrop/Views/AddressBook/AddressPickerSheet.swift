import SwiftUI
import Contacts

struct AddressPickerSheet: View {
    let role: AddressRole
    var onSelect: (String, String, String, String) -> Void   // (name, address, email, phone)

    @EnvironmentObject private var addressBook: AddressBookManager
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var showContactPicker = false
    @State private var contactResults: [CNContact] = []
    @State private var contactsPermission: CNAuthorizationStatus = CNContactStore.authorizationStatus(for: .contacts)

    private var savedAddresses: [SavedAddress] {
        let pool = role == .sender
            ? addressBook.senderAddresses
            : addressBook.recipientAddresses
        guard !searchText.isEmpty else { return pool }
        return pool.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.address.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // CardDrop saved addresses — always at top
                if savedAddresses.isEmpty && searchText.isEmpty {
                    Section("CardDrop") {
                        Text("No saved addresses yet.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                } else if !savedAddresses.isEmpty {
                    Section("CardDrop") {
                        ForEach(savedAddresses) { entry in
                            Button {
                                onSelect(entry.name, entry.address, entry.email, entry.phone)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.name)
                                        .foregroundColor(.primary)
                                    if !entry.address.isEmpty {
                                        Text(entry.address)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                        .onDelete { indexSet in
                            indexSet.map { savedAddresses[$0] }.forEach {
                                addressBook.delete($0)
                            }
                        }
                    }
                }

                // iPhone Contacts — recipient only
                if role == .recipient {
                    if searchText.isEmpty || contactsPermission == .denied || contactsPermission == .restricted {
                        Section {
                            Button {
                                showContactPicker = true
                            } label: {
                                Label("Browse iPhone Contacts", systemImage: "person.crop.circle")
                            }
                        }
                    } else if !contactResults.isEmpty {
                        Section("iPhone Contacts") {
                            ForEach(contactResults, id: \.identifier) { contact in
                                Button {
                                    onSelect(contactName(contact), contactAddress(contact),
                                             contactEmail(contact), contactPhone(contact))
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(contactName(contact))
                                            .foregroundColor(.primary)
                                        let addr = contactAddress(contact)
                                        if !addr.isEmpty {
                                            Text(addr)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                        } else {
                                            let detail = [contactPhone(contact), contactEmail(contact)]
                                                .filter { !$0.isEmpty }.first ?? ""
                                            if !detail.isEmpty {
                                                Text(detail)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search")
            .navigationTitle(role == .sender ? "Select Sender" : "Select Recipient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: searchText) { _, query in
                searchContacts(query: query)
            }
            .sheet(isPresented: $showContactPicker) {
                ContactPickerView { name, address, email, phone in
                    onSelect(name, address, email, phone)
                    dismiss()
                }
            }
        }
        .dynamicTypeSize(.medium ... .xxxLarge)
    }

    // MARK: - Contact search

    private func searchContacts(query: String) {
        guard !query.isEmpty else { contactResults = []; return }

        switch contactsPermission {
        case .denied, .restricted:
            contactResults = []
        case .notDetermined:
            CNContactStore().requestAccess(for: .contacts) { granted, _ in
                DispatchQueue.main.async {
                    contactsPermission = CNContactStore.authorizationStatus(for: .contacts)
                    if granted { performContactSearch(query: query) }
                }
            }
        default:
            performContactSearch(query: query)
        }
    }

    private func performContactSearch(query: String) {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor
        ]
        let predicate = CNContact.predicateForContacts(matchingName: query)
        let results = (try? CNContactStore().unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []
        DispatchQueue.main.async { contactResults = results }
    }

    // MARK: - Contact field helpers

    private func contactName(_ contact: CNContact) -> String {
        [contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func contactAddress(_ contact: CNContact) -> String {
        guard let postal = contact.postalAddresses.first?.value else { return "" }
        return PostcardDraft.formatAddress(
            street: postal.street, city: postal.city,
            state: postal.state, zip: postal.postalCode, country: postal.country
        )
    }

    private func contactEmail(_ contact: CNContact) -> String {
        let priority = [CNLabelHome, CNLabelWork]
        for label in priority {
            if let match = contact.emailAddresses.first(where: { $0.label == label }) {
                return match.value as String
            }
        }
        return contact.emailAddresses.first.map { $0.value as String } ?? ""
    }

    private func contactPhone(_ contact: CNContact) -> String {
        let priority = [CNLabelPhoneNumberiPhone, CNLabelPhoneNumberMobile, CNLabelHome, CNLabelWork]
        for label in priority {
            if let match = contact.phoneNumbers.first(where: { $0.label == label }) {
                return match.value.stringValue
            }
        }
        return contact.phoneNumbers.first.map { $0.value.stringValue } ?? ""
    }
}
