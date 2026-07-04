import SwiftUI

// MARK: - 数据模型
struct GameAccount: Identifiable, Codable {
    let id: String
    let gameName: String
    let uid: String
    let username: String
    let loginTime: String
}

// MARK: - 游戏登录管理器
class GameLoginManager: ObservableObject {
    @Published var currentToken: String = ""
    @Published var isLoggedIn: Bool = false
    @Published var accounts: [GameAccount] = []
    @Published var message: String = ""
    @Published var messageType: MessageType = .info
    
    enum MessageType {
        case info, success, warning, error
    }
    
    private let userDefaults = UserDefaults.standard
    private let accountsKey = "game_accounts"
    
    init() {
        loadAccounts()
    }
    
    func setToken(_ token: String) {
        currentToken = token
        isLoggedIn = true
        showMessage("Token已设置", type: .success)
    }
    
    func copyToken() {
        guard !currentToken.isEmpty else {
            showMessage("请先获取Token", type: .warning)
            return
        }
        UIPasteboard.general.string = currentToken
        showMessage("Token已复制到剪贴板", type: .success)
    }
    
    func manualTokenInput(_ token: String) {
        if token.isEmpty {
            showMessage("请输入Token", type: .warning)
            return
        }
        setToken(token)
    }
    
    func loginGame(gameName: String, gameCode: String) {
        guard !currentToken.isEmpty else {
            showMessage("请先获取Token", type: .warning)
            return
        }
        
        showMessage("正在登录\(gameName)...", type: .info)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            
            let newAccount = GameAccount(
                id: UUID().uuidString,
                gameName: gameName,
                uid: "\(Int.random(in: 100000000...999999999))",
                username: "Player_\(Int.random(in: 1000...9999))",
                loginTime: self.getCurrentTimeString()
            )
            
            self.accounts.append(newAccount)
            self.saveAccounts()
            self.showMessage("\(gameName)登录成功！", type: .success)
        }
    }
    
    func copyAccountUID(_ uid: String) {
        UIPasteboard.general.string = uid
        showMessage("UID已复制到剪贴板", type: .success)
    }
    
    func deleteAccount(id: String) {
        accounts.removeAll { $0.id == id }
        saveAccounts()
        showMessage("账号已删除", type: .info)
    }
    
    func clearAllAccounts() {
        accounts.removeAll()
        saveAccounts()
        showMessage("所有账号已清空", type: .info)
    }
    
    private func saveAccounts() {
        if let encoded = try? JSONEncoder().encode(accounts) {
            userDefaults.set(encoded, forKey: accountsKey)
        }
    }
    
    private func loadAccounts() {
        if let data = userDefaults.data(forKey: accountsKey),
           let decoded = try? JSONDecoder().decode([GameAccount].self, from: data) {
            accounts = decoded
        }
    }
    
    private func showMessage(_ text: String, type: MessageType) {
        message = text
        messageType = type
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.message = ""
        }
    }
    
    private func getCurrentTimeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
    
    func generateQRCodeURL() -> String {
        return "https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=QQ_LOGIN"
    }
}

// MARK: - 主界面
struct ContentView: View {
    @StateObject private var loginManager = GameLoginManager()
    @State private var tokenInput: String = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 顶部标题
                HStack {
                    Text("游戏账号管理助手")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Spacer()
                    // 登录状态
                    HStack(spacing: 6) {
                        Circle()
                            .fill(loginManager.isLoggedIn ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(loginManager.isLoggedIn ? "已登录" : "未登录")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(Color(red: 0.12, green: 0.12, blue: 0.18))
                
                ScrollView {
                    VStack(spacing: 16) {
                        // 1. QQ扫码登录（首页主区域）
                        qrCodeSection
                        
                        // 2. Token管理
                        tokenSection
                        
                        // 3. 游戏登录
                        gameLoginSection
                        
                        // 4. 账号列表
                        accountListSection
                    }
                    .padding(16)
                }
                .background(Color(.systemGray6))
            }
            .ignoresSafeArea(.all)
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
    }
    
    // QQ扫码区域
    private var qrCodeSection: some View {
        VStack(spacing: 16) {
            Text("📱 QQ扫码登录")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(alignment: .center, spacing: 0) {
                // 二维码
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue, lineWidth: 2)
                        .frame(width: 180, height: 180)
                    
                    AsyncImage(url: URL(string: loginManager.generateQRCodeURL())) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 165, height: 165)
                    } placeholder: {
                        VStack(spacing: 8) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 50))
                                .foregroundColor(.blue)
                            Text("QQ二维码")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Spacer()
                
                // 说明文字
                VStack(alignment: .leading, spacing: 10) {
                    Label("打开手机QQ扫描二维码", systemImage: "1.circle.fill")
                    Label("在手机上确认授权登录", systemImage: "2.circle.fill")
                    Label("等待自动获取Token", systemImage: "3.circle.fill")
                    Label("Token自动填充到下方输入框", systemImage: "4.circle.fill")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Button(action: {}) {
                Label("刷新二维码", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
    
    // Token管理区域
    private var tokenSection: some View {
        VStack(spacing: 12) {
            Text("🔑 Token管理")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 8) {
                SecureField("输入Token...", text: $tokenInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 14))
                
                Button(action: { loginManager.copyToken() }) {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                
                Button(action: { loginManager.manualTokenInput(tokenInput) }) {
                    Label("确认", systemImage: "checkmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.green)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
    
    // 游戏登录区域
    private var gameLoginSection: some View {
        VStack(spacing: 12) {
            Text("🎮 游戏登录")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                gameButton(name: "三角洲行动", icon: "arrow.triangle.swap", color: .orange, code: "delta_force")
                gameButton(name: "暗区突围", icon: "shield.fill", color: .red, code: "dark_zone")
                gameButton(name: "和平精英", icon: "scope", color: .green, code: "peace_elite")
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
    
    private func gameButton(name: String, icon: String, color: Color, code: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(color)
                .frame(height: 36)
            
            Text(name)
                .font(.caption)
                .fontWeight(.medium)
            
            Button("🚀 登录") {
                loginManager.loginGame(gameName: name, gameCode: code)
            }
            .buttonStyle(.borderedProminent)
            .tint(color)
            .font(.caption2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08))
        .cornerRadius(12)
    }
    
    // 账号列表区域
    private var accountListSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("📋 已保存的账号")
                    .font(.headline)
                Spacer()
                if !loginManager.accounts.isEmpty {
                    Button(action: { loginManager.clearAllAccounts() }) {
                        Label("清空", systemImage: "trash")
                            .font(.caption)
                    }
                    .foregroundColor(.red)
                }
            }
            
            if loginManager.accounts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
                    Text("暂无账号，请先登录游戏")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ForEach(loginManager.accounts) { account in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.gameName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("UID: \(account.uid)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(account.loginTime)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Button(action: { loginManager.copyAccountUID(account.uid) }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                            
                            Button(action: { loginManager.deleteAccount(id: account.id) }) {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

// MARK: - App入口
@main
struct DeltaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea(.all)
        }
    }
}