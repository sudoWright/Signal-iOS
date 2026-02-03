//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
public import LibSignalClient

public final class KeyTransparencyManager {
    /// Parameters required to do a Key Transparency check.
    public struct CheckParams {
        fileprivate let isLocalUser: Bool

        fileprivate let aciInfo: KeyTransparency.AciInfo
        fileprivate let e164Info: KeyTransparency.E164Info
        fileprivate let username: Username?
    }

    private let chatConnectionManager: ChatConnectionManager
    private let db: DB
    private let localUsernameManager: LocalUsernameManager
    private let logger: PrefixedLogger
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let tsAccountManager: TSAccountManager
    private let udManager: OWSUDManager

    private let taskQueue: KeyedConcurrentTaskQueue<Aci>

    init(
        chatConnectionManager: ChatConnectionManager,
        db: DB,
        localUsernameManager: LocalUsernameManager,
        recipientDatabaseTable: RecipientDatabaseTable,
        tsAccountManager: TSAccountManager,
        udManager: OWSUDManager,
    ) {
        self.chatConnectionManager = chatConnectionManager
        self.db = db
        self.localUsernameManager = localUsernameManager
        self.logger = PrefixedLogger(prefix: "[KT]")
        self.recipientDatabaseTable = recipientDatabaseTable
        self.tsAccountManager = tsAccountManager
        self.udManager = udManager

        self.taskQueue = KeyedConcurrentTaskQueue(concurrentLimitPerKey: 1)
    }

    // MARK: -

    /// Prepare to perform a Key Transparency check.
    /// - Returns
    /// Params required for the KT check, or `nil` if a check cannot be
    /// performed.
    public func prepareCheck(
        aci: Aci,
        identityKey: IdentityKey,
        tx: DBReadTransaction,
    ) -> CheckParams? {
        let logger = logger.suffixed(with: "[\(aci)]")
        logger.info("")

        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
            logger.warn("Missing local identifiers.")
            return nil
        }

        let aciInfo = KeyTransparency.AciInfo(
            aci: aci,
            identityKey: identityKey,
        )

        let e164Info: KeyTransparency.E164Info
        if
            let recipient = recipientDatabaseTable.fetchRecipient(
                serviceId: aci,
                transaction: tx,
            ),
            let e164 = recipient.phoneNumber?.stringValue,
            let uak = udManager.udAccessKey(for: aci, tx: tx)
        {
            e164Info = KeyTransparency.E164Info(
                e164: e164,
                unidentifiedAccessKey: uak.keyData,
            )
        } else {
            logger.warn("Missing E164Info.")
            return nil
        }

        // We only check the username hash for the local user.
        let username: Username?
        if localIdentifiers.contains(serviceId: aci) {
            switch localUsernameManager.usernameState(tx: tx) {
            case .unset:
                username = nil
            case .available(let _username, _), .linkCorrupted(let _username):
                do {
                    username = try Username(_username)
                } catch {
                    logger.warn("Failed to hash local username! \(error)")
                    return nil
                }
            case .usernameAndLinkCorrupted:
                logger.warn("Local username is corrupted.")
                return nil
            }
        } else {
            username = nil
        }

        return CheckParams(
            isLocalUser: localIdentifiers.contains(serviceId: aci),
            aciInfo: aciInfo,
            e164Info: e164Info,
            username: username,
        )
    }

    // MARK: -

    public func performCheck(params: CheckParams) async throws {
        try await taskQueue.run(forKey: params.aciInfo.aci) {
            let logger = logger.suffixed(with: "[\(params.aciInfo.aci)]")

            do {
                // We want to retry network errors indefinitely, as we don't
                // want them to suggest that KT has failed.
                try await Retry.performWithBackoff(
                    maxAttempts: .max,
                    preferredBackoffBlock: { error -> TimeInterval? in
                        switch error {
                        case SignalError.rateLimitedError(let retryAfter, message: _):
                            return retryAfter
                        default:
                            return nil
                        }
                    },
                    isRetryable: { error -> Bool in
                        switch error {
                        case SignalError.rateLimitedError,
                             SignalError.connectionFailed,
                             SignalError.ioError,
                             SignalError.webSocketError:
                            return true
                        default:
                            return false
                        }
                    },
                    block: {
                        try await _performCheck(params: params, logger: logger)
                    },
                )

                logger.info("Success!")
            } catch {
                logger.warn("Failure! \(error)")
                throw error
            }
        }
    }

    private func _performCheck(
        params: CheckParams,
        logger: PrefixedLogger,
    ) async throws {
        let ktClient = try await chatConnectionManager.keyTransparencyClient()
        let libSignalStore = KeyTransparencyStoreForLibSignal(db: db)

        let existingKeyTransparencyRecord = db.read { tx in
            return Self.getKeyTransparencyRecord(
                aci: params.aciInfo.aci,
                tx: tx,
            )
        }

        if
            params.isLocalUser,
            existingKeyTransparencyRecord != nil
        {
            logger.info("Monitoring for self.")

            try await ktClient.monitor(
                for: .`self`,
                account: params.aciInfo,
                e164: params.e164Info,
                usernameHash: params.username?.hash,
                store: libSignalStore,
            )
        } else if params.isLocalUser {
            logger.info("Searching for self.")

            try await ktClient.search(
                account: params.aciInfo,
                e164: params.e164Info,
                usernameHash: params.username?.hash,
                store: libSignalStore,
            )
        } else if existingKeyTransparencyRecord != nil {
            logger.info("Monitoring for other.")

            try await ktClient.monitor(
                for: .other,
                account: params.aciInfo,
                e164: params.e164Info,
                store: libSignalStore,
            )
        } else {
            logger.info("Searching for other.")

            try await ktClient.search(
                account: params.aciInfo,
                e164: params.e164Info,
                store: libSignalStore,
            )
        }
    }

    // MARK: -

    public static func wipeAllKeyTransparencyData(tx: DBWriteTransaction) {
        distinguishedTreeStore.removeAll(tx: tx)
        failIfThrows {
            try KeyTransparencyRecord.deleteAll(tx.database)
        }
    }

    // MARK: -

    private static let distinguishedTreeStore = NewKeyValueStore(collection: "KT.DistinguishedTree")
    private static let distinguishedTreeStoreKey = "head"

    fileprivate static func getLastDistinguishedTreeHead(tx: DBReadTransaction) -> Data? {
        return distinguishedTreeStore.fetchValue(Data.self, forKey: distinguishedTreeStoreKey, tx: tx)
    }

    fileprivate static func setLastDistinguishedTreeHead(_ blob: Data, tx: DBWriteTransaction) {
        distinguishedTreeStore.writeValue(blob, forKey: distinguishedTreeStoreKey, tx: tx)
    }

    fileprivate static func getKeyTransparencyRecord(
        aci: Aci,
        tx: DBReadTransaction,
    ) -> KeyTransparencyRecord? {
        return failIfThrows {
            try KeyTransparencyRecord.fetchOne(tx.database, key: aci.rawUUID)
        }
    }

    fileprivate static func setKeyTransparencyBlob(
        _ libsignalBlob: Data,
        aci: Aci,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            let record = KeyTransparencyRecord(
                aci: aci.rawUUID,
                libsignalBlob: libsignalBlob,
            )

            try record.insert(tx.database)
        }
    }
}

// MARK: -

/// An instance type conforming to `LibSignalClient.KeyTransparency.Store`, used
/// exclusively when calling LibSignal's KT APIs.
private struct KeyTransparencyStoreForLibSignal: KeyTransparency.Store {
    let db: DB

    func getLastDistinguishedTreeHead() async -> Data? {
        db.read { tx in
            KeyTransparencyManager.getLastDistinguishedTreeHead(tx: tx)
        }
    }

    func setLastDistinguishedTreeHead(to blob: Data) async {
        await db.awaitableWrite { tx in
            KeyTransparencyManager.setLastDistinguishedTreeHead(blob, tx: tx)
        }
    }

    func getAccountData(for aci: Aci) async -> Data? {
        db.read { tx in
            KeyTransparencyManager.getKeyTransparencyRecord(aci: aci, tx: tx)?.libsignalBlob
        }
    }

    func setAccountData(_ data: Data, for aci: Aci) async {
        await db.awaitableWrite { tx in
            KeyTransparencyManager.setKeyTransparencyBlob(data, aci: aci, tx: tx)
        }
    }
}

// MARK: -

private struct KeyTransparencyRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "KeyTransparency"

    // Overwrite if inserting a new record with an existing ACI primary key.
    static var persistenceConflictPolicy: PersistenceConflictPolicy {
        return PersistenceConflictPolicy(
            insert: .replace,
            update: .replace,
        )
    }

    let aci: UUID
    let libsignalBlob: Data

    enum CodingKeys: String, CodingKey {
        case aci
        case libsignalBlob
    }
}
