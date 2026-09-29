import SwiftUI
import AppKit

/// 基于 NSTextView 的高性能日志视图（支持着色与大文本量）
struct LogTextView: NSViewRepresentable {
    let onReady: (NSTextView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(
            width: textView.bounds.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        DispatchQueue.main.async {
            onReady(textView)
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    final class Coordinator: NSObject {}
}

/// 日志文本存储：负责追加着色行、自动滚动、清空
final class LogConsole {
    private(set) var textView: NSTextView?
    private var isScrolledToBottom = true

    func attach(_ textView: NSTextView) {
        self.textView = textView
        NotificationCenter.default.addObserver(
            forName: NSScrollView.didLiveScrollNotification,
            object: textView.enclosingScrollView,
            queue: .main
        ) { [weak self] _ in
            self?.updateScrollState()
        }
    }

    func appendLine(_ text: String, color: NSColor?) {
        guard let storage = textView?.textStorage else { return }
        let attr: [NSAttributedString.Key: Any] = [
            .foregroundColor: color ?? .labelColor,
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        ]
        let attributed = NSAttributedString(string: text + "\n", attributes: attr)
        storage.append(attributed)
        if isScrolledToBottom {
            textView?.scrollToEndOfDocument(nil)
        }
    }

    func clear() {
        textView?.textStorage?.setAttributedString(NSAttributedString())
    }

    private func updateScrollState() {
        guard let scrollView = textView?.enclosingScrollView else { return }
        let document = scrollView.documentVisibleRect
        let bounds = scrollView.documentView?.bounds ?? .zero
        isScrolledToBottom = document.maxY >= bounds.maxY - 4
    }
}
