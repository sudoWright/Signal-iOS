//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Utility for deciding whether to offer VP9
public enum RingrtcVp9Config {
    public static func enableVp9(with remoteConfig: RemoteConfig) -> Bool {
        if DebugFlags.callingForceVp9On.get() {
            return true
        }
        if DebugFlags.callingForceVp9Off.get() {
            return false
        }
        return remoteConfig.ringrtcVp9Enabled
    }
}
