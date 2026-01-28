//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension BackupArchive {

    public class AccountDataRestoringContext: RestoringContext {
        let backupPurpose: MessageBackupPurpose
        /// Will only be nil if there was no earier AccountData frame to set it, which
        /// should be treated as an error at read time when processing all subsequent frames.
        var backupPlan: BackupPlan?
        /// Will only be nil if there was no earier AccountData frame to set it, which
        /// should be treated as an error at read time when processing all subsequent frames.
        var uploadEra: String?

        init(
            backupPurpose: MessageBackupPurpose,
            startDate: Date,
            remoteConfig: RemoteConfig,
            attachmentByteCounter: BackupArchiveAttachmentByteCounter,
            isPrimaryDevice: Bool,
            tx: DBWriteTransaction,
        ) {
            self.backupPurpose = backupPurpose
            super.init(
                startDate: startDate,
                remoteConfig: remoteConfig,
                attachmentByteCounter: attachmentByteCounter,
                isPrimaryDevice: isPrimaryDevice,
                tx: tx,
            )
        }
    }
}
