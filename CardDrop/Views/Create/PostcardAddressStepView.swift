import SwiftUI

/// Step 1 of the physical-mail (LOB) send flow: pick a verified sender and
/// recipient address, and the card size. Presented from SendOptionsView's
/// "Mail Real Postcard" row. Only two sizes ever exist, so size selection
/// lives on this same screen rather than a separate step — payment (Phase 4)
/// comes after; `onContinue` hands back the two chosen addresses plus the
/// selected price option.
struct PostcardAddressStepView: View {
    /// Free-postcard allowance (friends & family), display only — the server
    /// applies it when the order is created. Either size is covered.
    var allowance: PostcardAllowance? = nil
    var onContinue: (_ sender: SavedMailingAddress, _ recipient: SavedMailingAddress, _ price: PostcardPriceOption) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var addresses: [SavedMailingAddress] = []
    @State private var isLoading = false
    @State private var loadError: String?

    @State private var selectedSender: SavedMailingAddress?
    @State private var selectedRecipient: SavedMailingAddress?

    @State private var showSenderPicker = false
    @State private var showRecipientPicker = false

    @State private var verifyingRole: MailingAddressType?
    @State private var verifyError: String?
    @State private var showVerifyError = false

    // Lets the user proceed past this step even though one or both addresses
    // failed verification, at their own risk — a single shared toggle (not
    // per-address), reset whenever either address selection changes so it
    // never silently carries over to an address the user hasn't seen yet.
    @State private var overrideConfirmed = false

    // Size/price — defaults to 4x6 once pricing loads (an obvious,
    // easy-to-change default beats forcing an explicit tap for a binary
    // choice; see [[project_lob_integration_progress]]).
    @State private var priceOptions: [PostcardPriceOption] = []
    @State private var selectedSize: PostcardSize = .fourBySix
    @State private var isPricingLoading = false
    @State private var pricingError: String?

    private var selectedPriceOption: PostcardPriceOption? {
        priceOptions.first { $0.size == selectedSize }
    }

    private var hasUnverifiedAddress: Bool {
        (selectedSender?.isVerified == false) || (selectedRecipient?.isVerified == false)
    }

    private var canContinue: Bool {
        guard let selectedSender, let selectedRecipient, selectedPriceOption != nil else { return false }
        let senderOK = selectedSender.isVerified || overrideConfirmed
        let recipientOK = selectedRecipient.isVerified || overrideConfirmed
        return senderOK && recipientOK
    }

    private var allowanceApplies: Bool { (allowance?.remaining ?? 0) > 0 }

    private var nextButtonTitle: String {
        guard let price = selectedPriceOption else { return "Next" }
        let sizeLabel = selectedSize == .fourBySix ? "4x6" : "6x9"
        return "Next: Mail \(sizeLabel) Card - \(allowanceApplies ? "Free" : price.formattedPrice)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    if let loadError {
                        Section {
                            Text(loadError).foregroundColor(.red).font(.subheadline)
                        }
                    }
                    Section("From Address") {
                        addressRow(
                            selected: selectedSender,
                            role: .sender,
                            placeholder: "Choose or add sender address"
                        ) { showSenderPicker = true }
                    }
                    Section("To Address") {
                        addressRow(
                            selected: selectedRecipient,
                            role: .recipient,
                            placeholder: "Choose or add recipient address"
                        ) { showRecipientPicker = true }
                    }
                    if hasUnverifiedAddress && verifyingRole == nil {
                        Section {
                            Toggle(isOn: $overrideConfirmed) {
                                HStack(spacing: 6) {
                                    cautionIcon
                                    Text("Address Unverified - send anyway?")
                                        .font(.subheadline)
                                }
                            }
                        }
                        .listSectionSpacing(.custom(20))
                    }
                    Section {
                        if let pricingError {
                            Text(pricingError).foregroundColor(.red).font(.subheadline)
                        } else if isPricingLoading && priceOptions.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            ForEach(priceOptions) { option in
                                sizeRow(option)
                            }
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Choose Size")
                            if allowanceApplies, let allowance {
                                Text("\(allowance.remaining) of \(allowance.limit) free postcards left this month")
                            }
                        }
                    }
                    .listSectionSpacing(.custom(40))
                }

                // Bottom "Next" control, matching the rest of the compose
                // workflow's step-to-step navigation (e.g. Write Card's
                // "Next: Preview and Send"), instead of a toolbar Continue.
                // Its own label reflects the chosen size + price.
                Button {
                    if let selectedSender, let selectedRecipient, let price = selectedPriceOption {
                        onContinue(selectedSender, selectedRecipient, price)
                    }
                } label: {
                    Text(nextButtonTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.brandBlue)
                        .foregroundColor(.white)
                        .cornerRadius(999)
                }
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.4)
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .navigationTitle("Mail Real Postcard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarPillItem("Cancel", placement: .cancellationAction, style: .filled) { dismiss() }
            }
            .task { await load() }
            .task { await loadPricing() }
            .sheet(isPresented: $showSenderPicker) {
                MailingAddressPickerSheet(role: .sender) { address in
                    select(address, role: .sender)
                }
            }
            .sheet(isPresented: $showRecipientPicker) {
                MailingAddressPickerSheet(role: .recipient) { address in
                    select(address, role: .recipient)
                }
            }
            .alert("Couldn't Verify Address", isPresented: $showVerifyError, presenting: verifyError) { _ in
                Button("OK") {}
            } message: { message in
                Text(message)
            }
        }
        .dynamicTypeSize(.medium ... .xxxLarge)
    }

    // LocalizedStringKey(dynamicString) is what makes a runtime DB string
    // render standard Markdown (**bold**, *italic*, ~~strike~~, links) —
    // Text(someString) alone would show the raw "**" characters. A literal
    // \n (backslash + n, two characters) is also converted to a real
    // newline first, since a plain Postgres string literal stores \n as
    // those two characters rather than an actual line break unless you use
    // E'...' escape syntax — this way a plain '...' string with \n typed in
    // still forces a line break without needing that escaping.
    private func markdownText(_ raw: String) -> Text {
        Text(LocalizedStringKey(raw.replacingOccurrences(of: "\\n", with: "\n")))
    }

    @ViewBuilder
    private func sizeRow(_ option: PostcardPriceOption) -> some View {
        let isSelected = option.size == selectedSize
        Button {
            selectedSize = option.size
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .brandBlue : .secondary)
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(option.size == .fourBySix ? "4x6 Standard Size" : "6x9 Deluxe Size")
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        Spacer()
                        Text(allowanceApplies ? "Free" : option.formattedPrice)
                            .foregroundColor(.primary)
                    }
                    if !option.productDescription.isEmpty {
                        markdownText(option.productDescription)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    if let special = option.specialDescription, !special.isEmpty {
                        markdownText(special)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.brandBlue)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func addressRow(
        selected: SavedMailingAddress?,
        role: MailingAddressType,
        placeholder: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    if let selected {
                        Text(selected.nickname?.isEmpty == false ? selected.nickname! : selected.displayName)
                            .foregroundColor(.primary)
                        if !selected.formattedAddress.isEmpty {
                            Text(selected.formattedAddress)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                        }
                    } else {
                        Text(placeholder)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if verifyingRole == role {
                    ProgressView()
                } else if let selected {
                    if selected.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                    } else {
                        cautionIcon
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    // exclamationmark.triangle.fill's .multicolor rendering isn't the
    // classic black-bordered road-sign look on this symbol — build it
    // manually: a solid yellow triangle under a black outline+exclamation.
    private var cautionIcon: some View {
        ZStack {
            Image(systemName: "triangle.fill")
                .foregroundColor(.yellow)
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.black)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            addresses = try await AddressBookService.fetch()
            // Prefill sender from the account's profile address, if one exists.
            if selectedSender == nil {
                selectedSender = addresses.first { $0.addressType == .profile }
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadPricing() async {
        isPricingLoading = true
        defer { isPricingLoading = false }
        do {
            priceOptions = try await PostcardPricingService.fetchCurrentPricing()
        } catch {
            pricingError = error.localizedDescription
        }
    }

    private func select(_ address: SavedMailingAddress, role: MailingAddressType) {
        if role == .sender {
            selectedSender = address
        } else {
            selectedRecipient = address
        }
        overrideConfirmed = false

        guard !address.isVerified else { return }

        verifyingRole = role
        Task {
            defer { verifyingRole = nil }
            do {
                let verified = try await AddressBookService.verify(id: address.id)
                if role == .sender {
                    selectedSender = verified
                } else {
                    selectedRecipient = verified
                }
            } catch {
                verifyError = error.localizedDescription
                showVerifyError = true
            }
        }
    }
}
