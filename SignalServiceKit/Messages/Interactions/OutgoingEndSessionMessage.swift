//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(OWSEndSessionMessage)
final class OutgoingEndSessionMessage: TSOutgoingMessage {
    override class var supportsSecureCoding: Bool { true }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    init(thread: TSThread, tx: DBReadTransaction) {
        let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread)
        super.init(
            outgoingMessageWith: messageBuilder,
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx,
        )
    }

    override var shouldBeSaved: Bool { false }

    override func dataMessageBuilder(with thread: TSThread, transaction: DBReadTransaction) -> SSKProtoDataMessageBuilder? {
        guard let builder = super.dataMessageBuilder(with: thread, transaction: transaction) else {
            return nil
        }
        builder.setTimestamp(self.timestamp)
        builder.setFlags(UInt32(SSKProtoDataMessageFlags.endSession.rawValue))
        return builder
    }
}
