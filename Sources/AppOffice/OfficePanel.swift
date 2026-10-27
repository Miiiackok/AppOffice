import AppKit

/// 浮动小窗：不抢焦点（点它不会改变"前台 app"），可拖动、改大小，位置大小自动记住
final class OfficePanel: NSPanel {
    var onHoverChange: ((Bool) -> Void)?

    init(content: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
                   styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "AppOffice"
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        minSize = NSSize(width: 240, height: 180)
        let host = HoverView()
        host.onHover = { [weak self] inside in self?.onHoverChange?(inside) }
        contentView = host
        content.frame = host.bounds
        content.autoresizingMask = [.width, .height]
        host.addSubview(content)
        if !setFrameUsingName("OfficePanel") { placeBottomRight() }
        setFrameAutosaveName("OfficePanel")
    }

    /// 钉在最上层
    var pinned: Bool {
        get { level == .floating }
        set { level = newValue ? .floating : .normal }
    }

    private func placeBottomRight() {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: visible.maxX - frame.width - 20, y: visible.minY + 20))
    }
}

/// 鼠标进出窗口内容时回调（透明模式用）
final class HoverView: NSView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
