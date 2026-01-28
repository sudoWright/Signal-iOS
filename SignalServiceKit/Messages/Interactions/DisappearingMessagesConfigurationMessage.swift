//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(OWSDisappearingMessagesConfigurationMessage)
final class DisappearingMessagesConfigurationMessage: TransientOutgoingMessage {

    private let configuration: DisappearingMessagesConfigurationRecord

    override var isUrgent: Bool { false }

    init(
        configuration: DisappearingMessagesConfigurationRecord,
        thread: TSThread,
        tx: DBReadTransaction,
    ) {
        self.configuration = configuration
        super.init(
            outgoingMessageWith: TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread),
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx,
        )
    }

    override class var supportsSecureCoding: Bool { true }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(configuration, forKey: "configuration")
    }

    required init?(coder: NSCoder) {
        guard let configuration = coder.decodeObject(of: DisappearingMessagesConfigurationRecord.self, forKey: "configuration") else {
            return nil
        }
        self.configuration = configuration
        super.init(coder: coder)
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.configuration)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.configuration == object.configuration else { return false }
        return true
    }

    override func dataMessageBuilder(with thread: TSThread, transaction: DBReadTransaction) -> SSKProtoDataMessageBuilder? {
        let dataMessageBuilder = super.dataMessageBuilder(with: thread, transaction: transaction)
        guard let dataMessageBuilder else {
            return nil
        }
        dataMessageBuilder.setTimestamp(self.timestamp)
        dataMessageBuilder.setFlags(UInt32(SSKProtoDataMessageFlags.expirationTimerUpdate.rawValue))
        if self.configuration.isEnabled {
            dataMessageBuilder.setExpireTimer(self.configuration.durationSeconds)
        } else {
            dataMessageBuilder.setExpireTimer(0)
        }
        dataMessageBuilder.setExpireTimerVersion(self.configuration.timerVersion)
        return dataMessageBuilder
    }
}
