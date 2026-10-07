import SwiftUI

// Add/edit sheet for a single server-side saved mailing address
// (see AddressBookService/MailingAddressBookView). Saving immediately
// attempts verification and shows the result inline.
struct MailingAddressFormView: View {
    let existing: SavedMailingAddress?
    /// Type assigned to a brand-new address (ignored when editing — existing
    /// keeps its own type). Callers presenting this from a type-specific
    /// picker (sender/recipient) pass that type; the standalone Profile
    /// "Mailing Addresses" screen leaves it at the default.
    var defaultType: MailingAddressType = .recipient
    /// Whether a default sender (address-book .profile row) already exists.
    /// When false, the default-sender toggle starts on.
    var hasDefaultSender: Bool = true
    var onSaved: (SavedMailingAddress) async -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager

    @State private var nickname = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var street = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zip = ""
    @State private var country = "US"
    @State private var email = ""
    @State private var phone = ""

    @State private var isSaving = false
    @State private var verifyStatus: VerifyStatus = .notAttempted
    @State private var errorMessage: String?
    @State private var hasSaved = false
    @State private var makeDefaultSender = false
    @State private var makeProfileAddress = false

    /// Only the sender picker's "Add New Address" offers this — a one-time
    /// override sender shouldn't silently become the account default, so
    /// this toggle is the explicit opt-in (see project_lob_integration_progress).
    private var showsDefaultSenderToggle: Bool { existing == nil && defaultType == .sender }

    private enum VerifyStatus {
        case notAttempted, verifying, verified, failed(String)
    }

    private var canSave: Bool {
        !street.trimmingCharacters(in: .whitespaces).isEmpty &&
        !city.trimmingCharacters(in: .whitespaces).isEmpty &&
        !state.trimmingCharacters(in: .whitespaces).isEmpty &&
        !zip.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Nickname (e.g. \"Mom\")", text: $nickname)
                    TextField("First name", text: $firstName).autocapitalization(.words)
                    TextField("Last name", text: $lastName).autocapitalization(.words)
                }
                Section("Mailing Address") {
                    TextField("Street address", text: $street).autocapitalization(.words)
                    TextField("City", text: $city).autocapitalization(.words)
                    HStack(spacing: 8) {
                        TextField("ST", text: $state)
                            .frame(width: 52)
                            .autocapitalization(.allCharacters)
                        TextField("ZIP", text: $zip)
                            .keyboardType(.numbersAndPunctuation)
                    }
                    TextField("Country", text: $country).autocapitalization(.words)
                }
                Section("Contact (optional)") {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                }
                if showsDefaultSenderToggle {
                    Section {
                        Toggle("Save as my default sender address", isOn: $makeDefaultSender)
                        Toggle("Save as my profile address", isOn: $makeProfileAddress)
                    } footer: {
                        Text("Off just uses this address for this postcard. Default sender replaces your default return address going forward; profile address replaces the address on your Profile tab. Either starts on if that spot is empty.")
                    }
                }
                verifySection
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
            }
            .navigationTitle(existing == nil ? "Add Address" : "Edit Address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarPillItem(hasSaved ? "Close" : "Cancel", placement: .cancellationAction, style: .filled) { dismiss() }
                if !hasSaved {
                    toolbarPillItem("Save", placement: .confirmationAction, style: .filled,
                                    isDisabled: !canSave || isSaving) { Task { await save() } }
                }
            }
            .onAppear(perform: loadExisting)
        }
        .dynamicTypeSize(.medium ... .xxxLarge)
    }

    @ViewBuilder
    private var verifySection: some View {
        switch verifyStatus {
        case .notAttempted:
            EmptyView()
        case .verifying:
            HStack { ProgressView(); Text("Verifying…") }
        case .verified:
            Label("Verified deliverable", systemImage: "checkmark.seal.fill")
                .foregroundColor(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        }
    }

    private func loadExisting() {
        if showsDefaultSenderToggle {
            makeDefaultSender = !hasDefaultSender
            makeProfileAddress = authManager.profileStreet.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard let existing else { return }
        nickname = existing.nickname ?? ""
        firstName = existing.firstName ?? ""
        lastName = existing.lastName ?? ""
        street = existing.street ?? ""
        city = existing.city ?? ""
        state = existing.state ?? ""
        zip = existing.zip ?? ""
        country = existing.country ?? "US"
        email = existing.email ?? ""
        phone = existing.phone ?? ""
        if existing.isVerified { verifyStatus = .verified }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let record = SavedMailingAddress(
            id: existing?.id ?? UUID(),
            nickname: nickname.isEmpty ? nil : nickname,
            firstName: firstName.isEmpty ? nil : firstName,
            lastName: lastName.isEmpty ? nil : lastName,
            street: street,
            city: city,
            state: state,
            zip: zip,
            country: country.isEmpty ? "US" : country,
            email: email.isEmpty ? nil : email,
            phone: phone.isEmpty ? nil : phone,
            addressType: existing?.addressType ?? (showsDefaultSenderToggle && makeDefaultSender ? .profile : defaultType),
            isVerified: existing?.isVerified ?? false,
            verifiedAt: existing?.verifiedAt,
            lobVerificationID: existing?.lobVerificationID,
            lastUsedAt: existing?.lastUsedAt ?? Date()
        )

        do {
            var saved = try await AddressBookService.save(record, existing: existing)
            hasSaved = true
            if showsDefaultSenderToggle && makeProfileAddress {
                authManager.saveProfileAddress(firstName: firstName, lastName: lastName, phone: phone,
                                               street: street, city: city, state: state, zip: zip,
                                               country: country.isEmpty ? "US" : country)
            }
            await onSaved(saved)

            if saved.isVerified {
                verifyStatus = .verified
            } else {
                verifyStatus = .verifying
                do {
                    saved = try await AddressBookService.verify(id: saved.id)
                    verifyStatus = .verified
                    await onSaved(saved)
                } catch {
                    verifyStatus = .failed(error.localizedDescription)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    MailingAddressFormView(existing: nil, onSaved: { _ in })
        .environmentObject(AuthManager())
}
