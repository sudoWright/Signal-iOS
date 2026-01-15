//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit

public class CVMemberLabel: UILabel {
    static var textInsets = UIEdgeInsets(top: 1, left: 8, bottom: 1, right: 8)

    public init(label: String, font: UIFont, backgroundColor: UIColor) {
        super.init(frame: .zero)
        super.text = label
        super.font = font
        super.backgroundColor = backgroundColor.withAlphaComponent(0.14)
        super.layer.cornerRadius = 10
        super.layer.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Center text within padding.
    override public func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: CVMemberLabel.textInsets))
    }

    override public var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + Self.textInsets.totalWidth,
            height: size.height + Self.textInsets.totalHeight,
        )
    }

    override public func sizeThatFits(_ size: CGSize) -> CGSize {
        let sizeMinusInsets = CGSize(
            width: size.width - Self.textInsets.totalWidth,
            height: size.height - Self.textInsets.totalHeight,
        )

        let textSize = super.sizeThatFits(sizeMinusInsets)

        return CGSize(
            width: textSize.width + Self.textInsets.totalWidth,
            height: textSize.height + Self.textInsets.totalHeight,
        )
    }

    public class func measureLabel(config: CVLabelConfig, maxWidth: CGFloat) -> CGSize {
        let memberLabelSize = CVText.measureLabel(config: config, maxWidth: maxWidth)
        return CGSize(
            width: memberLabelSize.width + Self.textInsets.totalWidth,
            height: memberLabelSize.height + Self.textInsets.totalHeight,
        )
    }
}
