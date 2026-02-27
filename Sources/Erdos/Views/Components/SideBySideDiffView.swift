import SwiftUI
import AppKit

struct SideBySideDiffView: NSViewRepresentable {
    let diffText: String

    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        let leftScroll = NSScrollView()
        let rightScroll = NSScrollView()

        for scrollView in [leftScroll, rightScroll] {
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            scrollView.autoresizingMask = [.width, .height]
            scrollView.borderType = .noBorder

            let textView = NSTextView()
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = true
            textView.backgroundColor = .textBackgroundColor
            textView.textContainerInset = NSSize(width: 8, height: 8)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = true
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

            scrollView.documentView = textView
        }

        // Divider
        let divider = NSBox()
        divider.boxType = .separator

        // Layout with Auto Layout
        leftScroll.translatesAutoresizingMaskIntoConstraints = false
        rightScroll.translatesAutoresizingMaskIntoConstraints = false
        divider.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(leftScroll)
        container.addSubview(divider)
        container.addSubview(rightScroll)

        NSLayoutConstraint.activate([
            leftScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            leftScroll.topAnchor.constraint(equalTo: container.topAnchor),
            leftScroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            leftScroll.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.5, constant: -0.5),

            divider.leadingAnchor.constraint(equalTo: leftScroll.trailingAnchor),
            divider.topAnchor.constraint(equalTo: container.topAnchor),
            divider.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            rightScroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            rightScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rightScroll.topAnchor.constraint(equalTo: container.topAnchor),
            rightScroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        context.coordinator.leftScrollView = leftScroll
        context.coordinator.rightScrollView = rightScroll
        context.coordinator.setupSyncScrolling()

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let leftScroll = context.coordinator.leftScrollView,
              let rightScroll = context.coordinator.rightScrollView,
              let leftTextView = leftScroll.documentView as? NSTextView,
              let rightTextView = rightScroll.documentView as? NSTextView else { return }

        let (leftContent, rightContent) = buildSideBySideContent(from: diffText)
        leftTextView.textStorage?.setAttributedString(leftContent)
        rightTextView.textStorage?.setAttributedString(rightContent)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Content Building

    private func buildSideBySideContent(from text: String) -> (NSAttributedString, NSAttributedString) {
        let lines = DiffColorizer.parseDiff(text)
        let monoFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let smallMono = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)

        let leftResult = NSMutableAttributedString()
        let rightResult = NSMutableAttributedString()

        for line in lines {
            switch line.type {
            case .header:
                let attr: [NSAttributedString.Key: Any] = [
                    .font: smallMono,
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
                let text = NSAttributedString(string: line.content + "\n", attributes: attr)
                leftResult.append(text)
                rightResult.append(text)

            case .hunkHeader:
                let attr: [NSAttributedString.Key: Any] = [
                    .font: monoFont,
                    .foregroundColor: NSColor.cyan,
                    .backgroundColor: NSColor.cyan.withAlphaComponent(0.05),
                ]
                let text = NSAttributedString(string: line.content + "\n", attributes: attr)
                leftResult.append(text)
                rightResult.append(text)

            case .context:
                let lineNum = String(format: "%4d  ", line.oldLineNumber ?? 0)
                let attr: [NSAttributedString.Key: Any] = [
                    .font: monoFont,
                    .foregroundColor: NSColor.labelColor,
                ]
                let numAttr: [NSAttributedString.Key: Any] = [
                    .font: monoFont,
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]
                let leftLine = NSMutableAttributedString(string: lineNum, attributes: numAttr)
                leftLine.append(NSAttributedString(string: line.content + "\n", attributes: attr))
                leftResult.append(leftLine)

                let rightLineNum = String(format: "%4d  ", line.newLineNumber ?? 0)
                let rightLine = NSMutableAttributedString(string: rightLineNum, attributes: numAttr)
                rightLine.append(NSAttributedString(string: line.content + "\n", attributes: attr))
                rightResult.append(rightLine)

            case .removed:
                let lineNum = String(format: "%4d  ", line.oldLineNumber ?? 0)
                let attr: [NSAttributedString.Key: Any] = [
                    .font: monoFont,
                    .foregroundColor: NSColor.systemRed,
                    .backgroundColor: NSColor.systemRed.withAlphaComponent(0.08),
                ]
                let numAttr: [NSAttributedString.Key: Any] = [
                    .font: monoFont,
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]
                let leftLine = NSMutableAttributedString(string: lineNum, attributes: numAttr)
                leftLine.append(NSAttributedString(string: line.content + "\n", attributes: attr))
                leftResult.append(leftLine)

                // Blank line on right side
                rightResult.append(NSAttributedString(string: "\n", attributes: [.font: monoFont]))

            case .added:
                // Blank line on left side
                leftResult.append(NSAttributedString(string: "\n", attributes: [.font: monoFont]))

                let lineNum = String(format: "%4d  ", line.newLineNumber ?? 0)
                let attr: [NSAttributedString.Key: Any] = [
                    .font: monoFont,
                    .foregroundColor: NSColor.systemGreen,
                    .backgroundColor: NSColor.systemGreen.withAlphaComponent(0.08),
                ]
                let numAttr: [NSAttributedString.Key: Any] = [
                    .font: monoFont,
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]
                let rightLine = NSMutableAttributedString(string: lineNum, attributes: numAttr)
                rightLine.append(NSAttributedString(string: line.content + "\n", attributes: attr))
                rightResult.append(rightLine)
            }
        }

        return (leftResult, rightResult)
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator {
        var leftScrollView: NSScrollView?
        var rightScrollView: NSScrollView?
        private var isSyncing = false

        func setupSyncScrolling() {
            guard let left = leftScrollView, let right = rightScrollView else { return }

            left.contentView.postsBoundsChangedNotifications = true
            right.contentView.postsBoundsChangedNotifications = true

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(leftDidScroll(_:)),
                name: NSView.boundsDidChangeNotification,
                object: left.contentView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(rightDidScroll(_:)),
                name: NSView.boundsDidChangeNotification,
                object: right.contentView
            )
        }

        @objc private func leftDidScroll(_ notification: Notification) {
            guard !isSyncing, let left = leftScrollView, let right = rightScrollView else { return }
            isSyncing = true
            right.contentView.scroll(to: left.contentView.bounds.origin)
            right.reflectScrolledClipView(right.contentView)
            isSyncing = false
        }

        @objc private func rightDidScroll(_ notification: Notification) {
            guard !isSyncing, let left = leftScrollView, let right = rightScrollView else { return }
            isSyncing = true
            left.contentView.scroll(to: right.contentView.bounds.origin)
            left.reflectScrolledClipView(left.contentView)
            isSyncing = false
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
