import SwiftUI
import CoreImage
import CryptoKit
import UIKit

// MARK: - QQ 互联配置
struct QQConfig {
    static let appID = "100360353"
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

// MARK: - 游戏配置
struct GameConfig: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let scheme: String
    let icon: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: GameConfig, rhs: GameConfig) -> Bool {
        lhs.id == rhs.id
    }
}

let supportedGames: [GameConfig] = [
    GameConfig(name: "三角洲行动", scheme: "seecoon://", icon: "figure.martial.arts"),
    GameConfig(name: "暗区突围", scheme: "darkzone://", icon: "target"),
    GameConfig(name: "和平精英", scheme: "pubgmhd://", icon: "scope")
]

// MARK: - AppDelegate（全屏 + 方向控制）
class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.portrait
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
    
    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        return QQAuthManager.shared.handleCallback(url: url)
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        return true
    }
}

// MARK: - 全屏 Window 控制器
class FullScreenHostingController<Content: View>: UIHostingController<Content> {
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var childForStatusBarHidden: UIViewController? { nil }
    override var childForHomeIndicatorAutoHidden: UIViewController? { nil }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        additionalSafeAreaInsets = .zero
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.frame = UIScreen.main.bounds
    }
}

// MARK: - 屏幕方向控制
struct OrientationHelper {
    static func lockPortrait() {
        AppDelegate.orientationLock = .portrait
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }
    
    static func lockLandscape() {
        AppDelegate.orientationLock = .landscapeRight
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
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

// MARK: - Token 提取工具
struct TokenExtractor {
    static func extractToken(from text: String) -> String? {
        let patterns = [
            "seecoon_token=([A-Za-z0-9+/=]{50,})",
            "token=([A-Za-z0-9+/=]{50,})",
            "([A-Za-z0-9+/=]{80,})"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range])
            }
        }
        return nil
    }
}

// MARK: - 加密工具
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

// MARK: - 账号模型
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

// MARK: - 数据管理器
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
enum AppPage { case home, capture, accountList, tokenLogin, extractToken }

// MARK: - 全屏修饰器
struct FullScreenModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
            .edgesIgnoringSafeArea(.all)
            .statusBar(hidden: true)
    }
}

extension View {
    func trueFullScreen() -> some View {
        self.modifier(FullScreenModifier())
    }
}

// MARK: - 主界面
struct HomeView: View {
    @Binding var currentPage: AppPage
    
    var body: some View {
        ZStack {
            Color.white
            VStack(spacing: 0) {
                Spacer()
                Text("三角洲行动助手")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.bottom, 40)
                VStack(spacing: 18) {
                    Button("挂机收号 + QQ扫码") { currentPage = .capture }
                        .homeButtonStyle(color: .red)
                    Button("账号库存") { currentPage = .accountList }
                        .homeButtonStyle(color: .green)
                    Button("Token 一键上号") { currentPage = .tokenLogin }
                        .homeButtonStyle(color: .blue)
                    Button("提取 Token（从文本）") { currentPage = .extractToken }
                        .homeButtonStyle(color: .purple)
                }
                .padding(.horizontal, 30)
                Spacer()
            }
        }
        .trueFullScreen()
        .onAppear { OrientationHelper.lockPortrait() }
    }
}

extension View {
    func homeButtonStyle(color: Color) -> some View {
        self.font(.system(size: 18, weight: .medium))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(color)
            .cornerRadius(14)
    }
}

// MARK: - 挂机收号 + QQ扫码 合并页面
struct CapturePage: View {
    @EnvironmentObject var manager: DataManager
    @Binding var currentPage: AppPage
    @State private var selectedMode = 0
    @State private var catchCount = 0
    @State private var qrImage = UIImage()
    @State private var session = ""
    @State private var clipTask: Task<Void, Never>?
    @State private var loopTask: Task<Void, Never>?
    @State private var lastPaste = ""
    @StateObject private var authManager = QQAuthManager.shared
    
    func newSession() {
        loopTask?.cancel()
        clipTask?.cancel()
        session = UUID().uuidString
        let base64Session = Data(session.utf8).base64EncodedString()
        let customProtocol = "open://authdata/\(base64Session)"
        qrImage = QRGenerator.createQRCode(text: customProtocol)
        startClipboard()
        startPolling()
    }
    
    func startClipboard() {
        clipTask = Task {
            while true {
                try? await Task.sleep(nanoseconds: 400_000_000)
                await MainActor.run {
                    let paste = UIPasteboard.general.string ?? ""
                    if paste != lastPaste && paste.contains("open://authdata/") {
                        lastPaste = paste
                    }
                }
            }
        }
    }
    
    func startPolling() {
        loopTask = Task {
            var count = 0
            while true {
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                count += 1
                if count >= 70 { await MainActor.run { newSession() }; break }
                guard let url = URL(string: "https://game.seecoon.com/api/login/checkScan?session=\(session)") else { continue }
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let user = json["data"] as? [String: Any] else { continue }
                    let acc = Account(openid: user["openid"] as! String,
                                      seecoon_token: user["seecoon_token"] as! String,
                                      quid: user["quid"] as! String,
                                      refresh_token: user["refresh_token"] as! String)
                    await MainActor.run { manager.saveNewAccount(acc); catchCount += 1; newSession() }
                    break
                } catch {}
            }
        }
    }
    
    var body: some View {
        ZStack {
            Color.white
            VStack(spacing: 0) {
                HStack {
                    Button("← 返回首页") {
                        OrientationHelper.lockPortrait()
                        loopTask?.cancel(); clipTask?.cancel()
                        currentPage = .home
                    }
                    .foregroundColor(.blue).font(.system(size: 16))
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 10)
                
                Picker("模式", selection: $selectedMode) {
                    Text("挂机收号").tag(0); Text("QQ扫码").tag(1)
                }
                .pickerStyle(.segmented).padding(.horizontal, 40).padding(.vertical, 10)
                
                Spacer()
                
                if selectedMode == 0 {
                    Image(uiImage: qrImage).resizable().scaledToFit().frame(width: 260, height: 260)
                    Text("已抓取：\(catchCount) 个账号").foregroundColor(.gray).font(.system(size: 16)).padding(.top, 15)
                } else {
                    if let url = authManager.startAuth() {
                        Image(uiImage: QRGenerator.createQRCode(text: url.absoluteString)).resizable().scaledToFit().frame(width: 260, height: 260)
                    }
                    if let token = authManager.accessToken {
                        Text("Token: \(String(token.prefix(15)))...").foregroundColor(.green).font(.system(size: 14)).padding(.top, 10)
                        Button("复制 Token") { UIPasteboard.general.string = authManager.accessToken }.foregroundColor(.blue)
                    } else {
                        Text("请使用 QQ 扫描此二维码").foregroundColor(.gray).font(.system(size: 16)).padding(.top, 15)
                    }
                }
                Spacer()
            }
        }
        .trueFullScreen()
        .onAppear { OrientationHelper.lockLandscape(); if selectedMode == 0 { newSession() } }
        .onChange(of: selectedMode) { mode in
            if mode == 0 { newSession() } else { loopTask?.cancel(); clipTask?.cancel(); _ = authManager.startAuth() }
        }
        .onDisappear { loopTask?.cancel(); clipTask?.cancel(); OrientationHelper.lockPortrait() }
    }
}

// MARK: - 账号库存页面
struct PageB: View {
    @EnvironmentObject var manager: DataManager
    @Binding var currentPage: AppPage
    
    var body: some View {
        ZStack {
            Color.white
            VStack(spacing: 0) {
                HStack {
                    Button("← 返回首页") { currentPage = .home }.foregroundColor(.blue).font(.system(size: 16))
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 10)
                
                Text("账号库存").font(.system(size: 22, weight: .bold)).foregroundColor(.black).padding(.vertical, 12)
                
                List(manager.accounts) { acc in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OpenID: \(acc.openid)").foregroundColor(.black).font(.system(size: 14))
                        Text("Token: \(String(acc.seecoon_token.prefix(20)))...").font(.system(size: 11)).foregroundColor(.gray)
                        HStack {
                            Button("复制") { UIPasteboard.general.string = acc.seecoon_token }.font(.system(size: 13))
                            Button("删除", role: .destructive) { manager.deleteAccount(uuid: acc.id) }.font(.system(size: 13))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .trueFullScreen()
        .onAppear { OrientationHelper.lockPortrait() }
    }
}

// MARK: - Token 一键上号页面
struct TokenLoginPage: View {
    @Binding var currentPage: AppPage
    @State var token = ""
    @State var selectedGame = 0
    @State var status = ""
    
    var body: some View {
        ZStack {
            Color.white
            VStack(spacing: 0) {
                HStack {
                    Button("← 返回首页") { currentPage = .home }.foregroundColor(.blue).font(.system(size: 16))
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 10)
                
                Spacer()
                
                Text("Token 一键上号").font(.system(size: 24, weight: .bold)).foregroundColor(.black).padding(.bottom, 20)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("选择游戏：").foregroundColor(.gray).font(.system(size: 14))
                    Menu {
                        ForEach(0..<supportedGames.count, id: \.self) { i in
                            Button(action: { selectedGame = i }) {
                                HStack {
                                    Image(systemName: supportedGames[i].icon)
                                    Text(supportedGames[i].name)
                                    if selectedGame == i { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: supportedGames[selectedGame].icon)
                            Text(supportedGames[selectedGame].name)
                            Spacer()
                            Image(systemName: "chevron.down").foregroundColor(.gray)
                        }
                        .padding().background(Color(.systemGray6)).cornerRadius(10)
                    }
                }
                .padding(.horizontal, 25).padding(.bottom, 20)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("输入 Token：").foregroundColor(.gray).font(.system(size: 14))
                    HStack(spacing: 8) {
                        TextField("粘贴 Token", text: $token)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 16))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        Button(action: {
                            if let pasteString = UIPasteboard.general.string {
                                token = pasteString
                            }
                        }) {
                            Text("读取粘贴板").font(.system(size: 13)).foregroundColor(.white)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(Color.gray).cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 25)
                
                Button("校验 Token") { check() }
                    .foregroundColor(.white).font(.system(size: 17))
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(Color.blue).cornerRadius(10)
                    .padding(.horizontal, 25).padding(.top, 18)
                
                Text(status).foregroundColor(status.contains("✅") ? .green : .red).font(.system(size: 15)).padding(.top, 8)
                
                Button("一键拉起 \(supportedGames[selectedGame].name)") { loginGame() }
                    .disabled(token.isEmpty)
                    .foregroundColor(.white).font(.system(size: 17))
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(Color.orange).cornerRadius(10)
                    .padding(.horizontal, 25).padding(.top, 12)
                
                Spacer()
            }
        }
        .trueFullScreen()
        .onAppear { OrientationHelper.lockPortrait() }
    }
    
    func check() {
        if token.isEmpty { status = "❌ 请输入 Token" }
        else if token.count > 80 { status = "✅ Token 格式有效" }
        else { status = "❌ Token 格式无效" }
    }
    
    func loginGame() {
        let game = supportedGames[selectedGame]
        if let url = URL(string: "\(game.scheme)login?token=\(token)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - 提取 Token 页面
struct ExtractTokenPage: View {
    @Binding var currentPage: AppPage
    @State private var inputText = ""
    @State private var extractedToken = ""
    @State private var message = ""
    
    var body: some View {
        ZStack {
            Color.white
            VStack(spacing: 0) {
                HStack {
                    Button("← 返回首页") { currentPage = .home }.foregroundColor(.blue).font(.system(size: 16))
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 10)
                
                Spacer()
                
                Text("从文本中提取 Token")
                    .font(.system(size: 24, weight: .bold)).foregroundColor(.black).padding(.bottom, 20)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("粘贴包含 Token 的文本：").foregroundColor(.gray).font(.system(size: 14))
                    
                    TextEditor(text: $inputText)
                        .frame(height: 150)
                        .border(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                        .font(.system(size: 15))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .padding(.horizontal, 25)
                
                Button("提取 Token") {
                    if let token = TokenExtractor.extractToken(from: inputText) {
                        extractedToken = token
                        message = "✅ 提取成功"
                    } else {
                        extractedToken = ""
                        message = "❌ 未找到有效 Token"
                    }
                }
                .foregroundColor(.white).font(.system(size: 17))
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(Color.blue).cornerRadius(10)
                .padding(.horizontal, 25).padding(.top, 18)
                
                Text(message).foregroundColor(message.contains("✅") ? .green : .red).font(.system(size: 15)).padding(.top, 8)
                
                if !extractedToken.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("提取的 Token：").foregroundColor(.gray).font(.system(size: 14))
                        Text(extractedToken).font(.system(size: 11)).foregroundColor(.black).padding().background(Color(.systemGray6)).cornerRadius(8)
                        Button("复制 Token") { UIPasteboard.general.string = extractedToken }
                            .foregroundColor(.white).font(.system(size: 17))
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(Color.green).cornerRadius(10)
                    }
                    .padding(.horizontal, 25).padding(.top, 15)
                }
                
                Spacer()
            }
        }
        .trueFullScreen()
        .onAppear { OrientationHelper.lockPortrait() }
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
                case .home:
                    HomeView(currentPage: $currentPage).environmentObject(manager)
                case .capture:
                    CapturePage(currentPage: $currentPage).environmentObject(manager)
                case .accountList:
                    PageB(currentPage: $currentPage).environmentObject(manager)
                case .tokenLogin:
                    TokenLoginPage(currentPage: $currentPage)
                case .extractToken:
                    ExtractTokenPage(currentPage: $currentPage)
                }
            }
        }
    }
}