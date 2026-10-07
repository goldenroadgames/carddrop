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
    @State private var showInspire = false

    // .inspire is never actually selected — it's a link segment that opens
    // the Inspire gallery as a sheet (see pickerBinding).
    enum AppTab { case inspire, postcards, profile }

    var body: some View {
        Group {
            switch selectedTab {
            case .postcards, .inspire:
                PostcardsView()
            case .profile:
                ProfileView(isDirty: $profileIsDirty)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Picker("", selection: pickerBinding) {
                    Text("Inspired").tag(AppTab.inspire)
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
        .sheet(isPresented: $showInspire) {
            InspireGalleryView()
                .presentationBackground(Color(.systemBackground))
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
                if newTab == .inspire {
                    // Link, not a tab: open the gallery over whatever page
                    // is showing; selection stays where it was. Nothing is
                    // left behind, so no unsaved-changes prompt is needed
                    // even over a dirty Profile.
                    showInspire = true
                    return
                }
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
