import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var draftManager: DraftManager
    @EnvironmentObject private var addressBook: AddressBookManager
    @State private var showCreateFlow = false
    @State private var showOTPVerification = false
    @State private var showSignInGate = false

    private var recentCards: [PostcardDraftSnapshot] {
        let drafts = draftManager.drafts.filter { $0.status == .unsent }.sorted { $0.lastModified > $1.lastModified }
        let sent   = draftManager.drafts.filter { $0.status == .sent   }.sorted { $0.lastModified > $1.lastModified }
        if drafts.isEmpty { return Array(sent.prefix(3)) }
        var result = Array(drafts.prefix(1)) + Array(sent.prefix(2))
        if result.count < 3 {
            result += Array(drafts.dropFirst(1).prefix(3 - result.count))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Create button
                    Button(action: { showCreateFlow = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                            Text("Create a Postcard")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.brandBlue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    // Recent cards
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Postcards")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .padding(.horizontal)

                        if recentCards.isEmpty {
                            Text("Your recent postcards will appear here.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(recentCards) { snapshot in
                                    DraftRowView(snapshot: snapshot)
                                        .padding(.horizontal)
                                    if snapshot.id != recentCards.last?.id {
                                        Divider().padding(.leading, 96)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.top)
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    CardDropWordmark(font: .headline.bold(), dropOffset: 4)
                }
            }
            .fullScreenCover(isPresented: $showCreateFlow) {
                CreateFlowView()
            }
            .sheet(isPresented: $showOTPVerification) {
                OTPVerificationView()
                    .environmentObject(authManager)
                    .environmentObject(draftManager)
                    .environmentObject(addressBook)
            }
            .sheet(isPresented: $showSignInGate) {
                SubscribeGateView(onSuccess: { showSignInGate = false })
                    .environmentObject(authManager)
                    .environmentObject(draftManager)
                    .environmentObject(addressBook)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !authManager.isAnonymous && !authManager.isEmailVerified {
                Button(action: { showOTPVerification = true }) {
                    Text("Verify your email for unlimited sending")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.brandBlue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(uiColor: .systemBackground))
            } else if authManager.isAnonymous {
                Button(action: { showSignInGate = true }) {
                    Text("Create an account for unlimited sending")
                        .fontWeight(.semibold)
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
        }
    }
}

#Preview {
    HomeView()
}
