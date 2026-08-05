import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Focus fields

private enum BackField: Hashable {
    case recipientFirstName, recipientLastName
    case recipientStreet, recipientCity, recipientState, recipientZip, recipientCountry, recipientEmail, recipientPhone
    case senderFirstName, senderLastName
    case senderStreet, senderCity, senderState, senderZip, senderCountry, senderEmail, senderPhone
}

// MARK: - Address picker target

private enum PickerTarget: Identifiable {
    case sender, recipient
    var id: Self { self }
}

// MARK: - Step View

struct BackOfCardStepView: View {
    @ObservedObject var draft: PostcardDraft
    var onNext: () -> Void

    @EnvironmentObject private var addressBook: AddressBookManager
    @EnvironmentObject private var authManager: AuthManager
    @FocusState private var focus: BackField?
    @State private var pickerTarget: PickerTarget? = nil
    @State private var showSaveProfilePrompt = false

    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
            VStack(spacing: 24) {

                // Form
                VStack(alignment: .leading, spacing: 0) {

                    BackFormSection(title: "To", pickerAction: { pickerTarget = .recipient }) {
                        HStack(spacing: 8) {
                            TextField("First name", text: $draft.recipientFirstName)
                                .textFieldStyle(.roundedBorder)
                                .focused($focus, equals: .recipientFirstName)
                                .submitLabel(.next)
                                .onSubmit { focus = .recipientLastName }
                            TextField("Last name", text: $draft.recipientLastName)
                                .textFieldStyle(.roundedBorder)
                                .focused($focus, equals: .recipientLastName)
                                .submitLabel(.next)
                                .onSubmit { focus = .recipientStreet }
                        }
                        TextField("Street address", text: $draft.recipientStreet)
                            .textFieldStyle(.roundedBorder)
                            .focused($focus, equals: .recipientStreet)
                            .submitLabel(.next)
                            .onSubmit { focus = .recipientCity }
                        HStack(spacing: 8) {
                            TextField("City", text: $draft.recipientCity)
                                .textFieldStyle(.roundedBorder)
                                .focused($focus, equals: .recipientCity)
                                .submitLabel(.next)
                                .onSubmit { focus = .recipientState }
                            TextField("ST", text: $draft.recipientState)
                                .textFieldStyle(.roundedBorder)
                                .focused($focus, equals: .recipientState)
                                .frame(width: 52)
                                .submitLabel(.next)
                                .onSubmit { focus = .recipientZip }
                            TextField("ZIP", text: $draft.recipientZip)
                                .textFieldStyle(.roundedBorder)
                                .focused($focus, equals: .recipientZip)
                                .frame(width: 80)
                                .keyboardType(.numbersAndPunctuation)
                                .submitLabel(.next)
                                .onSubmit { focus = .recipientCountry }
                        }
                        TextField("Country", text: $draft.recipientCountry)
                            .textFieldStyle(.roundedBorder)
                            .focused($focus, equals: .recipientCountry)
                            .submitLabel(.next)
                            .onSubmit { focus = .recipientEmail }
                        TextField("Email (to send via email)", text: $draft.recipientEmail)
                            .textFieldStyle(.roundedBorder)
                            .focused($focus, equals: .recipientEmail)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .submitLabel(.next)
                            .onSubmit { focus = .recipientPhone }
                        TextField("Phone (to send via messages)", text: $draft.recipientPhone)
                            .textFieldStyle(.roundedBorder)
                            .focused($focus, equals: .recipientPhone)
                            .keyboardType(.phonePad)
                            .submitLabel(.next)
                            .onSubmit { focus = .senderFirstName }
                    }

                    Divider().padding(.vertical, 16)

                    BackFormSection(title: "From", pickerAction: nil) {
                        HStack(spacing: 8) {
                            TextField("First name", text: $draft.senderFirstName)
                                .textFieldStyle(.roundedBorder)
                                .focused($focus, equals: .senderFirstName)
                                .submitLabel(.next)
                                .onSubmit { focus = .senderLastName }
                            TextField("Last name", text: $draft.senderLastName)
                                .textFieldStyle(.roundedBorder)
                                .focused($focus, equals: .senderLastName)
                                .submitLabel(.next)
                                .onSubmit { focus = .senderStreet }
                        }
                        TextField("Street address", text: $draft.senderStreet)
                            .textFieldStyle(.roundedBorder)
                            .focused($focus, equals: .senderStreet)
                            .submitLabel(.next)
                            .onSubmit { focus = .senderCity }
                        HStack(spacing: 8) {
                            TextField("City", text: $draft.senderCity)
                                .textFieldStyle(.roundedBorder)
                                .focused($focus, equals: .senderCity)
                                .submitLabel(.next)
                                .onSubmit { focus = .senderState }
                            TextField("ST", text: $draft.senderState)
                                .textFieldStyle(.roundedBorder)
                                .focused($focus, equals: .senderState)
                                .frame(width: 52)
                                .submitLabel(.next)
                                .onSubmit { focus = .senderZip }
                            TextField("ZIP", text: $draft.senderZip)
                                .textFieldStyle(.roundedBorder)
                                .focused($focus, equals: .senderZip)
                                .frame(width: 80)
                                .keyboardType(.numbersAndPunctuation)
                                .submitLabel(.next)
                                .onSubmit { focus = .senderCountry }
                        }
                        TextField("Country", text: $draft.senderCountry)
                            .textFieldStyle(.roundedBorder)
                            .focused($focus, equals: .senderCountry)
                            .submitLabel(.next)
                            .onSubmit { focus = .senderEmail }
                        TextField("Email (optional)", text: $draft.senderEmail)
                            .textFieldStyle(.roundedBorder)
                            .focused($focus, equals: .senderEmail)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .submitLabel(.next)
                            .onSubmit { focus = .senderPhone }
                        TextField("Phone (optional)", text: $draft.senderPhone)
                            .textFieldStyle(.roundedBorder)
                            .focused($focus, equals: .senderPhone)
                            .keyboardType(.phonePad)
                            .submitLabel(.done)
                            .onSubmit { focus = nil }
                    }

                }
                .padding(.horizontal)

            }
        }

        } // end outer VStack
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: saveAddressesAndProceed) {
                Text("Next: Preview")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.brandBlue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(uiColor: .systemBackground))
        }
        .onAppear { prefillSenderFromProfile() }
        .confirmationDialog("Update your saved address?", isPresented: $showSaveProfilePrompt, titleVisibility: .visible) {
            Button("Yes, update") {
                authManager.saveProfile(
                    firstName: draft.senderFirstName, lastName: draft.senderLastName,
                    phone: draft.senderPhone, street: draft.senderStreet,
                    city: draft.senderCity, state: draft.senderState,
                    zip: draft.senderZip, country: draft.senderCountry
                )
                onNext()
            }
            Button("No, just this card", role: .cancel) { onNext() }
        } message: {
            Text("Do you want to update the address saved in your profile?")
        }
        .sheet(item: $pickerTarget) { target in
            AddressPickerSheet(role: target == .sender ? .sender : .recipient) { name, address, email, phone in
                let parts = parseAddress(address)
                let nameParts = name.components(separatedBy: " ").filter { !$0.isEmpty }
                let first = nameParts.first ?? ""
                let last  = nameParts.dropFirst().joined(separator: " ")
                if target == .sender {
                    draft.senderFirstName = first
                    draft.senderLastName  = last
                    draft.senderStreet    = parts.street
                    draft.senderCity      = parts.city
                    draft.senderState     = parts.state
                    draft.senderZip       = parts.zip
                    draft.senderCountry   = parts.country
                    draft.senderEmail     = email
                    draft.senderPhone     = phone
                } else {
                    draft.recipientFirstName = first
                    draft.recipientLastName  = last
                    draft.recipientStreet    = parts.street
                    draft.recipientCity      = parts.city
                    draft.recipientState     = parts.state
                    draft.recipientZip       = parts.zip
                    draft.recipientCountry   = parts.country
                    draft.recipientEmail     = email
                    draft.recipientPhone     = phone
                }
            }
            .environmentObject(addressBook)
        }
    }

    private func prefillSenderFromProfile() {
        guard draft.senderFirstName.isEmpty && draft.senderStreet.isEmpty &&
              draft.senderCity.isEmpty && draft.senderState.isEmpty &&
              draft.senderZip.isEmpty && draft.senderCountry.isEmpty else { return }
        draft.senderFirstName = authManager.firstName
        draft.senderLastName  = authManager.lastName
        draft.senderStreet    = authManager.profileStreet
        draft.senderCity      = authManager.profileCity
        draft.senderState     = authManager.profileState
        draft.senderZip       = authManager.profileZip
        draft.senderCountry   = authManager.profileCountry
        if draft.senderEmail.isEmpty, !authManager.isAnonymous,
           let email = authManager.currentUserEmail {
            draft.senderEmail = email
        }
    }

    private func saveAddressesAndProceed() {
        if !draft.recipientStreet.isEmpty {
            addressBook.saveIfNew(name: draft.recipientName, address: draft.formattedRecipientAddress,
                                  email: draft.recipientEmail, phone: draft.recipientPhone, role: .recipient)
        }

        let senderHasData = !draft.senderFirstName.isEmpty || !draft.senderStreet.isEmpty
        guard senderHasData else { onNext(); return }

        let profileEmail = authManager.currentUserEmail ?? ""
        let draftEmail   = draft.senderEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        if !draftEmail.isEmpty && !profileEmail.isEmpty && draftEmail != profileEmail {
            addressBook.saveIfNew(name: draft.senderName, address: draft.formattedSenderAddress,
                                  email: draftEmail, phone: draft.senderPhone, role: .sender)
            onNext()
            return
        }

        let profileHasNameOrAddress = !authManager.firstName.isEmpty
                                   || !authManager.profileStreet.isEmpty
                                   || !authManager.profileCity.isEmpty

        if !profileHasNameOrAddress {
            authManager.saveProfile(
                firstName: draft.senderFirstName, lastName: draft.senderLastName,
                phone: draft.senderPhone, street: draft.senderStreet,
                city: draft.senderCity, state: draft.senderState,
                zip: draft.senderZip, country: draft.senderCountry
            )
            onNext()
            return
        }

        let senderChanged = draft.senderFirstName != authManager.firstName
                         || draft.senderLastName  != authManager.lastName
                         || draft.senderStreet    != authManager.profileStreet
                         || draft.senderCity      != authManager.profileCity
                         || draft.senderState     != authManager.profileState
                         || draft.senderZip       != authManager.profileZip
                         || draft.senderCountry   != authManager.profileCountry
        if senderChanged {
            showSaveProfilePrompt = true
        } else {
            onNext()
        }
    }

    private func parseAddress(_ string: String) -> (street: String, city: String, state: String, zip: String, country: String) {
        let lines = string.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let street = lines.first ?? ""
        var city = "", state = "", zip = "", country = ""
        if lines.count >= 2 {
            let line2 = lines[1]
            if let comma = line2.range(of: ", ") {
                city = String(line2[..<comma.lowerBound])
                let rest = String(line2[comma.upperBound...])
                let parts = rest.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 2 { state = parts[0]; zip = parts[1...].joined(separator: " ") }
                else { state = rest }
            } else {
                city = line2
            }
        }
        if lines.count >= 3 { country = lines[2...].joined(separator: "\n") }
        return (street, city, state, zip, country)
    }
}

// MARK: - Form Section Helper

private struct BackFormSection<Content: View>: View {
    let title: String
    var pickerAction: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                if let action = pickerAction {
                    Spacer()
                    Button(action: action) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .foregroundColor(.accentColor)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
            content()
        }
    }
}

#Preview {
    BackOfCardStepView(draft: PostcardDraft(), onNext: {})
}
