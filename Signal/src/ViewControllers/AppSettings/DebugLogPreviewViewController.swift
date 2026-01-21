//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class DebugLogPreviewViewController: OWSViewController {

    private let textView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()

        loadLogs()

        title = OWSLocalizedString(
            "DEBUG_LOG_PREVIEW_TITLE",
            comment: "Title for the debug log preview screen",
        )

        view.backgroundColor = .Signal.groupedBackground

        navigationItem.rightBarButtonItem = .cancelButton(dismissingFrom: self)

        // UITableView does not have the text-rendering optimizations that
        // UITextView with scrolling enabled has, and the app freezes when
        // trying to load this much text, so fake the style with one
        // full-height "cell" instead.
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 12
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 20, trailing: 20)
        view.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewSafeArea()

        let headerLabel = UILabel()
        stackView.addArrangedSubview(headerLabel)
        stackView.setCustomSpacing(24, after: headerLabel)
        headerLabel.text = OWSLocalizedString(
            "DEBUG_LOG_PREVIEW_HEADER",
            comment: "Header text displayed above the debug log preview",
        )
        headerLabel.font = .dynamicTypeFootnote
        headerLabel.textColor = .Signal.secondaryLabel
        headerLabel.numberOfLines = 0
        headerLabel.autoPinWidthToSuperviewMargins(withInset: 24)

        let cellContainer = UIView()
        stackView.addArrangedSubview(cellContainer)
        cellContainer.autoPinWidthToSuperviewMargins()
        cellContainer.backgroundColor = .Signal.secondaryGroupedBackground
        cellContainer.layer.cornerRadius = OWSTableViewController2.cellRounding
        cellContainer.clipsToBounds = true
        cellContainer.addSubview(textView)
        textView.autoPinEdgesToSuperviewEdges()
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.backgroundColor = .clear
        textView.textColor = .Signal.secondaryLabel
        textView.textContainerInset = .init(margin: 20)
        textView.textContainer.lineFragmentPadding = 0
        textView.verticalScrollIndicatorInsets = .init(hMargin: 0, vMargin: OWSTableViewController2.cellRounding / 2)
    }

    private func loadLogs() {
        Logger.flush()

        self.textView.text = DebugLogger.shared.allLogFilePaths.reduce(
            into: "",
        ) { partialResult, logFilePath in
            do {
                let logData = try Data(contentsOf: URL(fileURLWithPath: logFilePath))
                let logText = String(data: logData, encoding: .utf8)

                guard let logText else {
                    Logger.warn("Could not decode log file")
                    return
                }

                partialResult += logText + "\n\n"
            } catch {
                Logger.warn("\(error)")
            }
        }
    }

}
