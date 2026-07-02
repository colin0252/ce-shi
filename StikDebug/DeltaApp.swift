import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - 主视图
struct ContentView: View {
    @StateObject private var viewModel = QRCodeViewModel()
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景渐变
                LinearGradient(
                    colors: [Color(.systemGroupedBackground), Color(.systemBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // 标题
                        headerView
                        
                        // 输入区域
                        inputSection
                        
                        // 纠错级别选择
                        correctionLevelPicker
                        
                        // 二维码预览
                        qrCodePreview
                        
                        // 操作按钮
                        actionButtons
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("二维码生成器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if #available(iOS 16.0, *) {
                        Menu {
                            Button(action: viewModel.clearAll) {
                                Label("清空重置", systemImage: "arrow.counterclockwise")
                            }
                            Button(action: viewModel.saveToPhotos) {
                                Label("保存到相册", systemImage: "square.and.arrow.down")
                            }
                            if let image = viewModel.qrImage {
                                ShareLink(item: Image(uiImage: image), preview: SharePreview("二维码", image: Image(uiImage: image))) {
                                    Label("分享", systemImage: "square.and.arrow.up")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .alert(viewModel.alertTitle, isPresented: $viewModel.showAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(viewModel.alertMessage)
            }
        }
    }
    
    // MARK: - 头部视图
    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 44))
                .foregroundStyle(.blue.gradient)
            Text("生成专属二维码")
                .font(.title2.bold())
            Text("支持文本、网址、Wi-Fi 信息等")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 12)
    }
    
    // MARK: - 输入区域
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("输入内容", systemImage: "text.quote")
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack(spacing: 12) {
                TextField("请输入文本、网址或任意内容", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .lineLimit(3...6)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                    )
                
                Button(action: viewModel.generateQRCode) {
                    Image(systemName: "qrcode")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - 纠错级别选择
    private var correctionLevelPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("纠错级别", systemImage: "shield.lefthalf.filled")
                .font(.headline)
            
            HStack(spacing: 10) {
                ForEach(QRCorrectionLevel.allCases, id: \.rawValue) { level in
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            viewModel.correctionLevel = level
                            if !viewModel.inputText.isEmpty {
                                viewModel.generateQRCode()
                            }
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(level.rawValue)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                            Text(level.description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(viewModel.correctionLevel == level ? Color.blue : Color(.systemBackground))
                        )
                        .foregroundColor(viewModel.correctionLevel == level ? .white : .primary)
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - 二维码预览
    private var qrCodePreview: some View {
        VStack(spacing: 12) {
            if let image = viewModel.qrImage {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
                    
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(20)
                        .contextMenu {
                            Button {
                                viewModel.saveToPhotos()
                            } label: {
                                Label("保存到相册", systemImage: "square.and.arrow.down")
                            }
                            Button {
                                viewModel.copyQRToClipboard()
                            } label: {
                                Label("复制二维码", systemImage: "doc.on.doc")
                            }
                            if #available(iOS 16.0, *) {
                                ShareLink(item: Image(uiImage: image), preview: SharePreview("二维码", image: Image(uiImage: image))) {
                                    Label("分享", systemImage: "square.and.arrow.up")
                                }
                            }
                        }
                }
                .frame(height: 300)
                .transition(.scale.combined(with: .opacity))
                
                // 尺寸调整滑块
                sizeSlider
            } else {
                emptyQRPlaceholder
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.qrImage != nil)
    }
    
    // MARK: - 尺寸滑块
    private var sizeSlider: some View {
        HStack(spacing: 12) {
            Image(systemName: "minus.magnifyingglass")
                .foregroundColor(.secondary)
            Slider(value: $viewModel.qrSize, in: 150...350, step: 10)
                .tint(.blue)
                .onChange(of: viewModel.qrSize) { newValue in
                    viewModel.generateQRCode()
                }
            Image(systemName: "plus.magnifyingglass")
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
    
    // MARK: - 空占位视图
    private var emptyQRPlaceholder: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color(.systemGray6))
            .frame(height: 300)
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("输入内容后点击生成按钮")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
    }
    
    // MARK: - 操作按钮
    private var actionButtons: some View {
        HStack(spacing: 16) {
            CustomActionButton(
                title: "保存相册",
                icon: "photo.on.rectangle",
                color: .green
            ) {
                viewModel.saveToPhotos()
            }
            .disabled(viewModel.qrImage == nil)
            .opacity(viewModel.qrImage == nil ? 0.5 : 1)
            
            CustomActionButton(
                title: "复制图片",
                icon: "doc.on.doc",
                color: .orange
            ) {
                viewModel.copyQRToClipboard()
            }
            .disabled(viewModel.qrImage == nil)
            .opacity(viewModel.qrImage == nil ? 0.5 : 1)
            
            CustomActionButton(
                title: "Wi-Fi",
                icon: "wifi",
                color: .purple
            ) {
                viewModel.generateWiFiQR()
            }
        }
    }
}

// MARK: - 自定义按钮样式
struct CustomActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3.bold())
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
            .foregroundColor(color)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 纠错级别枚举
enum QRCorrectionLevel: String, CaseIterable {
    case L = "L"  // 低 ~7%
    case M = "M"  // 中 ~15%
    case Q = "Q"  // 较高 ~25%
    case H = "H"  // 高 ~30%
    
    var description: String {
        switch self {
        case .L: return "7%"
        case .M: return "15%"
        case .Q: return "25%"
        case .H: return "30%"
        }
    }
}

// MARK: - ViewModel
@MainActor
class QRCodeViewModel: ObservableObject {
    @Published var inputText = ""
    @Published var qrImage: UIImage?
    @Published var correctionLevel: QRCorrectionLevel = .H
    @Published var qrSize: Double = 260
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    
    private let context = CIContext()
    private let qrFilter = CIFilter.qrCodeGenerator()
    
    func generateQRCode() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            withAnimation {
                qrImage = nil
            }
            return
        }
        
        let data = Data(inputText.utf8)
        qrFilter.message = data
        qrFilter.correctionLevel = correctionLevel.rawValue
        
        guard let ciImage = qrFilter.outputImage else { return }
        
        let scaleX = qrSize / ciImage.extent.size.width
        let scaleY = qrSize / ciImage.extent.size.height
        let transformed = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        if let cgImage = context.createCGImage(transformed, from: transformed.extent) {
            withAnimation {
                qrImage = UIImage(cgImage: cgImage)
            }
        }
    }
    
    func saveToPhotos() {
        guard let image = qrImage else {
            showAlert(title: "提示", message: "请先生成二维码")
            return
        }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        showAlert(title: "成功", message: "二维码已保存到相册")
    }
    
    func copyQRToClipboard() {
        guard let image = qrImage else {
            showAlert(title: "提示", message: "请先生成二维码")
            return
        }
        UIPasteboard.general.image = image
        showAlert(title: "成功", message: "二维码已复制到剪贴板")
    }
    
    func generateWiFiQR() {
        let alert = UIAlertController(
            title: "Wi-Fi 配置",
            message: "生成 Wi-Fi 二维码，扫码即可连接",
            preferredStyle: .alert
        )
        alert.addTextField { $0.placeholder = "Wi-Fi 名称 (SSID)" }
        alert.addTextField { $0.placeholder = "密码"; $0.isSecureTextEntry = true }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "生成", style: .default) { [weak self] _ in
            guard let self = self,
                  let ssid = alert.textFields?[0].text,
                  let password = alert.textFields?[1].text,
                  !ssid.isEmpty else { return }
            
            let wifiString = "WIFI:T:WPA;S:\(ssid);P:\(password);;"
            self.inputText = wifiString
            self.generateQRCode()
        })
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(alert, animated: true)
        }
    }
    
    func clearAll() {
        withAnimation {
            inputText = ""
            qrImage = nil
            correctionLevel = .H
            qrSize = 260
        }
    }
    
    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}

// MARK: - App 入口
@main
struct QRCodeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}