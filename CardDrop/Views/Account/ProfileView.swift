import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var draftManager: DraftManager
    @EnvironmentObject var addressBook: AddressBookManager

    @Binding var isDirty: Bool

    @State private var showSignOutConfirmation = false
    @State private var showStorageUpgrade = false
    @State private var showOTPVerification = false
    @State private var showSignInGate = false

    @State private var senderNickname = ""
    @State private var nicknameSyncTask: Task<Void, Never>?

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var profilePhone = ""
    @State private var street = ""
    @State private var city = ""
    @State private var stateField = ""
    @State private var zip = ""
    @State private var country = ""

    private var profileIsDirty: Bool {
        firstName    != authManager.firstName    ||
        lastName     != authManager.lastName     ||
        street       != authManager.profileStreet ||
        city         != authManager.profileCity  ||
        stateField   != authManager.profileState ||
        zip          != authManager.profileZip   ||
        country      != authManager.profileCountry
    }

    var body: some View {
        NavigationStack {
            List {
                if !authManager.isAnonymous {
                    emailSection
                    nicknameSection
                    profileSection
                    if authManager.isEmailVerified {
                        storageSection
                    }
                }

                Section {
                    Text("Notifications")
                    Text("Privacy")
                } header: {
                    HStack {
                        Text("Settings")
                            .font(.system(size: 13, weight: .regular))
                        Spacer()
                        Button("Sign Out") {
                            showSignOutConfirmation = true
                        }
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.red)
                    }
                    .textCase(.none)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                loadProfile()
                if !authManager.isAnonymous && !authManager.isEmailVerified {
                    Task { await authManager.refreshSessionAsync() }
                }
                Task {
                    if let saved = await UserService.fetchSenderNickname() {
                        senderNickname = saved
                    }
                }
            }
            .onChange(of: profileIsDirty) { isDirty = profileIsDirty }
            .confirmationDialog("Sign Out", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { authManager.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll be signed out. Your drafts and addresses will be here when you sign back in.")
            }
            .sheet(isPresented: $showOTPVerification) {
                OTPVerificationView()
                    .environmentObject(authManager)
                    .environmentObject(draftManager)
                    .environmentObject(addressBook)
            }
            .sheet(isPresented: $showStorageUpgrade) {
                StorageUpgradeView {
                    authManager.setTierUnlimited()
                }
            }
        }
        .sheet(isPresented: $showSignInGate) {
            SubscribeGateView(onSuccess: { showSignInGate = false })
                .environmentObject(authManager)
                .environmentObject(draftManager)
                .environmentObject(addressBook)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if authManager.isAnonymous {
                Button(action: { showSignInGate = true }) {
                    Text("Create an account for unlimited sending")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.brandBlue)
                        .foregroundColor(.white)
                        .cornerRadius(999)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(uiColor: .systemBackground))
            }
        }
    }

    // MARK: - Profile

    private func loadProfile() {
        firstName    = authManager.firstName
        lastName     = authManager.lastName
        profilePhone = authManager.profilePhone
        street       = authManager.profileStreet
        city         = authManager.profileCity
        stateField   = authManager.profileState
        zip          = authManager.profileZip
        country      = authManager.profileCountry
    }

    private func saveProfile() {
        authManager.saveProfile(
            firstName: firstName, lastName: lastName,
            phone: profilePhone, street: street,
            city: city, state: stateField,
            zip: zip, country: country
        )
        isDirty = false
    }

    @ViewBuilder
    private var nicknameSection: some View {
        Section {
            TextField("e.g. Pookie", text: $senderNickname)
                .onChange(of: senderNickname) { _, newValue in
                    nicknameSyncTask?.cancel()
                    nicknameSyncTask = Task {
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        guard !Task.isCancelled else { return }
                        await UserService.updateSenderNickname(newValue)
                    }
                }
        } header: {
            Text("Nickname")
                .font(.system(size: 13, weight: .regular))
                .textCase(.none)
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        Section {
            TextField("First name", text: $firstName).autocapitalization(.words)
            TextField("Last name", text: $lastName).autocapitalization(.words)
            TextField("Street address", text: $street).autocapitalization(.words)
            HStack(spacing: 8) {
                TextField("City", text: $city).autocapitalization(.words)
                TextField("ST", text: $stateField)
                    .frame(width: 52)
                    .autocapitalization(.allCharacters)
                TextField("ZIP", text: $zip)
                    .frame(width: 80)
                    .keyboardType(.numbersAndPunctuation)
            }
            TextField("Country", text: $country).autocapitalization(.words)
            if profileIsDirty {
                Button("Save Profile", action: saveProfile)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
        } header: {
            Text("Profile")
                .font(.system(size: 13, weight: .regular))
                .textCase(.none)
        }
    }

    // MARK: - Email section

    @ViewBuilder
    private var emailSection: some View {
        Section {
            HStack {
                Text(authManager.currentUserEmail ?? "—")
                    .foregroundColor(.primary)
                Spacer()
                if authManager.isEmailVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                } else {
                    Button(action: { showOTPVerification = true }) {
                        Text("Verify for unlimited sending")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.brandBlue)
                            .foregroundColor(.white)
                            .cornerRadius(999)
                    }
                }
            }
        } header: {
            Text("Email")
                .font(.system(size: 13, weight: .regular))
                .textCase(.none)
        }
    }

    // MARK: - Storage section

    @ViewBuilder
    private var storageSection: some View {
        Section {
            if authManager.hasPermanentStorage {
                HStack {
                    Image(systemName: "archivebox.fill")
                        .foregroundColor(.purple)
                    Text("Permanent Storage")
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Free tier — cards expire after 30 days")
                        .font(.subheadline)
                    Text("Upgrade once to keep your cards live indefinitely.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)

                Button(action: { showStorageUpgrade = true }) {
                    HStack {
                        Image(systemName: "archivebox.fill")
                            .foregroundColor(.purple)
                        Text("Unlock Permanent Storage — $9.99")
                            .font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.primary)
            }
        } header: {
            Text("Card Storage")
                .font(.system(size: 13, weight: .regular))
                .textCase(.none)
        }
    }
}

#Preview {
    ProfileView(isDirty: .constant(false))
        .environmentObject(AuthManager())
        .environmentObject(AppSettings())
        .environmentObject(DraftManager())
        .environmentObject(AddressBookManager())
}
