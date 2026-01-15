//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

public struct MemberLabel {
    public let label: String
    public let groupNameColor: UIColor

    public init(label: String, groupNameColor: UIColor) {
        self.label = label
        self.groupNameColor = groupNameColor
    }
}
