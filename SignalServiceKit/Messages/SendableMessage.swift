//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

protocol SendableMessage {
    var threadUniqueId: String { get }

    var sqliteRowId: Int64? { get }

    var uniqueId: String { get }

    var timestamp: UInt64 { get }

    var isSyncMessage: Bool { get }

    var isStorySend: Bool { get }

    var isOnline: Bool { get }

    var isTransientSKDM: Bool { get }

    var isUrgent: Bool { get }

    var isResendRequest: Bool { get }

    var canSendToLocalAddress: Bool { get }

    var contentHint: SealedSenderContentHint { get }

    var encryptionStyle: EncryptionStyle { get }

    func buildPlainTextData(_ thread: TSThread, transaction: DBWriteTransaction) -> Data?

    var wasSentToAnyRecipient: Bool { get }

    func recipientAddresses() -> [SignalServiceAddress]

    func sendingRecipientAddresses() -> [SignalServiceAddress]

    func sentRecipientAddresses() -> [SignalServiceAddress]

    func insertedMessageHasRenderableContent(rowId: Int64, tx: DBReadTransaction) -> Bool

    func anyUpdateOutgoingMessage(transaction: DBWriteTransaction, block: (TSOutgoingMessage) -> Void)

    func updateWithSkippedRecipients(_ skippedRecipients: some Sequence<SignalServiceAddress>, tx: DBWriteTransaction)

    func updateWithFailedRecipients(_ recipientErrors: some Collection<(serviceId: ServiceId, error: Error)>, tx: DBWriteTransaction)

    func updateWithSentRecipients(_ serviceIds: [ServiceId], wasSentByUD: Bool, transaction: DBWriteTransaction)

    func update(withReadRecipient recipientAddress: SignalServiceAddress, deviceId: DeviceId, readTimestamp timestamp: UInt64, tx: DBWriteTransaction)

    func update(withViewedRecipient recipientAddress: SignalServiceAddress, deviceId: DeviceId, viewedTimestamp timestamp: UInt64, tx: DBWriteTransaction)

    func shouldSyncTranscript() -> Bool

    func thread(tx: DBReadTransaction) -> TSThread?

    var shouldBeSaved: Bool { get }

    var shouldRecordSendLog: Bool { get }

    var relatedUniqueIds: Set<String> { get }

    func envelopeGroupIdWithTransaction(_ transaction: DBReadTransaction) -> Data?

    var isVoiceMessage: Bool { get }

    var isViewOnceMessage: Bool { get }

    func buildTranscriptSyncMessage(
        localThread: TSContactThread,
        transaction: DBWriteTransaction,
    ) -> OutgoingSyncMessage?

    func update(withHasSyncedTranscript: Bool, transaction: DBWriteTransaction)

    func allAttachments(transaction: DBReadTransaction) -> [ReferencedAttachment]
}

extension TSOutgoingMessage: SendableMessage {
    var threadUniqueId: String { self.uniqueThreadId }
}
