//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

@objc
public class OutgoingMessagePreparer: NSObject {

    public let message: TSOutgoingMessage
    private let unsavedAttachmentInfos: [OutgoingAttachmentInfo]
    private var didCompletePrep = false
    public private(set) var savedAttachmentIds: [String]?

    public var unpreparedMessage: TSOutgoingMessage {
        assert(!didCompletePrep)
        if let message = message as? OutgoingEditMessage {
            return message.editedMessage
        } else {
            return message
        }
    }

    public convenience init(_ message: TSOutgoingMessage) {
        self.init(message, unsavedAttachmentInfos: [])
    }

    public init(_ message: TSOutgoingMessage, unsavedAttachmentInfos: [OutgoingAttachmentInfo]) {
        self.message = message
        self.unsavedAttachmentInfos = unsavedAttachmentInfos
    }

    public func insertMessage(
        linkPreviewDraft: OWSLinkPreviewDraft? = nil,
        transaction: SDSAnyWriteTransaction
    ) {
        let messageRowId: Int64
        if let message = message as? OutgoingEditMessage {
            // Write changes and insert new edit revisions/records
            guard let thread = message.thread(tx: transaction) else {
                owsFailDebug("Outgoing edit message missing thread.")
                return
            }
            DependenciesBridge.shared.editManager.insertOutgoingEditRevisions(
                for: message,
                thread: thread,
                tx: transaction.asV2Write
            )
            guard let id = message.sqliteRowId else {
                // We failed to insert!
                return
            }
            messageRowId = id
        } else {
            unpreparedMessage.anyInsert(transaction: transaction)
            messageRowId = message.sqliteRowId!
        }

        if let linkPreviewDraft = linkPreviewDraft {
            do {
                let linkPreview = try OWSLinkPreview.buildValidatedLinkPreview(
                    fromInfo: linkPreviewDraft,
                    messageRowId: messageRowId,
                    transaction: transaction
                )
                unpreparedMessage.update(with: linkPreview, transaction: transaction)
            } catch {
                Logger.error("error: \(error)")
            }
        }
    }

    public func prepareMessage(transaction: SDSAnyWriteTransaction) throws -> TSOutgoingMessage {
        assert(!didCompletePrep)

        if unsavedAttachmentInfos.count > 0 {
            // Eventually we'll pad all outgoing attachments, but currently just stickers.
            // Currently this method is only used to process "body" attachments, which
            // cannot be sent along with stickers.
            owsAssertDebug(unpreparedMessage.messageSticker == nil)

            try DependenciesBridge.shared.tsResourceManager.createBodyAttachmentStreams(
                consumingDataSourcesOf: unsavedAttachmentInfos,
                message: unpreparedMessage,
                tx: transaction.asV2Write
            )
        }

        self.savedAttachmentIds = Self.prepareAttachments(message: unpreparedMessage, tx: transaction)

        // When we start a message send, all "failed" recipients should be marked as "sending".
        unpreparedMessage.updateAllUnsentRecipientsAsSending(transaction: transaction)

        didCompletePrep = true
        return message
    }

    private static func prepareAttachments(message: TSOutgoingMessage, tx: SDSAnyWriteTransaction) -> [String] {
        var attachmentIds = [String]()

        attachmentIds.append(contentsOf: message.bodyAttachmentIds(transaction: tx))

        if message.quotedMessage?.fetchThumbnailAttachmentId(forParentMessage: message, transaction: tx) != nil {
            // We need to update the message record here to reflect the new attachments we may create.
            let thumbnail = message.quotedMessage?.createThumbnailAndUpdateMessageIfNecessary(
                withParentMessage: message,
                transaction: tx
            )
            thumbnail.map { attachmentIds.append($0.uniqueId) }
        }

        if let contactShare = message.contactShare, contactShare.avatarAttachmentId != nil {
            let attachmentStream = contactShare.avatarAttachment(with: tx) as? TSAttachmentStream
            owsAssertDebug(attachmentStream != nil)
            attachmentStream.map { attachmentIds.append($0.uniqueId) }
        }

        if
            let linkPreview = message.linkPreview,
            let attachmentId = linkPreview.imageAttachmentStreamId(forParentMessage: message, tx: tx)
        {
            attachmentIds.append(attachmentId)
        }

        if let messageSticker = message.messageSticker {
            let attachmentId = messageSticker.attachmentId
            let attachmentStream = TSAttachmentStream.anyFetchAttachmentStream(uniqueId: attachmentId, transaction: tx)
            owsAssertDebug(attachmentStream != nil)
            attachmentStream.map { attachmentIds.append($0.uniqueId) }
        }

        return attachmentIds
    }
}

extension TSOutgoingMessage {
    @objc
    public var asPreparer: OutgoingMessagePreparer {
        return OutgoingMessagePreparer(self)
    }
}
