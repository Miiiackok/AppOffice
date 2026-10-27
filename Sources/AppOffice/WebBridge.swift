import OfficeCore
import WebKit

/// 不是 key window 时第一下点击也交给网页；不接受拖进来的文件和链接
final class OfficeWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // 拖进来的文件会让 WKWebView 直接打开它，换掉办公室页面。
    // 不用 unregisterDraggedTypes()：WebKit 可能在之后自己重新注册；直接拦住拖放回调最稳
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { [] }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { false }
}

/// office://app/... → web/dist 里的文件
final class WebAssetHandler: NSObject, WKURLSchemeHandler {
    private let root: URL

    init(root: URL) {
        self.root = root
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              let hit = WebAssets.resolve(root: root, path: url.path),
              let data = try? Data(contentsOf: hit.url) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let headers = ["Content-Type": hit.mime, "Content-Length": String(data.count), "Access-Control-Allow-Origin": "*"]
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// 网页 ↔ Swift：发消息给 window.office.receive，收 webkit.messageHandlers.office 的操作
final class WebBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: OfficeWebView
    var onAction: ((OfficeAction) -> Void)?
    /// 网页进程挂了（会自动重新加载）
    var onCrash: (() -> Void)?
    /// 短时间内反复崩溃，不再重新加载
    var onGiveUp: (() -> Void)?
    var onLoadFailed: ((String) -> Void)?
    private let logging = ProcessInfo.processInfo.environment["APP_OFFICE_LOG"] != nil
    /// 最近的崩溃时间，用来判断是不是在反复崩溃
    private var crashTimes: [Date] = []

    init(webRoot: URL) {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(WebAssetHandler(root: webRoot), forURLScheme: WebAssets.scheme)
        webView = OfficeWebView(frame: .zero, configuration: config)
        super.init()
        // 必须在加载页面之前注册：网页启动时只检查一次，没有就进 mock 模式
        webView.configuration.userContentController.add(WeakMessageHandler(self), name: "office")
        webView.navigationDelegate = self
        webView.isInspectable = true // Safari 开发菜单里能调试
    }

    func load() {
        webView.load(URLRequest(url: WebAssets.indexURL))
    }

    func send(_ messages: [OutboundMessage]) {
        for message in messages {
            let json = message.json()
            if logging { print("→ web", Self.summary(message, bytes: json.utf8.count)) }
            webView.callAsyncJavaScript("window.office.receive(m); return 0;", arguments: ["m": json],
                                        in: nil, in: .page) { [logging] result in
                if logging, case .failure(let error) = result { print("send failed:", error.localizedDescription) }
            }
        }
    }

    /// 转发鼠标位置（窗口坐标）给网页弹名片；nil 是移出了窗口
    func hover(atWindowPoint point: NSPoint?) {
        guard let point else {
            webView.evaluateJavaScript("window.office?.hover?.(null, null)")
            return
        }
        let p = webView.convert(point, from: nil)
        // 网页坐标原点在左上角
        let y = webView.isFlipped ? p.y : webView.bounds.height - p.y
        webView.evaluateJavaScript("window.office?.hover?.(\(Double(p.x)), \(Double(y)))")
    }

    /// 日志里只打摘要：roster 带图标很长
    private static func summary(_ message: OutboundMessage, bytes: Int) -> String {
        switch message {
        case .roster(let rooms, let employees):
            return "roster \(rooms.count) rooms, \(employees.count) employees, \(bytes) bytes"
        case .status(let network, let employees):
            let states = employees.map { "\($0.id)=\($0.state.rawValue)" }.joined(separator: ", ")
            return "status \(network.rawValue) [\(states)]"
        case .paused(let paused):
            return "paused \(paused)"
        case .locale(let lang):
            return "locale \(lang.rawValue)"
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let action = OfficeAction.parse(message.body) else { return }
        if logging { print("← web", action) }
        onAction?(action)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        onCrash?()
        // 60 秒内崩了 3 次就放弃，避免无限崩溃重载
        let now = Date()
        crashTimes = crashTimes.filter { now.timeIntervalSince($0) < 60 } + [now]
        guard crashTimes.count < 3 else {
            onGiveUp?()
            return
        }
        // 隔 1 秒再加载，不要立刻重来
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.load() }
    }

    /// 只允许加载 office:// 自己的页面，链接、跳转、外部网址一律拦掉
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let allowed = navigationAction.request.url?.scheme?.lowercased() == WebAssets.scheme
        if !allowed && logging { print("blocked navigation:", navigationAction.request.url?.absoluteString ?? "nil") }
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        reportLoadFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        reportLoadFailure(error)
    }

    /// 被新的加载打断（NSURLErrorCancelled）、被上面拦掉的跳转（WebKit 102）都不算失败
    private func reportLoadFailure(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return }
        onLoadFailed?(error.localizedDescription)
    }
}

/// WKUserContentController 会强引用 handler，转一层弱引用避免循环引用
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
