import SwiftUI
import Foundation
import CommonCrypto
import UIKit

// MARK: - AES 加密工具（使用 CCCrypt 稳定实现）
struct AESHelper {
    static let keyString = "IENNSJFJWKSFJ"
    static let mainKey = Data(keyString.utf8)
    
    static func encrypt(_ str: String) -> String {
        return aesCrypt(text: str, keyData: mainKey, isEncrypt: true)
    }
    static func decrypt(_ base64Str: String) -> String {
        return aesCrypt(text: base64Str, keyData: mainKey, isEncrypt: false)
    }
    static func customDecrypt(base64Str: String, keyStr: String) -> String {
        let kData = Data(keyStr.utf8)
        return aesCrypt(text: base64Str, keyData: kData, isEncrypt: false)
    }
    
    private static func aesCrypt(text: String, keyData: Data, isEncrypt: Bool) -> String {
        let iv = Data(repeating: UInt8(0), count: 16) // 全零 IV
        let options = CCOptions(kCCOptionPKCS7Padding)
        
        if isEncrypt {
            guard let inputData = text.data(using: .utf8) else { return "" }
            var outLength = Int(inputData.count) + kCCBlockSizeAES128
            var outData = Data(count: outLength)
            var moved = 0
            let status = outData.withUnsafeMutableBytes { outBytes in
                inputData.withUnsafeBytes { inBytes in
                    CCCrypt(CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES128),
                            options,
                            keyData.withUnsafeBytes { $0.baseAddress },
                            keyData.count,
                            iv.withUnsafeBytes { $0.baseAddress },
                            inBytes.baseAddress, inputData.count,
                            outBytes.baseAddress, outLength,
                            &moved)
                }
            }
            guard status == kCCSuccess else { return "" }
            outData.count = moved
            return outData.base64EncodedString()
        } else {
            guard let inputData = Data(base64Encoded: text) else { return "解密失败" }
            var outLength = Int(inputData.count) + kCCBlockSizeAES128
            var outData = Data(count: outLength)
            var moved = 0
            let status = outData.withUnsafeMutableBytes { outBytes in
                inputData.withUnsafeBytes { inBytes in
                    CCCrypt(CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES128),
                            options,
                            keyData.withUnsafeBytes { $0.baseAddress },
                            keyData.count,
                            iv.withUnsafeBytes { $0.baseAddress },
                            inBytes.baseAddress, inputData.count,
                            outBytes.baseAddress, outLength,
                            &moved)
                }
            }
            guard status == kCCSuccess else { return "解密失败" }
            outData.count = moved
            return String(data: outData, encoding: .utf8) ?? "解密失败"
        }
    }
}

// MARK: - 账号模型
struct Account: Codable, Identifiable {
    let id = UUID()
    let openid: String
    let seecoon_token: String
    let quid: String
    let refresh_token: String
    let createTime: Date
}

// MARK: - 数据管理器
class DataManager: ObservableObject {
    @Published var accounts: [Account] = []
    var docPath: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("delta.dat")
    }
    init(){ loadAccounts() }
    func saveAccount(acc:Account){
        accounts.append(acc)
        let json = try! JSONEncoder().encode(accounts)
        let cipher = AESHelper.encrypt(String(data:json,encoding:.utf8)!)
        try! cipher.write(to:docPath,atomically:true,encoding:.utf8)
    }
    func loadAccounts(){
        if FileManager.default.fileExists(atPath: docPath.path){
            let cipher = try! String(contentsOf: docPath)
            let jsonStr = AESHelper.decrypt(cipher)
            let data = jsonStr.data(using:.utf8)!
            accounts = try! JSONDecoder().decode([Account].self,from:data)
        }
    }
    func deleteAccount(id:UUID){
        accounts.removeAll{$0.id == id}
        let json = try! JSONEncoder().encode(accounts)
        let cipher = AESHelper.encrypt(String(data:json,encoding:.utf8)!)
        try! cipher.write(to:docPath,atomically:true,encoding:.utf8)
    }
}

// MARK: - 二维码生成（用于展示，先不做网络请求）
struct QRCodeGenerator {
    static func createQRCode(urlString:String) -> UIImage {
        let data = urlString.data(using: String.Encoding.utf8)
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(data, forKey: "inputMessage")
        filter?.setValue("H", forKey: "inputCorrectionLevel")
        let ciImage = filter?.outputImage
        let transform = CGAffineTransform(scaleX: 12, y: 12)
        let scaledImage = ciImage?.transformed(by: transform)
        return UIImage(ciImage: scaledImage!)
    }
}

// MARK: - A 页面：扫码获取 Token（简化版，仅演示 UI）
struct ScanView: View {
    @ObservedObject var dm: DataManager
    @Environment(\.presentationMode) var presentationMode
    @State var qrImage = UIImage()
    @State var sessionKey = UUID().uuidString
    let baseUrl = "https://game.seecoon.com/h5/qqauth?session="
    
    func refreshCode() {
        sessionKey = UUID().uuidString
        let qrUrl = baseUrl + sessionKey
        qrImage = QRCodeGenerator.createQRCode(urlString: qrUrl)
        // 实际轮询逻辑可在此添加，暂省略
    }
    
    var body: some View {
        VStack(spacing:20) {
            Button("← 返回首页") {
                presentationMode.wrappedValue.dismiss()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading)
            
            Text("三角洲行动 移动端扫码登录")
                .font(.title)
            Text("使用QQ扫描下方二维码，跳转三角洲APP完成授权")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            Image(uiImage: qrImage)
                .resizable()
                .frame(width: 260, height: 260)
            
            Button("刷新二维码", action: refreshCode)
                .buttonStyle(.borderedProminent)
            
            Spacer()
        }
        .onAppear {
            refreshCode()
            // 尝试打开 QQ（仅示意）
            if let url = URL(string: "mqqapi://") {
                UIApplication.shared.open(url)
            }
        }
    }
}

// MARK: - B 页面：账号管理
struct TokenManageView: View {
    @ObservedObject var dm: DataManager
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack {
            Button("← 返回首页") {
                presentationMode.wrappedValue.dismiss()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading)
            
            List(dm.accounts) { acc in
                VStack(alignment: .leading) {
                    Text("OpenID：\(acc.openid)")
                    Text("Token：\(acc.seecoon_token)")
                        .font(.system(size: 8))
                    HStack {
                        Button("复制Token") {
                            UIPasteboard.general.string = acc.seecoon_token
                        }
                        Button("删除账号", role: .destructive) {
                            dm.deleteAccount(id: acc.id)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 解密弹窗
struct DecryptView: View {
    @State var cipherText = ""
    @State var keyInput = ""
    @State var result = ""
    var body: some View {
        VStack(spacing:12) {
            TextField("粘贴dat全部密文", text: $cipherText)
                .textFieldStyle(.roundedBorder)
            TextField("输入密钥", text: $keyInput)
                .textFieldStyle(.roundedBorder)
            Button("解密") {
                result = AESHelper.customDecrypt(base64Str: cipherText, keyStr: keyInput)
            }
            TextEditor(text: $result)
                .frame(height: 200)
        }
        .padding()
    }
}

// MARK: - C 页面：Token 校验与登录
struct LoginDecryptView: View {
    @Environment(\.presentationMode) var presentationMode
    @State var inputToken = ""
    @State var tipText = ""
    @State var showDecrypt = false
    
    func checkToken() {
        let headers = [
            "Authorization": "seecoon_token=\(inputToken)",
            "User-Agent": "SeecoonGame",
            "Content-Type": "application/json"
        ]
        var req = URLRequest(url: URL(string: "https://game.seecoon.com/api/user/checkLogin")!)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = headers
        req.httpBody = "{}".data(using: .utf8)
        URLSession.shared.dataTask(with: req) { data, _, _ in
            DispatchQueue.main.async {
                guard let d = data,
                      let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let valid = json["data"] as? Bool else {
                    tipText = "网络异常"
                    return
                }
                tipText = valid ? "✅ Token有效，可以一键登录" : "❌ Token失效"
            }
        }.resume()
    }
    
    func openGame() {
        guard let url = URL(string: "seecoon://login?token=\(inputToken)") else { return }
        UIApplication.shared.open(url)
    }
    
    var body: some View {
        VStack(spacing:15) {
            Button("← 返回首页") {
                presentationMode.wrappedValue.dismiss()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading)
            
            TextField("粘贴seecoon_token", text: $inputToken)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            Button("检测Token有效性", action: checkToken)
            Text(tipText)
            Button("唤起三角洲一键登录", action: openGame)
                .disabled(!tipText.contains("✅"))
            Button("🔐 密文解密工具") {
                showDecrypt = true
            }
            Spacer()
        }
        .sheet(isPresented: $showDecrypt) {
            DecryptView()
        }
        .padding()
    }
}

// MARK: - 首页（使用 NavigationView 兼容 iOS 15）
struct HomeView: View {
    @StateObject var dm = DataManager()
    @State var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                NavigationLink(destination: ScanView(dm: dm)) {
                    Text("A：三角洲扫码获取Token")
                        .font(.title2)
                        .frame(width: 300, height: 80)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                NavigationLink(destination: TokenManageView(dm: dm)) {
                    Text("B：账号Token管理")
                        .font(.title2)
                        .frame(width: 300, height: 80)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                NavigationLink(destination: LoginDecryptView()) {
                    Text("C：Token登录与解密工具")
                        .font(.title2)
                        .frame(width: 300, height: 80)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .navigationTitle("三角洲行动工具箱")
        }
    }
}

// MARK: - App 入口
@main
struct DeltaApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}