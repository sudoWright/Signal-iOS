//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

final class DebugUIKeyTransparency: DebugUIPage {
    let name = "Key Transparency"

    func section(thread: TSThread?) -> OWSTableSection? {
        let db = DependenciesBridge.shared.db

        let items: [OWSTableItem] = [
            OWSTableItem(title: "Wipe all KT data", actionBlock: {
                db.write { tx in
                    KeyTransparencyManager.wipeAllKeyTransparencyData(tx: tx)
                }
            }),
        ]

        return OWSTableSection(items: items)
    }
}

#endif
