import SwiftUI

struct ProfileSectionView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var showEdit = false

    var body: some View {
        Section {
            Button(action: { showEdit = true }) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        if authManager.firstName.isEmpty {
                            Text("Add your name and address")
                                .foregroundColor(.secondary)
                        } else {
                            Text(authManager.firstName)
                                .foregroundColor(.primary)
                            if !authManager.profilePhone.isEmpty {
                                Text(authManager.profilePhone)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if !authManager.profileStreet.isEmpty {
                                Text(addressLine)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: "pencil")
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.primary)
        } header: {
            Text("Profile")
                .font(.system(size: 13, weight: .regular))
                .textCase(.none)
        }
        .sheet(isPresented: $showEdit) {
            EditProfileView()
                .environmentObject(authManager)
        }
    }

    private var addressLine: String {
        [authManager.profileStreet,
         authManager.profileCity,
         authManager.profileState,
         authManager.profileZip]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

// MARK: - Edit sheet

struct EditProfileView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var phone = ""
    @State private var street = ""
    @State private var city = ""
    @State private var stateField = ""
    @State private var zip = ""
    @State private var country = ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("First name", text: $firstName)
                        .autocapitalization(.words)
                } header: {
                    Text("Name")
                        .font(.system(size: 13, weight: .regular))
                        .textCase(.none)
                }

                Section {
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Street address", text: $street)
                        .autocapitalization(.words)
                    HStack(spacing: 8) {
                        TextField("City", text: $city)
                            .autocapitalization(.words)
                        TextField("ST", text: $stateField)
                            .frame(width: 52)
                            .autocapitalization(.allCharacters)
                        TextField("ZIP", text: $zip)
                            .frame(width: 80)
                            .keyboardType(.numbersAndPunctuation)
                    }
                    TextField("Country", text: $country)
                        .autocapitalization(.words)
                } header: {
                    Text("Return Address & Phone")
                        .font(.system(size: 13, weight: .regular))
                        .textCase(.none)
                } footer: {
                    Text("Auto-fills as your return address on every card. Not shared with anyone.")
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarPillItem("Cancel", placement: .cancellationAction) { dismiss() }
                saveToolbarItem
            }
            .onAppear {
                firstName  = authManager.firstName
                phone      = authManager.profilePhone
                street     = authManager.profileStreet
                city       = authManager.profileCity
                stateField = authManager.profileState
                zip        = authManager.profileZip
                country    = authManager.profileCountry
            }
        }
    }

    // Custom "Save"/"Saved ✓" — not a plain ToolbarPillButton since its color
    // switches to green once saved, so it needs the same iOS 26 shared-glass
    // opt-out applied by hand instead of via toolbarPillItem.
    @ToolbarContentBuilder
    private var saveToolbarItem: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .confirmationAction) { saveButtonLabel }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .confirmationAction) { saveButtonLabel }
        }
    }

    private var saveButtonLabel: some View {
        Button {
            authManager.saveProfile(
                firstName: firstName, phone: phone,
                street: street, city: city,
                state: stateField, zip: zip, country: country
            )
            saved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { dismiss() }
        } label: {
            Text(saved ? "Saved ✓" : "Save")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(saved ? .green : .brandBlue)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
