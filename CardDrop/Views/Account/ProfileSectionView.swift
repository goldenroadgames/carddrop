import SwiftUI

struct ProfileSectionView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var showEdit = false

    var body: some View {
        Section("Profile") {
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
                Section("Name") {
                    TextField("First name", text: $firstName)
                        .autocapitalization(.words)
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
                } footer: {
                    Text("Auto-fills as your return address on every card. Not shared with anyone.")
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saved ? "Saved ✓" : "Save") {
                        authManager.saveProfile(
                            firstName: firstName, phone: phone,
                            street: street, city: city,
                            state: stateField, zip: zip, country: country
                        )
                        saved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { dismiss() }
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(saved ? .green : .accentColor)
                }
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
}
