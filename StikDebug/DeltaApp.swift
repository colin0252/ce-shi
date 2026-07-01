import SwiftUI
import Foundation
import CommonCrypto
import UIKit

//AES加密 固定密钥
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
        let iv = Data(repeating: UInt8(0), count: 16)
        var cryptor: CCCryptorRef?
        let alg = CCAlgorithm(kCCAlgorithmAES128)
        let pad = CCOption(kCCOptionPKCS7Padding)
        let mode = kCCModeCBC
        if isEncrypt {
            let rawData = Data(text.utf8)
            CCCryptorCreateWithMode(kCCEncrypt, mode, alg, pad, iv, keyData, nil, 0, nil, nil, 0, &cryptor)
            let up = CCCryptorUpdate(cryptor!, rawData, rawData.count)!
            let fin = CCCryptorFinal(cryptor!)!
            return (up+fin).base64EncodedString()
        } else {
            guard let rawData = Data(base64Encoded: text) else { return "解密失败" }
            CCCryptorCreateWithMode(kCCDecrypt, mode, alg, pad, iv, keyData, nil, 0, nil, nil, 0, &cryptor)
            let up = CCCryptorUpdate(cryptor!, rawData, rawData.count)!
            let fin = CCCryptorFinal(cryptor!)!
            return String(data: up+fin, encoding: .utf8) ?? "解密失败"
        }
    }
}

//账号数据模型
struct Account: Codable, Identifiable {
    let id = UUID()
    let openid: String
    let seecoon_token: String
    let quid: String
    let refresh_token: String
    let createTime: Date
}

//全局数据管理器
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

//二维码生成工具
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

//首页主界面
struct HomeView: View {
    @StateObject var dm = DataManager()
    @State var jumpPage: Int? = nil
    var body: some View {
        NavigationStack{
            VStack(spacing:30){
                Button(action:{jumpPage = 1}){
                    Text("A：三角洲扫码获取Token")
                        .font(.title)
                        .frame(width:300,height:80)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                Button(action:{jumpPage = 2}){
                    Text("B：账号Token管理")
                        .font(.title)
                        .frame(width:300,height:80)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                Button(action:{jumpPage = 3}){
                    Text("C：Token登录与解密工具")
                        .font(.title)
                        .frame(width:300,height:80)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .navigationDestination(item:$jumpPage){ page in
                if page == 1 { ScanView(dm:dm) }
                if page == 2 { TokenManageView(dm:dm) }
                if page == 3 { LoginDecryptView() }
            }
            .navigationTitle("三角洲行动工具箱")
        }
    }
}

//A页面：复刻三角洲扫码界面，本地生成二维码，跳转QQ授权
struct ScanView: View {
    @ObservedObject var dm:DataManager
    @Environment(\.dismiss) var dismiss
    @State var qrImage:UIImage = UIImage()
    @State var sessionKey = UUID().uuidString
    let baseUrl = "https://game.seecoon.com/h5/qqauth?session="
    
    func refreshCode(){
        sessionKey = UUID().uuidString
        let qrUrl = baseUrl + sessionKey
        qrImage = QRCodeGenerator.createQRCode(urlString:qrUrl)
        startPolling()
    }
    
    func startPolling(){
        Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { timer in
            let checkApi = URL(string:"https://game.seecoon.com/api/login/checkScan?session=\(sessionKey)")!
            URLSession.shared.dataTask(with: checkApi){ data,_,_ in
                guard let data = data else {return}
                let json = try! JSONSerialization.jsonObject(with: data) as! [String:Any]
                if let dataDic = json["data"] as? [String:Any]{
                    let acc = Account(
                        id: UUID(),
                        openid: dataDic["openid"] as! String,
                        seecoon_token: dataDic["seecoon_token"] as! String,
                        quid: dataDic["quid"] as! String,
                        refresh_token: dataDic["refresh_token"] as! String,
                        createTime: Date()
                    )
                    DispatchQueue.main.async {
                        dm.saveAccount(acc:acc)
                        refreshCode()
                    }
                    timer.invalidate()
                }
            }.resume()
        }
    }
    
    var body: some View {
        VStack(spacing:20){
            Button("← 返回首页"){dismiss()}
                .frame(maxWidth:.leading)
                .padding(.leading)
            Text("三角洲行动 移动端扫码登录")
                .font(.title)
            Text("使用QQ扫描下方二维码，跳转三角洲APP完成授权")
                .font(.subheadline).foregroundColor(.gray)
            Image(uiImage:qrImage)
                .resizable()
                .frame(width:260,height:260)
            Button("刷新二维码",action:refreshCode)
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .onAppear{
            refreshCode()
            //QQ拉起的时候识别标题为三角洲行动，不会拦截
            UIApplication.shared.open(URL(string:"mqqapi://")!)
        }
    }
}

//B页面 账号管理
struct TokenManageView: View {
    @ObservedObject var dm:DataManager
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack{
            Button("← 返回首页"){dismiss()}
                .frame(maxWidth:.leading)
                .padding(.leading)
            List(dm.accounts){acc in
                VStack(alignment:.leading){
                    Text("OpenID：\(acc.openid)")
                    Text("Token：\(acc.seecoon_token)")
                        .font(.system(size:8))
                    HStack{
                        Button("复制Token"){
                            UIPasteboard.general.string = acc.seecoon_token
                        }
                        Button("删除账号",role:.destructive){
                            dm.deleteAccount(id:acc.id)
                        }
                    }
                }
            }
        }
    }
}

//C页面 Token校验+唤起游戏+解密弹窗
struct LoginDecryptView: View {
    @Environment(\.dismiss) var dismiss
    @State var inputToken = ""
    @State var tipText = ""
    @State var showDecrypt = false
    @State var cipherText = ""
    @State var keyInput = ""
    @State var decryptResult = ""
    
    func checkToken(){
        let header:[String:String] = [
            "Authorization":"seecoon_token=\(inputToken)",
            "User-Agent":"SeecoonGame",
            "Content-Type":"application/json"
        ]
        var req = URLRequest(url:URL(string:"https://game.seecoon.com/api/user/checkLogin")!)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = header
        req.httpBody = "{}".data(using:.utf8)
        URLSession.shared.dataTask(with:req){ data,res,err in
            DispatchQueue.main.async {
                if let d = data,let json = try? JSONSerialization.jsonObject(with:d) as? [String:Any]{
                    let valid = json["data"] as? Bool ?? false
                    tipText = valid ? "✅ Token有效，可以一键登录" : "❌ Token失效"
                }else{
                    tipText = "网络异常"
                }
            }
        }.resume()
    }
    
    func openGame(){
        UIApplication.shared.open(URL(string:"seecoon://login?token=\(inputToken)")!)
    }
    
    var body: some View {
        VStack(spacing:15){
            Button("← 返回首页"){dismiss()}
                .frame(maxWidth:.leading)
                .padding(.leading)
            TextField("粘贴seecoon_token",text:$inputToken)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            Button("检测Token有效性",action:checkToken)
            Text(tipText)
            Button("唤起三角洲一键登录",action:openGame)
                .disabled(!tipText.contains("✅"))
            Button("🔐 密文解密工具"){
                showDecrypt = true
            }
            Spacer()
        }
        .sheet(isPresented:$showDecrypt){
            VStack(spacing:12){
                TextField("粘贴dat全部密文",text:$cipherText)
                TextField("输入密钥",text:$keyInput)
                Button("解密"){
                    decryptResult = AESHelper.customDecrypt(base64Str: cipherText, keyStr: keyInput)
                }
                TextEditor(text:$decryptResult)
            }.padding()
        }
        .padding()
    }
}

@main
struct DeltaApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}