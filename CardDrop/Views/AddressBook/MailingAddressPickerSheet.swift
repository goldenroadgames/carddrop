import SwiftUI
import ContactsUI

/// Picker sheet for the server-side mailing address book (SavedMailingAddress)
/// used by the physical-mail (LOB) send flow — distinct from AddressPickerSheet,
/// which picks from the local freeform AddressBookManager for the digital-send
/// flow. `role` selects which bucket is shown (and what type a newly-added or
/// Contacts-picked address is saved as): sender addresses show the profile
/// address plus any previously-used senders; recipient addresses show only
/// saved recipients, plus an iPhone Contacts option.
struct MailingAddressPickerSheet: View {
    let role: MailingAddressType
    var onSelect: (SavedMailingAddress) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var addresses: [SavedMailingAddress] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showAddForm = false
    @State private var showContactPicker = false
    @State private var isSavingContact = false
    @State private var contactSaveError: String?
    @State private var showContactSaveError = false

    private var filtered: [SavedMailingAddress] {
        switch role {
        case .sender:
            return addresses
                .filter { $0.addressType == .sender || $0.addressType == .profile }
                .sorted { ($0.addressType == .profile ? 0 : 1) < ($1.addressType == .profile ? 0 : 1) }
        case .profile, .recipient:
            return addresses.filter { $0.addressType == .recipient }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let loadError {
                    Section {
                        Text(loadError).foregroundColor(.red).font(.subheadline)
                    }
                }
                if filtered.isEmpty && !isLoading {
                    Section {
                        Text("No saved addresses yet.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    Section {
                        ForEach(filtered) { address in
                            Button {
                                onSelect(address)
                                dismiss()
                            } label: {
                                row(for: address)
                            }
                            .foregroundColor(.primary)
                        }
                    }
                }

                Section {
                    Button {
                        showAddForm = true
                    } label: {
                        Label("Add New Address", systemImage: "plus")
                    }
                    if role == .recipient {
                        Button {
                            showContactPicker = true
                        } label: {
                            Label("Choose from Contacts", systemImage: "person.crop.circle")
                        }
                    }
                }
            }
            .navigationTitle(role == .sender ? "Select Sender" : "Select Recipient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarPillItem("Cancel", placement: .cancellationAction, style: .filled) { dismiss() }
            }
            .task { await load() }
            .sheet(isPresented: $showAddForm) {
                MailingAddressFormView(existing: nil, defaultType: role == .sender ? .sender : .recipient) { saved in
                    onSelect(saved)
                    dismiss()
                }
            }
            .sheet(isPresented: $showContactPicker) {
                ContactNamePickerView(
                    onSelect: { info in Task { await saveContactAndSelect(info) } },
                    enablingPredicate: NSPredicate(format: "postalAddresses.@count > 0")
                )
            }
            .overlay {
                if isSavingContact {
                    ProgressView("Saving…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .alert("Couldn't Save Contact", isPresented: $showContactSaveError, presenting: contactSaveError) { _ in
                Button("OK") {}
            } message: { message in
                Text(message)
            }
        }
        .dynamicTypeSize(.medium ... .xxxLarge)
    }

    @ViewBuilder
    private func row(for address: SavedMailingAddress) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(address.nickname?.isEmpty == false ? address.nickname! : address.displayName)
                    .font(.body)
                if !address.formattedAddress.isEmpty {
                    Text(address.formattedAddress)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if address.isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            addresses = try await AddressBookService.fetch()
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Contacts picked here are saved into user_address_book (type: recipient)
    /// automatically, not left as one-off picks — matches the standing product
    /// decision so the address is reusable from the picker next time.
    private func saveContactAndSelect(_ info: PickedContactInfo) async {
        isSavingContact = true
        defer { isSavingContact = false }

        let record = SavedMailingAddress(
            id: UUID(),
            nickname: nil,
            firstName: info.firstName.isEmpty ? nil : info.firstName,
            lastName: info.lastName.isEmpty ? nil : info.lastName,
            street: info.street,
            city: info.city,
            state: info.state,
            zip: info.zip,
            country: info.country.isEmpty ? "US" : info.country,
            email: info.email.isEmpty ? nil : info.email,
            phone: info.phone.isEmpty ? nil : info.phone,
            addressType: .recipient,
            isVerified: false,
            verifiedAt: nil,
            lobVerificationID: nil,
            lastUsedAt: Date()
        )

        do {
            let saved = try await AddressBookService.save(record, existing: nil)
            onSelect(saved)
            dismiss()
            _ = try? await AddressBookService.verify(id: saved.id)
        } catch {
            contactSaveError = error.localizedDescription
            showContactSaveError = true
        }
    }
}
