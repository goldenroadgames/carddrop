import SwiftUI

/// Email text field with a dropdown of known on-device accounts.
/// Typing filters the list; tapping a suggestion fills the field and closes the dropdown.
/// Pass onSelect to be notified when the user picks a suggestion (vs. typing manually).
struct AutocompleteEmailField: View {
    @Binding var text: String
    let suggestions: [String]
    var onSelect: ((String) -> Void)? = nil

    @FocusState private var isFocused: Bool

    private var visible: [String] {
        guard !suggestions.isEmpty else { return [] }
        if text.isEmpty { return suggestions }
        return suggestions.filter { $0.localizedCaseInsensitiveContains(text) }
    }

    private var showDropdown: Bool { isFocused && !visible.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Email", text: $text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .focused($isFocused)

            if showDropdown {
                VStack(spacing: 0) {
                    ForEach(visible, id: \.self) { suggestion in
                        Button {
                            text = suggestion
                            isFocused = false
                            onSelect?(suggestion)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "person.circle.fill")
                                    .foregroundColor(.accentColor)
                                Text(suggestion)
                                    .foregroundColor(.primary)
                                    .font(.subheadline)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                        if suggestion != visible.last {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showDropdown)
    }
}
