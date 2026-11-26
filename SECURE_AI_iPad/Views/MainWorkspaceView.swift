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

    @State private var selectedTab: SidebarTab = .pdf
    @State private var showSidebar: Bool = true
    @State private var pendingAIPDFAttachment: AIAttachment? = nil
    @AppStorage("secure_ai_gemini_key") private var geminiApiKey: String = ""

    private var pal: AppThemePalette { theme.palette }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                if showSidebar {
                    sidebarPanel
                        .frame(width: 345)
                        .background(pal.side)
                        .overlay(Rectangle().frame(width: 1).foregroundColor(pal.line), alignment: .trailing)
                }

                VStack(spacing: 0) {
                    BrowserToolbarView(showSidebar: $showSidebar)
                    WebViewRepresentable(store: browser)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(pal.bg)

            if automation.isRunning {
                floatingAutomationHUD
                    .padding(.top, 92)
                    .padding(.trailing, 18)
            }
        }
        .onChange(of: license.cloudGeminiKey) { newKey in
            if geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !newKey.isEmpty {
                geminiApiKey = newKey
            }
        }
        .task {
            await license.verifyOnLaunch()
        }
    }

    // MARK: - Left Control Panel
    private var sidebarPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(pal.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SECURE AI")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(pal.fg)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(license.isActivated ? SecureTheme.green : SecureTheme.amber)
                            .frame(width: 6, height: 6)
                        Text(license.isActivated ? "Cloud Active • v3.0.10" : "License Not Active")
                            .font(.system(size: 10.5))
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
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(pal.panel)
                    .foregroundColor(pal.accent)
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(pal.bg)

            HStack(spacing: 5) {
                ForEach(SidebarTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12.5, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 10.5, weight: .semibold))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(selectedTab == tab ? pal.accent.opacity(0.22) : pal.card)
                        .foregroundColor(selectedTab == tab ? pal.accent : pal.muted)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedTab == tab ? pal.accent : pal.line, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(pal.side)

            Divider().background(pal.line)

            Group {
                switch selectedTab {
                case .pdf:
                    PDFImportView(
                        onStartRequested: {
                            automation.startAutomation(browser: browser)
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
                    VerifyFixView()
                case .settings:
                    SettingsLicenseView(geminiApiKey: $geminiApiKey)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Floating Compact Top-Right Automation HUD
    private var floatingAutomationHUD: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Step \(automation.completedSteps)/\(automation.totalSteps) • \(automation.speed.rawValue)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(pal.accent)
                Text(automation.currentStepLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(pal.fg)
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .leading)
            }

            Button {
                automation.togglePause()
            } label: {
                Image(systemName: automation.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 13, weight: .bold))
                    .padding(8)
                    .background(SecureTheme.amber)
                    .foregroundColor(.black)
                    .cornerRadius(8)
            }

            Button {
                automation.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .bold))
                    .padding(8)
                    .background(SecureTheme.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(pal.bg.opacity(0.96))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(pal.accent, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 4)
    }
}

/// Isolated toolbar view so WKWebView progress updates only re-render this thin top strip (zero lag).
private struct BrowserToolbarView: View {
    @EnvironmentObject var browser: EmbeddedBrowserStore
    @EnvironmentObject var automation: AutomationController
    @EnvironmentObject var theme: ThemeManager

    @Binding var showSidebar: Bool
    @State private var addressDraft: String = "https://secure.dord.gov.in/"

    private var pal: AppThemePalette { theme.palette }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showSidebar.toggle() }
                } label: {
                    Image(systemName: showSidebar ? "sidebar.left" : "sidebar.squares.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(pal.accent)
                        .padding(7)
                        .background(pal.card)
                        .cornerRadius(8)
                }

                Button { browser.goBack() } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(browser.canGoBack ? pal.fg : pal.muted.opacity(0.4))
                        .padding(6)
                }
                .disabled(!browser.canGoBack)

                Button { browser.goForward() } label: {
                    Image(systemName: "chevron.right")
                        .foregroundColor(browser.canGoForward ? pal.fg : pal.muted.opacity(0.4))
                        .padding(6)
                }
                .disabled(!browser.canGoForward)

                Button { browser.reloadOrStop() } label: {
                    Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
                        .foregroundColor(pal.fg)
                        .padding(6)
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
                        .onSubmit {
                            browser.navigate(input: addressDraft)
                        }
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

                // Smooth CSS Zoom Controls
                HStack(spacing: 2) {
                    Button { browser.zoomOut() } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 6)
                    }
                    Button { browser.resetZoom() } label: {
                        Text("\(Int(round(browser.zoomLevel * 100)))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 6)
                    }
                    Button { browser.zoomIn() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 6)
                    }
                }
                .foregroundColor(pal.fg)
                .background(pal.card)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(pal.line, lineWidth: 1))

                Button {
                    browser.desktopMode.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: browser.desktopMode ? "desktopcomputer" : "ipad")
                        Text(browser.desktopMode ? "PC" : "iPad")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(browser.desktopMode ? SecureTheme.green.opacity(0.18) : pal.card)
                    .foregroundColor(browser.desktopMode ? SecureTheme.green : pal.muted)
                    .cornerRadius(8)
                }
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
                if let est = automation.activeEstimate {
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
