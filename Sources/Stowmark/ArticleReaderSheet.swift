import SwiftUI
import WebKit

struct ArticleReaderSheet: View {
    var title: String
    var html: String
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button("Done") { onClose() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            ArticleWebView(html: html)
        }
        .frame(minWidth: 520, minHeight: 640)
    }
}

private struct ArticleWebView: NSViewRepresentable {
    var html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        view.loadHTMLString(html, baseURL: nil)
    }
}
