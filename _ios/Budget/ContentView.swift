import SwiftUI
import WebKit
import StoreKit

let premiumProductID = "com.yaasap.budget.premium"

/// Pont natif : la page demande l'état Premium, l'achat ou la restauration via StoreKit 2.
final class PremiumBridge: NSObject, WKScriptMessageHandlerWithReply {
    weak var web: WKWebView?
    private var updates: Task<Void, Never>?

    override init() {
        super.init()
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.pushState()
            }
        }
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        let action = (message.body as? [String: Any])?["action"] as? String ?? "status"
        Task {
            var err = ""
            if action == "buy" { err = await buy() }
            if action == "restore" { err = await restore() }
            replyHandler(await state(error: err), nil)
        }
    }

    private func product() async -> Product? {
        try? await Product.products(for: [premiumProductID]).first
    }

    func isPremium() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == premiumProductID, t.revocationDate == nil { return true }
        }
        return false
    }

    func state(error: String = "") async -> [String: Any] {
        let p = await product()
        return ["premium": await isPremium(), "price": p?.displayPrice ?? "", "error": error]
    }

    private func buy() async -> String {
        guard let p = await product() else { return "Produit introuvable pour le moment. Réessayez plus tard." }
        do {
            switch try await p.purchase() {
            case .success(let v):
                if case .verified(let t) = v { await t.finish(); return "" }
                return "Achat non vérifié."
            case .userCancelled: return ""
            case .pending: return "Achat en attente d'approbation."
            @unknown default: return ""
            }
        } catch { return "Achat impossible : \(error.localizedDescription)" }
    }

    private func restore() async -> String {
        do { try await AppStore.sync(); return "" } catch { return "Restauration impossible : \(error.localizedDescription)" }
    }

    @MainActor func pushState() async {
        let s = await state()
        let js = "window.pstate && pstate({premium:\(s["premium"] as? Bool ?? false),price:\"\(s["price"] as? String ?? "")\"})"
        web?.evaluateJavaScript(js, completionHandler: nil)
    }
}

struct AppView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let bridge = PremiumBridge()
        config.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: "premium")
        let web = WKWebView(frame: .zero, configuration: config)
        bridge.web = web
        context.coordinator.bridge = bridge
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 244/255, green: 246/255, blue: 251/255, alpha: 1)
        web.scrollView.backgroundColor = web.backgroundColor
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsLinkPreview = false
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "App") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coord { Coord() }
    final class Coord { var bridge: PremiumBridge? }
}

struct ContentView: View {
    var body: some View { AppView() }
}
