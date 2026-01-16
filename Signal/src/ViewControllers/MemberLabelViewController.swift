//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI
import SwiftUI

class MemberLabelViewController: OWSViewController {
    override init() {
        super.init()

        view.backgroundColor = UIColor.Signal.groupedBackground
        navigationItem.title = OWSLocalizedString("MEMBER_LABEL_VIEW_TITLE", comment: "Title for a view where users can edit and preview their member label.")

        // TODO: fade if text field empty
        navigationItem.rightBarButtonItem = .init(barButtonSystemItem: .done, target: self, action: #selector(didTapDone))
        navigationItem.leftBarButtonItem = .init(barButtonSystemItem: .cancel, target: self, action: #selector(didTapCancel))
        navigationItem.rightBarButtonItem?.tintColor = UIColor.Signal.ultramarine
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        createViews()
    }

    private func createViews() {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 20

        let subtitleLabel = UILabel()
        subtitleLabel.text = OWSLocalizedString(
            "MEMBER_LABEL_VIEW_SUBTITLE",
            comment: "Subtitle for a view where users can edit and preview their member label.",
        )
        subtitleLabel.numberOfLines = 0
        subtitleLabel.font = .dynamicTypeCaption1Clamped
        subtitleLabel.textColor = UIColor.Signal.secondaryLabel
        subtitleLabel.textAlignment = .center

        stackView.addArrangedSubview(subtitleLabel)

        let textFieldStack = UIStackView()
        textFieldStack.layer.cornerRadius = 27
        textFieldStack.backgroundColor = UIColor.Signal.tertiaryBackground
        textFieldStack.axis = .horizontal
        textFieldStack.alignment = .center
        textFieldStack.distribution = .fill
        textFieldStack.spacing = 8
        textFieldStack.isLayoutMarginsRelativeArrangement = true
        textFieldStack.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        let addEmojiButton = UIButton(type: .system)
        addEmojiButton.setImage(UIImage(named: "emoji-plus"), for: .normal)
        addEmojiButton.tintColor = UIColor.Signal.secondaryLabel
        addEmojiButton.setContentHuggingPriority(.required, for: .horizontal)
        addEmojiButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textField = UITextField()
        textField.placeholder = OWSLocalizedString(
            "MEMBER_LABEL_VIEW_PLACEHOLDER_TEXT",
            comment: "Placeholder text in text field where user can edit their member label.",
        )
        textField.font = .dynamicTypeBodyClamped

        textFieldStack.addArrangedSubview(addEmojiButton)
        textFieldStack.addArrangedSubview(textField)
        stackView.addArrangedSubview(textFieldStack)
        stackView.setCustomSpacing(34, after: textFieldStack)

        textFieldStack.translatesAutoresizingMaskIntoConstraints = false
        textFieldStack.heightAnchor.constraint(equalToConstant: 52).isActive = true

        guard
            let mockConversationItem = buildMockConversationItem(),
            let previewContainer = messageBubblePreviewContainer(renderItem: mockConversationItem)
        else {
            return
        }

        stackView.addArrangedSubview(previewContainer)

        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
        ])

    }

    private func buildMockConversationItem() -> CVRenderItem? {
        let db = DependenciesBridge.shared.db
        let attachmentContentValidator = DependenciesBridge.shared.attachmentContentValidator
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        let messageBody = db.write { tx in
            attachmentContentValidator.truncatedMessageBodyForInlining(
                MessageBody(text: OWSLocalizedString(
                    "MEMBER_LABEL_VIEW_MESSAGE_PREVIEW_TEXT",
                    comment: "Text shown in the preview message bubble when a user is editing their member label.",
                ), ranges: .empty),
                tx: tx,
            )
        }

        guard
            let localAci = db.read(block: { tx in
                tsAccountManager.localIdentifiers(tx: tx)?.aci
            }),
            let secretParams = try? GroupSecretParams.generate()
        else {
            return nil
        }

        var groupModelBuilder = TSGroupModelBuilder(secretParams: secretParams)
        var groupMembershipBuilder = groupModelBuilder.groupMembership.asBuilder
        groupMembershipBuilder.setMemberLabel(label: "test123", aci: localAci)
        groupModelBuilder.groupMembership = groupMembershipBuilder.build()

        guard let groupModel = try? groupModelBuilder.buildAsV2() else {
            return nil
        }

        let mockGroupThread = MockGroupThread(groupModel: groupModel)
        let mockMessage = MockIncomingMessage(messageBody: messageBody, thread: mockGroupThread, authorAci: localAci)

        let renderItem = db.read { tx in
            let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: mockGroupThread, ignoreMissing: true, transaction: tx)

            let conversationStyle = ConversationStyle(
                type: .`default`,
                thread: mockGroupThread,
                viewWidth: view.width - 44, // stack view padding
                hasWallpaper: false,
                isWallpaperPhoto: false,
                chatColor: PaletteChatColor.ultramarine.colorSetting,
            )

            return CVLoader.buildStandaloneRenderItem(
                interaction: mockMessage,
                thread: mockGroupThread,
                threadAssociatedData: threadAssociatedData,
                conversationStyle: conversationStyle,
                spoilerState: SpoilerRenderState(),
                transaction: tx,
            )
        }
        return renderItem
    }

    func messageBubblePreviewContainer(renderItem: CVRenderItem) -> UIView? {

        let previewTitle = UILabel()
        previewTitle.text = OWSLocalizedString(
            "MEMBER_LABEL_PREVIEW_HEADING",
            comment: "Heading shown above the preview of a message bubble with the edited member label.",
        )
        previewTitle.font = .dynamicTypeBodyClamped.semibold()

        let cellView = CVCellView()
        cellView.configure(renderItem: renderItem, componentDelegate: self)
        cellView.isCellVisible = true
        cellView.autoSetDimension(.height, toSize: renderItem.cellMeasurement.cellSize.height)
        cellView.autoSetDimension(.width, toSize: renderItem.cellMeasurement.cellSize.width)

        let cellContainer = UIView()
        cellContainer.layer.cornerRadius = 27
        cellContainer.layer.masksToBounds = true
        cellContainer.backgroundColor = UIColor.Signal.tertiaryBackground

        cellContainer.addSubview(cellView)
        cellView.autoPinEdge(toSuperviewEdge: .top, withInset: 20)
        cellView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 20)

        let previewContainer = UIStackView()
        previewContainer.axis = .vertical
        previewContainer.spacing = 8
        previewContainer.addArrangedSubview(previewTitle)
        previewContainer.addArrangedSubview(cellContainer)

        return previewContainer
    }

    @objc
    private func didTapDone() {
        dismiss(animated: true)
    }

    @objc
    private func didTapCancel() {
        dismiss(animated: true)
    }
}

// MARK: -

extension MemberLabelViewController: CVComponentDelegate {
    var spoilerState: SignalUI.SpoilerRenderState {
        return SpoilerRenderState()
    }

    func enqueueReload() {}

    func enqueueReloadWithoutCaches() {}

    func didTapBodyTextItem(_ item: CVTextLabel.Item) {}

    func didLongPressBodyTextItem(_ item: CVTextLabel.Item) {}

    func didTapSystemMessageItem(_ item: CVTextLabel.Item) {}

    func didDoubleTapTextViewItem(_ itemViewModel: CVItemViewModelImpl) {}

    func didLongPressTextViewItem(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool,
    ) {}

    func didLongPressMediaViewItem(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool,
    ) {}

    func didLongPressQuote(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool,
    ) {}

    func didLongPressSystemMessage(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
    ) {}

    func didLongPressSticker(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool,
    ) {}

    func didLongPressPaymentMessage(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool,
    ) {}

    func didLongPressPoll(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool,
    ) {}

    func didTapPayment(_ payment: PaymentsHistoryItem) {}

    func didChangeLongPress(_ itemViewModel: CVItemViewModelImpl) {}

    func didEndLongPress(_ itemViewModel: CVItemViewModelImpl) {}

    func didCancelLongPress(_ itemViewModel: CVItemViewModelImpl) {}

    // MARK: -

    func willBecomeVisibleWithFailedOrPendingDownloads(_ message: TSMessage) {}

    func didTapFailedOrPendingDownloads(_ message: TSMessage) {}

    func didCancelDownload(_ message: TSMessage, attachmentId: Attachment.IDType) {}

    // MARK: -

    func didTapReplyToItem(_ itemViewModel: CVItemViewModelImpl) {}

    func didTapSenderAvatar(_ interaction: TSInteraction) {}

    func shouldAllowReplyForItem(_ itemViewModel: CVItemViewModelImpl) -> Bool { false }

    func didTapReactions(
        reactionState: InteractionReactionState,
        message: TSMessage,
    ) {}

    func didTapTruncatedTextMessage(_ itemViewModel: CVItemViewModelImpl) {}

    func didTapShowEditHistory(_ itemViewModel: CVItemViewModelImpl) {}

    var hasPendingMessageRequest: Bool { false }

    func didTapUndownloadableMedia() {}

    func didTapUndownloadableGenericFile() {}

    func didTapUndownloadableOversizeText() {}

    func didTapUndownloadableAudio() {}

    func didTapUndownloadableSticker() {}

    func didTapBrokenVideo() {}

    func didTapBodyMedia(
        itemViewModel: CVItemViewModelImpl,
        attachmentStream: ReferencedAttachmentStream,
        imageView: UIView,
    ) {}

    func didTapGenericAttachment(
        _ attachment: CVComponentGenericAttachment,
    ) -> CVAttachmentTapAction { .default }

    func didTapQuotedReply(_ quotedReply: QuotedReplyModel) {}

    func didTapLinkPreview(_ linkPreview: OWSLinkPreview) {}

    func didTapContactShare(_ contactShare: ContactShareViewModel) {}

    func didTapSendMessage(to phoneNumbers: [String]) {}

    func didTapSendInvite(toContactShare contactShare: ContactShareViewModel) {}

    func didTapAddToContacts(contactShare: ContactShareViewModel) {}

    func didTapStickerPack(_ stickerPackInfo: StickerPackInfo) {}

    func didTapGroupInviteLink(url: URL) {}

    func didTapProxyLink(url: URL) {}

    func didTapShowMessageDetail(_ itemViewModel: CVItemViewModelImpl) {}

    func willWrapGift(_ messageUniqueId: String) -> Bool { false }

    func willShakeGift(_ messageUniqueId: String) -> Bool { false }

    func willUnwrapGift(_ itemViewModel: CVItemViewModelImpl) {}

    func didTapGiftBadge(
        _ itemViewModel: CVItemViewModelImpl,
        profileBadge: ProfileBadge,
        isExpired: Bool,
        isRedeemed: Bool,
    ) {}

    func prepareMessageDetailForInteractivePresentation(_ itemViewModel: CVItemViewModelImpl) {}

    func beginCellAnimation(maximumDuration: TimeInterval) -> EndCellAnimation {
        return {}
    }

    var wallpaperBlurProvider: WallpaperBlurProvider? { nil }

    var selectionState: CVSelectionState { CVSelectionState() }

    func didTapPreviouslyVerifiedIdentityChange(_ address: SignalServiceAddress) {}

    func didTapUnverifiedIdentityChange(_ address: SignalServiceAddress) {}

    func didTapCorruptedMessage(_ message: TSErrorMessage) {}

    func didTapSessionRefreshMessage(_ message: TSErrorMessage) {}

    func didTapResendGroupUpdateForErrorMessage(_ errorMessage: TSErrorMessage) {}

    func didTapShowFingerprint(_ address: SignalServiceAddress) {}

    func didTapIndividualCall(_ call: TSCall) {}

    func didTapLearnMoreMissedCallFromBlockedContact(_ call: TSCall) {}

    func didTapGroupCall() {}

    func didTapPendingOutgoingMessage(_ message: TSOutgoingMessage) {}

    func didTapFailedOutgoingMessage(_ message: TSOutgoingMessage) {}

    func didTapGroupMigrationLearnMore() {}

    func didTapGroupInviteLinkPromotion(groupModel: TSGroupModel) {}

    func didTapViewGroupDescription(newGroupDescription: String) {}

    func didTapNameEducation(type: SafetyTipsType) {}

    func didTapShowConversationSettings() {}

    func didTapShowConversationSettingsAndShowMemberRequests() {}

    func didTapBlockRequest(
        groupModel: TSGroupModelV2,
        requesterName: String,
        requesterAci: Aci,
    ) {}

    func didTapShowUpgradeAppUI() {}

    func didTapUpdateSystemContact(
        _ address: SignalServiceAddress,
        newNameComponents: PersonNameComponents,
    ) {}

    func didTapPhoneNumberChange(aci: Aci, phoneNumberOld: String, phoneNumberNew: String) {}

    func didTapViewOnceAttachment(_ interaction: TSInteraction) {}

    func didTapViewOnceExpired(_ interaction: TSInteraction) {}

    func didTapContactName(thread: TSContactThread) {}

    func didTapUnknownThreadWarningGroup() {}
    func didTapUnknownThreadWarningContact() {}
    func didTapDeliveryIssueWarning(_ message: TSErrorMessage) {}

    func didTapActivatePayments() {}
    func didTapSendPayment() {}

    func didTapThreadMergeLearnMore(phoneNumber: String) {}

    func didTapReportSpamLearnMore() {}

    func didTapMessageRequestAcceptedOptions() {}

    func didTapJoinCallLinkCall(callLink: CallLink) {}

    func didTapViewVotes(poll: OWSPoll) {}

    func didTapViewPoll(pollInteractionUniqueId: String) {}

    func didTapVoteOnPoll(poll: OWSPoll, optionIndex: UInt32, isUnvote: Bool) {}

    func didTapViewPinnedMessage(pinnedMessageUniqueId: String) {}
}
