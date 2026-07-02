import SwiftUI
import Foundation
import WebKit
import UIKit
import CoreImage
import CryptoKit

// MARK: - 全局强制横屏
class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.landscapeRight
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}

// MARK: - 高清二维码生成
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

// MARK: - AES 加解密
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
enum AppPage { case home, pageA, pageB, pageC }

// MARK: - QQ 内部授权网页（依赖 seecoon 接口）
struct AuthWebView: UIViewRepresentable {
    let sessionID: String
    @Binding var authComplete: Bool
    
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.add(context.coordinator, name: "submitAuthData")
        let web = WKWebView(frame: .zero, configuration: config)
        let html = """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"></head><body>
        <script>
        function doAuth(){
        var ua = navigator.userAgent.toLowerCase();
        if(ua.indexOf("mobileqq") == -1 && ua.indexOf("qqbrowser") == -1) return;
        try{
        window.external.getUinSkey(function(res){
        var info = JSON.parse(res);
        window.external.showLoginDialog("三角洲行动","异地设备申请登录账号，是否授权本次登录？",function(ret){
        if(ret == "1"){
        var postBody = {"uin":info.uin,"skey":info.skey,"pttoken":info.pttoken,"session":"\(sessionID)"};
        window.webkit.messageHandlers.submitAuthData.postMessage(postBody);
        }
        });
        });
        }catch(e){}
        }
        doAuth();
        </script></body></html>
        """
        web.loadHTMLString(html, baseURL: nil)
        return web
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        let parent: AuthWebView
        // ✅ 修复点：必须初始化 parent 属性
        init(parent: AuthWebView) { self.parent = parent }
        
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if message.name == "submitAuthData", let body = message.body as? [String: String] {
                Task {
                    var req = URLRequest(url: URL(string: "https://game.seecoon.com/api/login/qqAuth")!)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try! JSONSerialization.data(withJSONObject: body)
                    let _ = try? await URLSession.shared.data(for: req)
                    await MainActor.run { parent.authComplete = true }
                }
            }
        }
    }
}

// MARK: - 挂机收号页面（剪贴板方案）
struct PageA: View {
    @EnvironmentObject var manager: DataManager
    @Binding var currentPage: AppPage
    @State private var qrImage = UIImage()
    @State private var session = ""
    @State private var catchCount = 0
    @State private var showAuth = false
    @State private var authFinished = false
    @State private var clipTask: Task<Void, Never>?
    @State private var loopTask: Task<Void, Never>?
    @State private var lastPaste = ""
    
    // 🔥 修改点：生成自定义协议二维码，QQ 扫完提示复制，而非打不开的链接
    func newSession() {
        loopTask?.cancel()
        clipTask?.cancel()
        session = UUID().uuidString
        
        // 将 session 转为 base64，再嵌到 open://authdata/ 协议中
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
                let paste = UIPasteboard.general.string ?? ""
                if paste != lastPaste && paste.contains("open://authdata/") {
                    lastPaste = paste
                    let baseStr = paste.replacingOccurrences(of: "open://authdata/", with: "")
                    guard let data = Data(base64Encoded: baseStr),
                          let sid = String(data: data, encoding: .utf8),
                          sid == session else { continue }
                    await MainActor.run { showAuth = true }
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
                if count >= 70 {
                    await MainActor.run { newSession() }
                    break
                }
                guard let url = URL(string: "https://game.seecoon.com/api/login/checkScan?session=\(session)") else { continue }
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let user = json["data"] as? [String: Any] else { continue }
                    let acc = Account(openid: user["openid"] as! String,
                                      seecoon_token: user["seecoon_token"] as! String,
                                      quid: user["quid"] as! String,
                                      refresh_token: user["refresh_token"] as! String)
                    await MainActor.run {
                        manager.saveNewAccount(acc)
                        catchCount += 1
                        newSession()
                    }
                    break
                } catch {}
            }
        }
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            HStack(spacing: 0) {
                VStack(spacing: 35) {
                    HStack {
                        Button("关闭") { exit(0) }.foregroundColor(.blue)
                        Spacer()
                    }.padding(.leading, 20)
                    Spacer()
                    Text("三角洲").font(.system(size: 52, weight: .bold)).foregroundColor(.white)
                    Text("已抓取：\(catchCount) 个").foregroundColor(.gray).font(.system(size: 22))
                    Spacer()
                }.frame(width: UIScreen.main.bounds.width * 0.45)
                
                VStack {
                    Spacer()
                    Image(uiImage: qrImage).resizable().scaledToFit().frame(width: 290, height: 290)
                    Spacer()
                }.frame(width: UIScreen.main.bounds.width * 0.55)
            }
        }
        .onAppear { newSession() }
        .onDisappear { loopTask?.cancel(); clipTask?.cancel() }
        .sheet(isPresented: $showAuth) {
            AuthWebView(sessionID: session, authComplete: $authFinished)
                .frame(width: 360, height: 460)
        }
    }
}

// MARK: - 账号库存页面
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

// MARK: - Token 校验与上号
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
                
                TextField("输入 Seecoon Token", text: $token)
                    .textFieldStyle(.roundedBorder).padding(.horizontal)
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

// MARK: - 主界面
struct HomeView: View {
    @Binding var currentPage: AppPage
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 35) {
                Button("A：挂机收号") { currentPage = .pageA }
                    .font(.title2).padding().background(Color.orange).foregroundColor(.white).cornerRadius(14)
                Button("B：账号库存") { currentPage = .pageB }
                    .font(.title2).padding().background(Color.green).foregroundColor(.white).cornerRadius(14)
                Button("C：Token 校验 + 上号") { currentPage = .pageC }
                    .font(.title2).padding().background(Color.blue).foregroundColor(.white).cornerRadius(14)
            }
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
                case .home: HomeView(currentPage: $currentPage)
                case .pageA: PageA(currentPage: $currentPage).environmentObject(manager)
                case .pageB: PageB(currentPage: $currentPage).environmentObject(manager)
                case .pageC: PageC(currentPage: $currentPage)
                }
            }
        }
    }
}