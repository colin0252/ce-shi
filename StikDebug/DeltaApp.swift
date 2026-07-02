import SwiftUI
import CoreImage
import CryptoKit

// MARK: - 配置（你的真实 AppID）
struct QQConfig {
    static let appID = "100360353"   // ← 已填入你申请的 APP ID
    static let redirectURI = "seecoonlocal://oauth/callback"
    
    static func authURL(state: String) -> URL {
        var comps = URLComponents(string: "https://graph.qq.com/oauth2.0/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "client_id", value: appID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "get_user_info"),
            URLQueryItem(name: "state", value: state)
        ]
        return comps.url!
    }
}

// MARK: - AppDelegate
class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.landscapeRight
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
    
    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        return QQAuthManager.shared.handleCallback(url: url)
    }
}

// MARK: - QQ 授权管理器
class QQAuthManager: ObservableObject {
    static let shared = QQAuthManager()
    @Published var accessToken: String? = nil
    @Published var isAuthorizing = false
    private var currentState = ""
    
    func startAuth() -> URL? {
        currentState = UUID().uuidString
        isAuthorizing = true
        return QQConfig.authURL(state: currentState)
    }
    
    func handleCallback(url: URL) -> Bool {
        guard isAuthorizing else { return false }
        isAuthorizing = false
        
        var params = [String: String]()
        if let fragment = url.fragment {
            URLComponents(string: "?" + fragment)?.queryItems?.forEach { params[$0.name] = $0.value }
        } else if let query = url.query {
            URLComponents(string: "?" + query)?.queryItems?.forEach { params[$0.name] = $0.value }
        }
        
        guard params["state"] == currentState, let token = params["access_token"] else { return false }
        self.accessToken = token
        return true
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
        let box = try! AES.GCM.seal(Data(text.utf8), using: key, nonce: nonce)
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

// MARK: - 账号模型（保留）
struct Account: Identifiable, Codable {
    let id: UUID
    let openid: String
    let seecoon_token: String
    let quid: String
    let refresh_token: String
    let createTime: Date
    init(openid: String, seecoon_token: String, quid: String, refresh_token: String) {
        self.id = UUID(); self.openid = openid; self.seecoon_token = seecoon_token
        self.quid = quid; self.refresh_token = refresh_token; self.createTime = Date()
    }
    enum CodingKeys: CodingKey { case id, openid, seecoon_token, quid, refresh_token, createTime }
}

// MARK: - 数据管理器（保留）
class DataManager: ObservableObject {
    @Published var accounts: [Account] = []
    var filePath: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("delta.dat")
    }
    init() { loadAllAccounts() }
    func saveNewAccount(_ acc: Account) { accounts.append(acc); syncToDisk() }
    func deleteAccount(uuid: UUID) { accounts.removeAll { $0.id == uuid }; syncToDisk() }
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

// MARK: - QQ 授权扫码页面
struct QQAuthView: View {
    @EnvironmentObject var manager: DataManager
    @Binding var isPresented: Bool
    @StateObject private var authManager = QQAuthManager.shared
    @State private var qrImage: UIImage? = nil
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let qrImage = qrImage {
                    Image(uiImage: qrImage).resizable().scaledToFit().frame(width: 250, height: 250)
                    Text("请使用 QQ 扫描此二维码").foregroundColor(.white)
                } else {
                    ProgressView("生成二维码中...")
                }
                if let token = authManager.accessToken {
                    Text("获取到 token: \(token.prefix(10))...").foregroundColor(.green)
                    Button("复制 Token") { UIPasteboard.general.string = token }
                }
            }
            .padding()
            .background(Color.black.ignoresSafeArea())
            .onAppear {
                if let url = authManager.startAuth() {
                    qrImage = QRGenerator.createQRCode(text: url.absoluteString)
                }
            }
            .onChange(of: authManager.accessToken) { _ in
                if authManager.accessToken != nil { isPresented = false }
            }
            .navigationTitle("QQ 授权登录")
        }
    }
}

// MARK: - 主界面
struct HomeView: View {
    @Binding var currentPage: AppPage
    @State private var showQQAuth = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 35) {
                Button("QQ 扫码登录获取 Token") { showQQAuth = true }
                    .font(.title2).padding().background(Color.orange).foregroundColor(.white).cornerRadius(14)
                Button("账号库存") { currentPage = .accountList }
                    .font(.title2).padding().background(Color.green).foregroundColor(.white).cornerRadius(14)
                Button("Token 校验 + 一键上号") { currentPage = .tokenCheck }
                    .font(.title2).padding().background(Color.blue).foregroundColor(.white).cornerRadius(14)
            }
        }
        .sheet(isPresented: $showQQAuth) {
            QQAuthView(isPresented: $showQQAuth).environmentObject(DataManager())
        }
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
                            Button("复制") { UIPasteboard.general.string = acc.seecoon_token }
                            Button("删除", role: .destructive) { manager.deleteAccount(uuid: acc.id) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Token 校验与上号（保留）
struct PageC: View {
    @Binding var currentPage: AppPage
    @State var token = ""
    @State var status = ""
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 22) {
                HStack {
                    Button("返回") { currentPage = .home }.foregroundColor(.blue)
                    Spacer()
                }.padding()
                TextField("输入 Seecoon Token", text: $token).textFieldStyle(.roundedBorder).padding(.horizontal)
                Button("校验有效性") { check() }.foregroundColor(.blue)
                Text(status).foregroundColor(.white)
                Button("一键上号") {
                    UIApplication.shared.open(URL(string: "seecoon://login?token=\(token)")!)
                }.disabled(token.isEmpty)
            }
        }
    }
    
    func check() {
        status = "校验中…"
        Task {
            var req = URLRequest(url: URL(string: "https://game.seecoon.com/api/login/checkLogin")!)
            req.httpMethod = "POST"
            req.setValue("seecoon_token=\(token)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 3
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                if (json["code"] as? Int) == 200 { status = "✅ 有效" }
                else { status = "❌ 失效" }
            } catch { status = "网络错误" }
        }
    }
}

// MARK: - 程序入口
@main
struct DeltaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var manager = DataManager()
    @State var currentPage: AppPage = .home
    
    var body: some Scene {
        WindowGroup {
            if #available(iOS 16.4, *) {
                switch currentPage {
                case .home: HomeView(currentPage: $currentPage).environmentObject(manager)
                case .accountList: PageB(currentPage: $currentPage).environmentObject(manager)
                case .tokenCheck: PageC(currentPage: $currentPage)
                default: EmptyView()
                }
            }
        }
    }
}