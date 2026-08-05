import SwiftUI

struct FamilyModeSettingSheet: View {
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $appSettings.familyMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Family Mode")
                            Text("Blocks strong language in messages")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } footer: {
                    Text("When Family Mode is off, messages with mild language will show a warning but can still be sent. Content that is sexually explicit, graphically violent, or promotes self-harm is always blocked.")
                }
            }
            .navigationTitle("Content Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .dynamicTypeSize(.medium ... .xxxLarge)
    }
}

#Preview {
    FamilyModeSettingSheet()
        .environmentObject(AppSettings())
}
