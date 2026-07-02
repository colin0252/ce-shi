import SwiftUI
import Foundation
import WebKit
import UIKit
import CoreImage
import CryptoKit

// MARK: - 全局配置（请替换为你的 QQ 互联信息）
struct QQConfig {
    static let appID = "YOUR_QQ_APP_ID"          // ← 替换为你的 QQ 互联 AppID
    static let callbackScheme = "seecoonlocal"   // 回调 URL Scheme，与 Info.plist 一致
    static let callbackPath = "oauth/callback"
    
    static var redirectURI: String {
        "\(callbackScheme)://\(callbackPath)"
    }
    
    // QQ 互联授权 URL（implicit 模式，直接返回 access_token）
    static func authURL(state: String) -> URL {
        var comps = URLComponents(string: "https://graph.qq.com/oauth2.0/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "client_id", value: appID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "get_user_info"),   // 根据需要修改
            URLQueryItem(name: "state", value: state)
        ]
        return comps.url!
    }
}

// MARK: - AppDelegate（强制横屏 + URL 回调处理）
class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.landscapeRight
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
    
    // 处理 URL 回调
    func application(_ application: UIApplication, handleOpen url: URL) -> Bool {
        return QQAuthManager.shared.handleCallback(url: url)
    }
    
    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        return QQAuthManager.shared.handleCallback(url: url)
    }
}

// MARK: - QQ 登录管理器（单例）
class QQAuthManager: ObservableObject {
    static let shared = QQAuthManager()
    
    @Published var accessToken: String? = nil
    @Published var openID: String? = nil
    @Published var expiresIn: Int = 0
    @Published var isAuthorizing = false
    
    private var currentState: String = ""
    
    func startAuth() -> URL? {
        currentState = UUID().uuidString
        isAuthorizing = true
        return QQConfig.authURL(state: currentState)
    }
    
    func handleCallback(url: URL) -> Bool {
        guard isAuthorizing else { return false }
        isAuthorizing = false
        
        // 解析回调 URL Fragment 或 Query 中的参数
        var params: [String: String] = [:]
        if let fragment = url.fragment {
            let components = URLComponents(string: "?" + fragment)
            components?.queryItems?.forEach { params[$0.name] = $0.value }
        } else if let query = url.query {
            let components = URLComponents(string: "?" + query)
            components?.queryItems?.forEach { params[$0.name] = $0.value }
        }
        
        // 验证 state
        guard let state = params["state"], state == currentState else { return false }
        
        if let token = params["access_token"] {
            self.accessToken = token
            self.expiresIn = Int(params["expires_in"] ?? "0") ?? 0
            // 如果有 openid 也会一同返回（取决于 QQ 互联的返回方式）
            if let openid = params["openid"] {
                self.openID = openid
            }
            return true
        }
        return false
    }
}

// MARK: - 二维码生成器
struct QRGenerator {
    static let context = CIContext()
    static func createQRCode(text: String) -> UIImage {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return UIImage() }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return UIImage() }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 15, y: 15))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return UIImage() }
        return UIImage(cgImage: cg)
    }
}

// MARK: - 加密工具（保留）
struct CryptoHelper {
    private static let keyRaw = Data("IENNSJFJWKSFJ20260702".utf8)
    private static let nonceRaw = Data("1234567890123456".utf8)
    
    static func encrypt(_ text: String) -> String {
        let key = SymmetricKey(data: keyRaw)
        let nonce = try! AES.GCM.Nonce(data: nonceRaw)
        let raw = Data(text.utf8)
        let box = try! AES.GCM.seal(raw, using: key, nonce: nonce)
        return box.combined!.base64EncodedString()
    }
    
    static func decrypt(_ base64Str: String) -> String {
        guard let combined = Data(base64Encoded: base64Str) else { return "" }
        let key = SymmetricKey(data: keyRaw)
        guard let box = try? AES.GCM.SealedBox(combined: combined),
              let data = try? AES.GCM.open(box, using: key) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - 账号存储模型（保留）
struct Account: Identifiable, Codable {
    let id: UUID
    let openid: String
    let seecoon_token: String
    let quid: String
    let refresh_token: String
    let createTime: Date
    
    init(openid: String, seecoon_token: String, quid: String, refresh_token: String) {
        self.id = UUID()
        self.openid = openid
        self.seecoon_token = seecoon_token
        self.quid = quid
        self.refresh_token = refresh_token
        self.createTime = Date()
    }
    
    enum CodingKeys: CodingKey { case id, openid, seecoon_token, quid, refresh_token, createTime }
}

// MARK: - 数据管理器（保留）
class DataManager: ObservableObject {
    @Published var accounts: [Account] = []
    var filePath: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("delta.dat")
    }
    init() { loadAllAccounts() }
    
    func saveNewAccount(_ acc: Account) {
        accounts.append(acc)
        syncToDisk()
    }
    
    func deleteAccount(uuid: UUID) {
        accounts.removeAll { $0.id == uuid }
        syncToDisk()
    }
    
    private func syncToDisk() {
        let json = try! JSONEncoder().encode(accounts)
        let enc = CryptoHelper.encrypt(json.base64EncodedString())
        try! enc.write(to: filePath, atomically: true, encoding: .utf8)
    }
    
    private func loadAllAccounts() {
        guard FileManager.default.fileExists(atPath: filePath.path) else { return }
        let cipher = try! String(contentsOf: filePath)
        let plain = CryptoHelper.decrypt(cipher)
        guard let data = Data(base64Encoded: plain) else { return }
        accounts = try! JSONDecoder().decode([Account].self, from: data)
    }
}

// MARK: - 页面路由
enum AppPage { case home, authQR, accountList, tokenCheck }

// MARK: - QQ 登录二维码视图（内嵌 WebView 供调试/可替代纯二维码）
struct QQAuthWebView: UIViewRepresentable {
    let url: URL
    let onCallback: (URL) -> Void
    
    func makeCoordinator() -> Coordinator { Coordinator(onCallback: onCallback) }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: url))
        return web
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let onCallback: (URL) -> Void
        init(onCallback: @escaping (URL) -> Void) { self.onCallback = onCallback }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, url.scheme == QQConfig.callbackScheme {
                onCallback(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

// MARK: - 首页
struct HomeView: View {
    @EnvironmentObject var manager: DataManager
    @Binding var currentPage: AppPage
    @State private var showQQAuth = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 35) {
                Button("QQ 登录获取 token") { showQQAuth = true }
                    .font(.title2)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                
                Button("账号库存") { currentPage = .accountList }
                    .font(.title2)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                
                Button("Token 校验 + 上号") { currentPage = .tokenCheck }
                    .font(.title2)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .sheet(isPresented: $showQQAuth) {
                QQAuthView(isPresented: $showQQAuth)
            }
        }
    }
}

// MARK: - QQ 授权视图（显示二维码）
struct QQAuthView: View {
    @Binding var isPresented: Bool
    @StateObject private var authManager = QQAuthManager.shared
    @State private var qrImage: UIImage? = nil
    @State private var authURL: URL? = nil
    @State private var showWebView = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let qrImage = qrImage {
                    Image(uiImage: qrImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 250, height: 250)
                    Text("请使用 QQ 扫描此二维码")
                        .foregroundColor(.white)
                } else {
                    ProgressView("生成二维码中...")
                }
                
                if authManager.isAuthorizing {
                    Button("打开内置浏览器授权") { showWebView = true }
                        .foregroundColor(.blue)
                }
                
                if let token = authManager.accessToken {
                    Text("获取到 token: \(token.prefix(10))...")
                        .foregroundColor(.green)
                        .padding()
                    Button("复制 Token") { UIPasteboard.general.string = token }
                }
            }
            .padding()
            .background(Color.black.ignoresSafeArea())
            .onAppear { prepareAuth() }
            .sheet(isPresented: $showWebView) {
                if let url = authURL {
                    QQAuthWebView(url: url) { callbackURL in
                        _ = authManager.handleCallback(url: callbackURL)
                        showWebView = false
                    }
                }
            }
            .onChange(of: authManager.accessToken) { _ in
                if authManager.accessToken != nil { isPresented = false }
            }
        }
    }
    
    private func prepareAuth() {
        guard let url = QQAuthManager.shared.startAuth() else { return }
        authURL = url
        qrImage = QRGenerator.createQRCode(text: url.absoluteString)
    }
}

// MARK: - 账号库存页面（保留）
struct PageB: View {
    @EnvironmentObject var manager: DataManager
    @Binding var currentPage: AppPage
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                HStack {
                    Button("返回") { currentPage = .home }.foregroundColor(.blue)
                    Spacer()
                }.padding()
                Text("账号库存").foregroundColor(.white).font(.title)
                List(manager.accounts) { acc in
                    VStack(alignment: .leading) {
                        Text("OpenID: \(acc.openid)").foregroundColor(.white)
                        Text("Token: \(acc.seecoon_token)").font(.system(size: 9)).foregroundColor(.white)
                        HStack {
                            Button("复制 Token") { UIPasteboard.general.string = acc.seecoon_token }
                            Button("删除", role: .destructive) { manager.deleteAccount(uuid: acc.id) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Token 校验与上号页面（保留）
struct PageC: View {
    @Binding var currentPage: AppPage
    @State var inputToken = ""
    @State var statusText = ""
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 22) {
                HStack {
                    Button("返回") { currentPage = .home }.foregroundColor(.blue)
                    Spacer()
                }.padding()
                
                TextField("输入 Token", text: $inputToken)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                
                Button("校验有效性") { checkToken() }.foregroundColor(.blue)
                Text(statusText).foregroundColor(.white)
                Button("一键上号（seecoon）") {
                    UIApplication.shared.open(URL(string: "seecoon://login?token=\(inputToken)")!)
                }.disabled(inputToken.isEmpty)
            }
        }
    }
    
    private func checkToken() {
        statusText = "校验中..."
        Task {
            var req = URLRequest(url: URL(string: "https://game.seecoon.com/api/login/checkLogin")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("seecoon_token=\(inputToken)", forHTTPHeaderField: "Authorization")
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                if (json["code"] as? Int) == 200 { statusText = "✅ 有效" }
                else { statusText = "❌ 失效" }
            } catch { statusText = "网络错误" }
        }
    }
}

// MARK: - 应用入口
@main
struct DeltaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var manager = DataManager()
    @State var currentPage: AppPage = .home
    
    var body: some Scene {
        WindowGroup {
            if #available(iOS 16.4, *) {
                switch currentPage {
                case .home:         HomeView(currentPage: $currentPage).environmentObject(manager)
                case .authQR:       QQAuthView(isPresented: .constant(false))  // 占位，实际用 sheet
                case .accountList:  PageB(currentPage: $currentPage).environmentObject(manager)
                case .tokenCheck:   PageC(currentPage: $currentPage)
                }
            }
        }
    }
}