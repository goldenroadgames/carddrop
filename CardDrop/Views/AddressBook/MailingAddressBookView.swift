import SwiftUI

// Server-side, LOB-verified mailing addresses (see AddressBookService) —
// distinct from AddressPickerSheet/AddressBookManager's local, freeform
// contact-autofill address book, which this doesn't touch.
struct MailingAddressBookView: View {
    @State private var addresses: [SavedMailingAddress] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showAddForm = false
    @State private var editingAddress: SavedMailingAddress?
    @State private var verifyingID: UUID?
    @State private var verifyError: String?
    @State private var showVerifyError = false
    @State private var addressToDelete: SavedMailingAddress?

    var body: some View {
        List {
            if let loadError {
                Section {
                    Text(loadError)
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
            }
            if addresses.isEmpty && !isLoading {
                Section {
                    Text("No saved mailing addresses yet.")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
            } else {
                Section {
                    ForEach(addresses) { address in
                        Button {
                            editingAddress = address
                        } label: {
                            row(for: address)
                        }
                        .foregroundColor(.primary)
                    }
                    .onDelete(perform: delete)
                } footer: {
                    Text("Verified addresses have already been checked with our mail carrier and won't be re-verified.")
                }
            }
        }
        .navigationTitle("Saved Addresses")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddForm = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showAddForm) {
            MailingAddressFormView(existing: nil) { _ in await load() }
        }
        .sheet(item: $editingAddress) { address in
            MailingAddressFormView(existing: address) { _ in await load() }
        }
        .alert("Delete this address?", isPresented: Binding(
            get: { addressToDelete != nil },
            set: { if !$0 { addressToDelete = nil } }
        ), presenting: addressToDelete) { address in
            Button("Delete", role: .destructive) { deleteAddress(address) }
            Button("Cancel", role: .cancel) {}
        } message: { address in
            Text(address.nickname?.isEmpty == false ? address.nickname! : address.displayName)
        }
        .alert("Couldn't Verify Address", isPresented: $showVerifyError, presenting: verifyError) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }

    @ViewBuilder
    private func row(for address: SavedMailingAddress) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(address.nickname?.isEmpty == false ? address.nickname! : address.displayName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                if !address.formattedAddress.isEmpty {
                    Text(address.formattedAddress)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if address.isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
            } else if verifyingID == address.id {
                ProgressView()
            } else {
                Button("Verify") {
                    Task { await verify(address) }
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
            }
            Button {
                addressToDelete = address
            } label: {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(.borderless)
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

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { addresses[$0] }
        addresses.remove(atOffsets: offsets)
        Task {
            for address in toDelete {
                try? await AddressBookService.delete(id: address.id)
            }
        }
    }

    private func deleteAddress(_ address: SavedMailingAddress) {
        addresses.removeAll { $0.id == address.id }
        Task { try? await AddressBookService.delete(id: address.id) }
    }

    private func verify(_ address: SavedMailingAddress) async {
        verifyingID = address.id
        defer { verifyingID = nil }
        do {
            let updated = try await AddressBookService.verify(id: address.id)
            if let index = addresses.firstIndex(where: { $0.id == updated.id }) {
                addresses[index] = updated
            }
        } catch {
            verifyError = error.localizedDescription
            showVerifyError = true
        }
    }
}

#Preview {
    NavigationStack {
        MailingAddressBookView()
    }
}
