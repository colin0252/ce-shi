import SwiftUI

@main
struct DeltaLoginApp: App {
    @StateObject private var tokenManager = TokenManager()

    var body: some Scene {
        WindowGroup {
            NavigationView {
                ContentView()
                    .environmentObject(tokenManager)
            }
            .navigationViewStyle(.stack)
            .ignoresSafeArea(.all)          // 关键：全屏显示
            .onOpenURL { url in
                handleIncomingURL(url, tokenManager: tokenManager)
            }
        }
    }

    private func handleIncomingURL(_ url: URL, tokenManager: TokenManager) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "mqq" else { return }
        if let callback = components.queryItems?.first(where: { $0.name == "callback" })?.value {
            tokenManager.callbackScheme = callback
        }
        tokenManager.pendingAuth = true
    }
}

// MARK: - Token 管理
class TokenManager: ObservableObject {
    @Published var savedToken = ""
    @Published var pendingAuth = false
    @Published var callbackScheme = ""

    private let tokenKey = "com.delta.login.token"

    init() {
        savedToken = UserDefaults.standard.string(forKey: tokenKey) ?? ""
    }

    func saveToken(_ token: String) {
        savedToken = token
        UserDefaults.standard.set(token, forKey: tokenKey)
    }
}

// MARK: - 主界面
struct ContentView: View {
    @EnvironmentObject var tokenManager: TokenManager
    @State private var inputToken = ""
    @State private var showSaveSuccess = false
    @State private var loginSuccess = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                if tokenManager.pendingAuth {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("三角洲行动请求 QQ 登录")
                            .font(.headline)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(10)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("登录 Token")
                        .font(.subheadline).bold()
                    TextField("请输入或粘贴 Token", text: $inputToken)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .padding(.horizontal)

                HStack(spacing: 16) {
                    Button {
                        guard !inputToken.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        tokenManager.saveToken(inputToken)
                        inputToken = ""
                        showSaveSuccess = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showSaveSuccess = false }
                    } label: {
                        Label("保存 Token", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        guard !tokenManager.savedToken.isEmpty else { return }
                        performLogin()
                    } label: {
                        Label("登录游戏", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(tokenManager.savedToken.isEmpty)
                }
                .padding(.horizontal)

                if !tokenManager.savedToken.isEmpty {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(.green)
                        Text("已保存 Token：\(tokenManager.savedToken.prefix(8))...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if showSaveSuccess {
                    Text("Token 保存成功")
                        .foregroundColor(.green)
                }

                if loginSuccess {
                    Text("已尝试回跳至三角洲，请返回游戏")
                        .foregroundColor(.blue)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Delta 登录助手")
        }
        .animation(.easeInOut, value: showSaveSuccess)
        .animation(.easeInOut, value: loginSuccess)
    }

    private func performLogin() {
        let callback = tokenManager.callbackScheme
        guard !callback.isEmpty else {
            loginSuccess = true
            tokenManager.pendingAuth = false
            return
        }

        var components = URLComponents()
        components.scheme = callback
        components.host = "oauth"
        components.queryItems = [
            URLQueryItem(name: "access_token", value: tokenManager.savedToken),
            URLQueryItem(name: "openid", value: "delta_fake_openid"),
            URLQueryItem(name: "expires_in", value: "7200")
        ]

        if let url = components.url {
            UIApplication.shared.open(url) { success in
                if success {
                    loginSuccess = true
                    tokenManager.pendingAuth = false
                }
            }
        }
    }
}