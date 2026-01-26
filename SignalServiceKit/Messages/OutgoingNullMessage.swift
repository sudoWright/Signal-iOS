//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(OWSOutgoingNullMessage)
final class OutgoingNullMessage: TransientOutgoingMessage {

    let verificationStateSyncMessage: OutgoingVerificationStateSyncMessage?

    init(contactThread: TSContactThread, verificationStateSyncMessage: OutgoingVerificationStateSyncMessage? = nil, tx: DBReadTransaction) {
        self.verificationStateSyncMessage = verificationStateSyncMessage
        let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: contactThread)
        super.init(
            outgoingMessageWith: messageBuilder,
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx,
        )
    }

    override class var supportsSecureCoding: Bool { true }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        if let verificationStateSyncMessage {
            coder.encode(verificationStateSyncMessage, forKey: "verificationStateSyncMessage")
        }
    }

    required init?(coder: NSCoder) {
        self.verificationStateSyncMessage = coder.decodeObject(of: OutgoingVerificationStateSyncMessage.self, forKey: "verificationStateSyncMessage")
        super.init(coder: coder)
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.verificationStateSyncMessage)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.verificationStateSyncMessage == object.verificationStateSyncMessage else { return false }
        return true
    }

    override func contentBuilder(thread: TSThread, transaction: DBReadTransaction) -> SSKProtoContentBuilder? {
        let nullMessageBuilder = SSKProtoNullMessage.builder()

        if let verificationStateSyncMessage {
            var contentLength = verificationStateSyncMessage.unpaddedVerifiedLength()

            owsAssertDebug(verificationStateSyncMessage.paddingBytesLength > 0)

            // We add the same amount of padding in the VerificationStateSync message
            // and its corresponding NullMessage so that the sync message is
            // indistinguishable from an outgoing Sent transcript corresponding to the
            // NullMessage. We pad the NullMessage so as to obscure its content. The
            // sync message (like all sync messages) will be *additionally* padded by
            // the superclass while being sent. The end result is we send a NullMessage
            // of a non-distinct size, and a verification sync which is ~1-512 bytes
            // larger than that.
            contentLength += verificationStateSyncMessage.paddingBytesLength

            owsAssertDebug(contentLength > 0)

            nullMessageBuilder.setPadding(Randomness.generateRandomBytes(contentLength))
        }

        let nullMessage = nullMessageBuilder.buildInfallibly()

        let contentBuilder = SSKProtoContent.builder()
        contentBuilder.setNullMessage(nullMessage)
        return contentBuilder
    }

    override func shouldSyncTranscript() -> Bool { false }

    override var contentHint: SealedSenderContentHint { .implicit }
}
