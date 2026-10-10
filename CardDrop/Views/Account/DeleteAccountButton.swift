import SwiftUI
import Supabase

/// "Delete Account" with its confirmation, Apple re-authorization (Apple
/// accounts only, so the server can revoke the grant), progress and failure
/// handling. On success the local data is wiped and the user is signed out.
/// Used on Profile and on the suspended-account screen.
struct DeleteAccountButton: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var draftManager: DraftManager
    @EnvironmentObject var addressBook: AddressBookManager

    @State private var showConfirm = false
    @State private var isDeleting = false
    @State private var showFailed = false

    var body: some View {
        Button(role: .destructive) {
            showConfirm = true
        } label: {
            Text(isDeleting ? "Deleting…" : "Delete Account")
        }
        .disabled(isDeleting)
        .confirmationDialog("Delete Account?", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { Task { await deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, your cards and their shared links, and your saved addresses. Cannot be undone.")
        }
        .alert("Couldn't Delete Account", isPresented: $showFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and try again. Your account has not been fully deleted.")
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }

        var appleCode: String? = nil
        if authManager.isAppleAccount {
            appleCode = await authManager.requestAppleAuthorizationCode()
            if appleCode == nil {
                // Cancelled or failed at the Apple prompt: don't delete.
                showFailed = true
                return
            }
        }

        guard await AccountDeleteService.delete(appleAuthorizationCode: appleCode) else {
            showFailed = true
            return
        }

        draftManager.clearAllData()
        addressBook.clearAllData()
        // The login no longer exists server-side, so clear the local session
        // without asking the server to revoke it.
        try? await supabase.auth.signOut(scope: .local)
    }
}
