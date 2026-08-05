import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var draftManager: DraftManager
    @EnvironmentObject var addressBook: AddressBookManager

    @State private var selectedTab: AppTab = .postcards
    @State private var showSignInGate = false
    @State private var showOTPGate = false
    @State private var profileIsDirty = false
    @State private var showUnsavedAlert = false
    @State private var intendedTab: AppTab = .postcards

    enum AppTab { case postcards, profile }

    var body: some View {
        Group {
            switch selectedTab {
            case .postcards:
                PostcardsView()
            case .profile:
                ProfileView(isDirty: $profileIsDirty)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Picker("", selection: pickerBinding) {
                    Text("Postcards").tag(AppTab.postcards)
                    Text("Profile").tag(AppTab.profile)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(uiColor: .systemBackground))
            }
        }
        .alert("Unsaved Changes", isPresented: $showUnsavedAlert) {
            Button("Discard Changes", role: .destructive) {
                profileIsDirty = false
                switchTo(intendedTab)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your profile changes haven't been saved.")
        }
        .sheet(isPresented: $showSignInGate) {
            SubscribeGateView(onSuccess: {
                showSignInGate = false
                selectedTab = .profile
            })
            .environmentObject(authManager)
            .environmentObject(draftManager)
            .environmentObject(addressBook)
        }
        .sheet(isPresented: $showOTPGate) {
            OTPVerificationView()
                .environmentObject(authManager)
                .environmentObject(draftManager)
                .environmentObject(addressBook)
        }
    }

    private var pickerBinding: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                guard newTab != selectedTab else { return }
                if selectedTab == .profile && profileIsDirty {
                    intendedTab = newTab
                    showUnsavedAlert = true
                } else {
                    switchTo(newTab)
                }
            }
        )
    }

    private func switchTo(_ tab: AppTab) {
        if tab == .profile {
            if authManager.isAnonymous {
                showSignInGate = true
                return
            }
            if !authManager.isEmailVerified {
                showOTPGate = true
            }
        }
        selectedTab = tab
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthManager())
}
