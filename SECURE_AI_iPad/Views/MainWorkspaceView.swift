import SwiftUI

enum SidebarTab: String, CaseIterable, Identifiable {
    case pdf = "PDF"
    case ai = "100% AI"
    case verify = "Verify & Fix"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .pdf: return "doc.text.fill"
        case .ai: return "sparkles"
        case .verify: return "checkmark.shield.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct MainWorkspaceView: View {
    @EnvironmentObject var browser: EmbeddedBrowserStore
    @EnvironmentObject var automation: AutomationController
    @EnvironmentObject var license: LicenseService
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var savedLogins: SavedLoginStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: SidebarTab = .pdf
    @State private var showSidebar: Bool = true
    @State private var pendingAIPDFAttachment: AIAttachment? = nil
    @State private var showAddLoginSheet: Bool = false
    @State private var showWallpaperGallery: Bool = false
    @AppStorage("secure_ai_gemini_key") private var geminiApiKey: String = ""

    private var pal: AppThemePalette { theme.palette }

    var body: some View {
        GeometryReader { geo in
            let sidebarWidth = min(max(geo.size.width * 0.33, 310), 430)

            ZStack(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    if showSidebar {
                        sidebarPanel
                            .frame(width: sidebarWidth)
                            .background(
                                FrostedWallpaperBackdrop(
                                    palette: pal,
                                    style: theme.wallpaper,
                                    frosted: theme.frostedGlass,
                                    customKind: theme.customWallpaperKind,
                                    customURL: theme.customWallpaperURL,
                                    customFallbackURL: theme.customWallpaperFallbackURL,
                                    dimming: theme.wallpaperDimming,
                                    isActive: showSidebar && scenePhase == .active
                                )
                            )
                            .overlay(Rectangle().frame(width: 1).foregroundColor(pal.line.opacity(0.6)), alignment: .trailing)
                            .transition(.move(edge: .leading))
                    }

                    VStack(spacing: 0) {
                        BrowserToolbarView(
                            showSidebar: $showSidebar,
                            showAddLoginSheet: $showAddLoginSheet
                        )
                        WebViewRepresentable(store: browser)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(pal.bg)

                if automation.isRunning {
                    floatingAutomationHUD
                        .padding(.top, 92)
                        .padding(.trailing, 18)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        // Automatically bring back the 1/3 app window when automation completes or is stopped!
        .onChange(of: automation.isRunning) { running in
            if !running {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    showSidebar = true
                }
            }
        }
        .onChange(of: license.cloudGeminiKey) { newKey in
            if geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !newKey.isEmpty {
                geminiApiKey = newKey
            }
        }
        .sheet(isPresented: $showAddLoginSheet) {
            AddLoginIDSheet()
                .environmentObject(savedLogins)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showWallpaperGallery) {
            WallpaperGallerySheet()
                .environmentObject(theme)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                browser.restoreViewportAfterForeground()
            }
        }
        .task {
            await license.verifyOnLaunch()
        }
    }

    // MARK: - Left 1/3 Frosted Glass SECURE AI Panel
    private var sidebarPanel: some View {
        VStack(spacing: 0) {
            // Sleek Brand Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(pal.accent.opacity(0.22))
                        .frame(width: 34, height: 34)
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(pal.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("SECURE AI")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(pal.fg)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(license.isActivated ? SecureTheme.green : SecureTheme.amber)
                            .frame(width: 6, height: 6)
                        Text(license.isActivated ? "Cloud Active • v3.0.10" : "License Not Active")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(license.isActivated ? SecureTheme.green : SecureTheme.amber)
                    }
                }
                Spacer()
                Menu {
                    ForEach(SpeedPreset.allCases) { preset in
                        Button {
                            automation.speed = preset
                        } label: {
                            HStack {
                                Text("Speed \(preset.rawValue)")
                                if automation.speed == preset { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.needle.fill")
                        Text(automation.speed.rawValue)
                    }
                    .font(.system(size: 11.5, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(pal.card.opacity(0.75))
                    .foregroundColor(pal.accent)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(pal.line.opacity(0.7), lineWidth: 1))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            // Smooth Pill Tab Switcher
            HStack(spacing: 6) {
                ForEach(SidebarTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) { selectedTab = tab }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12.5, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 10.5, weight: .semibold))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? pal.accent.opacity(0.24) : pal.card.opacity(0.55))
                        .foregroundColor(selectedTab == tab ? pal.accent : pal.muted)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selectedTab == tab ? pal.accent : pal.line.opacity(0.5), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Divider().background(pal.line.opacity(0.5))

            Group {
                switch selectedTab {
                case .pdf:
                    PDFImportView(
                        onStartRequested: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                showSidebar = false
                            }
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 420_000_000)
                                automation.startAutomation(browser: browser)
                            }
                        },
                        onSendScannedPDFToAI: { att in
                            pendingAIPDFAttachment = att
                            selectedTab = .ai
                        },
                        onOpenSettings: {
                            selectedTab = .settings
                        }
                    )
                case .ai:
                    AI100GeneratorView(
                        geminiApiKey: $geminiApiKey,
                        incomingAttachment: $pendingAIPDFAttachment,
                        onEstimateReady: {
                            selectedTab = .pdf
                        }
                    )
                case .verify:
                    VerifyFixView(onStartRepairRequested: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            showSidebar = false
                        }
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 420_000_000)
                            automation.runRepairUnits(browser: browser)
                        }
                    })
                case .settings:
                    SettingsLicenseView(geminiApiKey: $geminiApiKey, showAddLoginSheet: $showAddLoginSheet, showWallpaperGallery: $showWallpaperGallery)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Floating Compact Top-Right Automation HUD (Visible While App Window Is Hidden)
    private var floatingAutomationHUD: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Step \(automation.completedSteps)/\(automation.totalSteps) • \(automation.speed.rawValue)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(pal.accent)
                Text(automation.currentStepLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(pal.fg)
                    .lineLimit(1)
                    .frame(maxWidth: 250, alignment: .leading)
                if let err = automation.lastErrorBanner {
                    Text(err)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(SecureTheme.amber)
                        .lineLimit(2)
                        .frame(maxWidth: 250, alignment: .leading)
                }
            }

            Button {
                automation.togglePause()
            } label: {
                Image(systemName: automation.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 13, weight: .bold))
                    .padding(9)
                    .background(SecureTheme.amber)
                    .foregroundColor(.black)
                    .cornerRadius(9)
            }

            Button {
                automation.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .bold))
                    .padding(9)
                    .background(SecureTheme.red)
                    .foregroundColor(.white)
                    .cornerRadius(9)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .background(pal.bg.opacity(0.85))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(pal.accent.opacity(0.85), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.42), radius: 14, x: 0, y: 5)
    }
}

/// Isolated 120Hz Browser Toolbar with Saved SECURE Logins menu & Chrome-style Zoom Controls
private struct BrowserToolbarView: View {
    @EnvironmentObject var browser: EmbeddedBrowserStore
    @EnvironmentObject var automation: AutomationController
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var savedLogins: SavedLoginStore

    @Binding var showSidebar: Bool
    @Binding var showAddLoginSheet: Bool
    @State private var addressDraft: String = "https://secure.dord.gov.in/"
    @State private var loginStatusToast: String? = nil

    private var pal: AppThemePalette { theme.palette }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { showSidebar.toggle() }
                } label: {
                    Image(systemName: showSidebar ? "sidebar.left" : "sidebar.squares.left")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(pal.accent)
                        .padding(7)
                        .background(pal.card)
                        .cornerRadius(8)
                }

                Button { browser.goBack() } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(browser.canGoBack ? pal.fg : pal.muted.opacity(0.4))
                        .padding(5)
                }
                .disabled(!browser.canGoBack)

                Button { browser.goForward() } label: {
                    Image(systemName: "chevron.right")
                        .foregroundColor(browser.canGoForward ? pal.fg : pal.muted.opacity(0.4))
                        .padding(5)
                }
                .disabled(!browser.canGoForward)

                Button { browser.reloadOrStop() } label: {
                    Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
                        .foregroundColor(pal.fg)
                        .padding(5)
                }

                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(pal.muted)
                        .font(.system(size: 12))
                    TextField("Enter SECURE URL or search Google...", text: $addressDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.URL)
                        .foregroundColor(pal.fg)
                        .font(.system(size: 12.5))
                        .submitLabel(.go)
                        .onSubmit { browser.navigate(input: addressDraft) }
                    if !addressDraft.isEmpty {
                        Button { addressDraft = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(pal.muted)
                                .font(.system(size: 12))
                        }
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(pal.card)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(pal.line, lineWidth: 1))

                Button("Go") {
                    browser.navigate(input: addressDraft)
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(SecureTheme.blue)
                .foregroundColor(.white)
                .cornerRadius(8)

                // Saved SECURE Logins One-Tap Auto-Fill Menu
                Menu {
                    if savedLogins.accounts.isEmpty {
                        Text("No saved SECURE logins yet")
                    } else {
                        ForEach(savedLogins.accounts) { acc in
                            Button {
                                Task {
                                    let msg = await browser.autoFillLogin(userId: acc.userId, password: acc.password)
                                    loginStatusToast = msg
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                        if loginStatusToast == msg { loginStatusToast = nil }
                                    }
                                }
                            } label: {
                                Label("\(acc.label) (\(acc.userId))", systemImage: "person.badge.key.fill")
                            }
                        }
                    }
                    Divider()
                    Button {
                        showAddLoginSheet = true
                    } label: {
                        Label("Add New SECURE Login ID...", systemImage: "plus.circle.fill")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "key.fill")
                        Text("Logins")
                    }
                    .font(.system(size: 11.5, weight: .bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(pal.accent.opacity(0.22))
                    .foregroundColor(pal.accent)
                    .cornerRadius(8)
                }

                // Chrome-Exact Live Zoom Controls (- 67% +)
                HStack(spacing: 2) {
                    Button { browser.zoomOut() } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                    }
                    Button { browser.resetZoom() } label: {
                        Text("\(Int(round(browser.zoomLevel * 100)))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 6)
                    }
                    Button { browser.zoomIn() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                    }
                }
                .foregroundColor(pal.fg)
                .background(pal.card)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(pal.line, lineWidth: 1))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(pal.bg)

            HStack(spacing: 8) {
                ForEach(QuickBookmark.defaults) { bm in
                    Button {
                        browser.navigate(input: bm.urlString)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: bm.icon).font(.system(size: 11))
                            Text(bm.title).font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(pal.card)
                        .foregroundColor(pal.fg)
                        .cornerRadius(6)
                    }
                }
                Spacer()
                if let toast = loginStatusToast {
                    Text(toast)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(pal.accent)
                } else if let est = automation.activeEstimate {
                    Text("Loaded: \(est.headings.count) H • \(est.totalItemCount) Items • \(est.lumpSums.count) LS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(SecureTheme.green)
                } else {
                    Text("1. Open SECURE  →  2. Upload PDF / AI  →  3. Press START")
                        .font(.system(size: 11))
                        .foregroundColor(pal.muted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(pal.side)

            if browser.isLoading {
                ProgressView(value: browser.estimatedProgress)
                    .tint(pal.accent)
                    .frame(height: 2)
            } else {
                Divider().background(pal.line)
            }
        }
        .onChange(of: browser.addressText) { newVal in
            addressDraft = newVal
        }
    }
}

/// Modal sheet to add a new saved SECURE Login ID (stored in iPadOS Keychain so it survives reinstalls)
struct AddLoginIDSheet: View {
    @EnvironmentObject var savedLogins: SavedLoginStore
    @EnvironmentObject var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var label: String = ""
    @State private var userId: String = ""
    @State private var password: String = ""

    private var pal: AppThemePalette { theme.palette }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account Details (Saved Securely in Keychain)") {
                    TextField("Label (e.g. Kawadpur JE / Surajgarha)", text: $label)
                    TextField("SECURE User ID (e.g. BH101710)", text: $userId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    SecureField("Password", text: $password)
                }
                Section {
                    Button("Save Login ID") {
                        savedLogins.add(label: label, userId: userId, password: password)
                        dismiss()
                    }
                    .disabled(userId.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                }
            }
            .navigationTitle("Add SECURE Login ID")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
