import SwiftUI
import UIKit

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
    
    // 设置Token
    func setToken(_ token: String) {
        currentToken = token
        isLoggedIn = true
        showMessage("Token已设置", type: .success)
    }
    
    // 复制Token到剪贴板
    func copyToken() {
        guard !currentToken.isEmpty else {
            showMessage("请先获取Token", type: .warning)
            return
        }
        UIPasteboard.general.string = currentToken
        showMessage("Token已复制到剪贴板", type: .success)
    }
    
    // 登录游戏
    func loginGame(gameName: String, gameCode: String, completion: @escaping (Bool) -> Void) {
        guard !currentToken.isEmpty else {
            showMessage("请先获取Token", type: .warning)
            completion(false)
            return
        }
        
        showMessage("正在登录\(gameName)...", type: .info)
        
        // 模拟登录请求
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            
            // 模拟成功登录
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
            completion(true)
        }
    }
    
    // 复制账号UID
    func copyAccountUID(_ uid: String) {
        UIPasteboard.general.string = uid
        showMessage("UID已复制到剪贴板", type: .success)
    }
    
    // 删除账号
    func deleteAccount(id: String) {
        accounts.removeAll { $0.id == id }
        saveAccounts()
        showMessage("账号已删除", type: .info)
    }
    
    // 清空所有账号
    func clearAllAccounts() {
        guard !accounts.isEmpty else {
            showMessage("没有可删除的账号", type: .info)
            return
        }
        accounts.removeAll()
        saveAccounts()
        showMessage("所有账号已清空", type: .info)
    }
    
    // 保存账号到本地
    private func saveAccounts() {
        if let encoded = try? JSONEncoder().encode(accounts) {
            userDefaults.set(encoded, forKey: accountsKey)
        }
    }
    
    // 从本地加载账号
    private func loadAccounts() {
        if let data = userDefaults.data(forKey: accountsKey),
           let decoded = try? JSONDecoder().decode([GameAccount].self, from: data) {
            accounts = decoded
        }
    }
    
    // 显示消息
    private func showMessage(_ text: String, type: MessageType) {
        message = text
        messageType = type
        
        // 3秒后自动清除消息
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.message = ""
        }
    }
    
    private func getCurrentTimeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
    
    // 二维码生成URL（演示用）
    func generateQRCodeURL() -> String {
        return "https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=QQ_LOGIN_DEMO"
    }
    
    // 刷新二维码
    func refreshQRCode() {
        showMessage("二维码已刷新", type: .info)
    }
    
    // 手动输入Token
    func manualTokenInput(_ token: String) {
        if token.isEmpty {
            showMessage("请输入Token", type: .warning)
            return
        }
        setToken(token)
    }
}

// MARK: - 主界面
struct ContentView: View {
    @StateObject private var loginManager = GameLoginManager()
    @State private var tokenInput: String = ""
    @State private var showQRCode: Bool = true
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Token管理区域
                    tokenSection
                    
                    // QQ扫码区域
                    qrCodeSection
                    
                    // 游戏登录区域
                    gameLoginSection
                    
                    // 账号列表区域
                    accountListSection
                }
                .padding()
            }
            .navigationTitle("游戏账号管理助手")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(
                // 消息提示
                Group {
                    if !loginManager.message.isEmpty {
                        messageView
                    }
                }
            )
        }
    }
    
    // Token管理区域
    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🔑 Token管理")
                .font(.headline)
            
            HStack {
                SecureField("Token将自动填充或手动输入...", text: $tokenInput)
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
            
            HStack {
                Circle()
                    .fill(loginManager.isLoggedIn ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(loginManager.isLoggedIn ? "已登录" : "未登录")
                    .font(.caption)
                    .foregroundColor(loginManager.isLoggedIn ? .green : .red)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // QQ扫码区域
    private var qrCodeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("📱 QQ扫码登录")
                .font(.headline)
            
            HStack(alignment: .center, spacing: 20) {
                // 二维码占位图
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue, lineWidth: 2)
                        .frame(width: 150, height: 150)
                    
                    AsyncImage(url: URL(string: loginManager.generateQRCodeURL())) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 140, height: 140)
                    } placeholder: {
                        VStack {
                            Image(systemName: "qrcode")
                                .font(.system(size: 40))
                            Text("QQ二维码")
                                .font(.caption)
                        }
                        .foregroundColor(.gray)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("使用说明：")
                        .font(.subheadline)
                        .fontWeight(.bold)
                    
                    Text("1. 打开手机QQ扫描左侧二维码")
                    Text("2. 在手机上确认授权登录")
                    Text("3. 等待自动获取Token")
                    Text("4. Token将自动填充到输入框")
                    
                    Button(action: { loginManager.refreshQRCode() }) {
                        Label("刷新二维码", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 5)
                }
                .font(.caption)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // 游戏登录区域
    private var gameLoginSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🎮 游戏登录")
                .font(.headline)
            
            HStack(spacing: 20) {
                gameLoginButton(
                    gameName: "三角洲行动",
                    icon: "arrow.triangle.swap",
                    color: .orange
                ) {
                    loginManager.loginGame(gameName: "三角洲行动", gameCode: "delta_force") { _ in }
                }
                
                gameLoginButton(
                    gameName: "暗区突围",
                    icon: "shield.fill",
                    color: .red
                ) {
                    loginManager.loginGame(gameName: "暗区突围", gameCode: "dark_zone") { _ in }
                }
                
                gameLoginButton(
                    gameName: "和平精英",
                    icon: "scope",
                    color: .green
                ) {
                    loginManager.loginGame(gameName: "和平精英", gameCode: "peace_elite") { _ in }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // 游戏登录按钮
    private func gameLoginButton(gameName: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        VStack {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(color)
            Text(gameName)
                .font(.caption)
            Button("🚀 登录", action: action)
                .buttonStyle(.bordered)
                .tint(color)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .cornerRadius(10)
    }
    
    // 账号列表区域
    private var accountListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("📋 已保存的账号")
                    .font(.headline)
                Spacer()
                Button(action: { loginManager.clearAllAccounts() }) {
                    Label("清空所有", systemImage: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            if loginManager.accounts.isEmpty {
                HStack {
                    Spacer()
                    Text("暂无账号，请先登录游戏")
                        .foregroundColor(.gray)
                        .padding()
                    Spacer()
                }
            } else {
                ForEach(loginManager.accounts) { account in
                    accountCard(account)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // 账号卡片
    private func accountCard(_ account: GameAccount) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.gameName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("UID: \(account.uid)")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("登录时间: \(account.loginTime)")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Button(action: { loginManager.copyAccountUID(account.uid) }) {
                Label("复制", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            
            Button(action: { loginManager.deleteAccount(id: account.id) }) {
                Label("删除", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
    
    // 消息提示视图
    private var messageView: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: messageIcon)
                Text(loginManager.message)
                    .font(.subheadline)
            }
            .foregroundColor(.white)
            .padding()
            .background(messageColor)
            .cornerRadius(10)
            .shadow(radius: 5)
            .padding(.bottom, 20)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut, value: loginManager.message)
    }
    
    private var messageIcon: String {
        switch loginManager.messageType {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }
    
    private var messageColor: Color {
        switch loginManager.messageType {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

// MARK: - App入口
@main
struct DeltaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}