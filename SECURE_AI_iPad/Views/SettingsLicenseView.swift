import SwiftUI

struct SettingsLicenseView: View {
    @EnvironmentObject var browser: EmbeddedBrowserStore
    @EnvironmentObject var automation: AutomationController
    @EnvironmentObject var license: LicenseService
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var savedLogins: SavedLoginStore
    @Binding var geminiApiKey: String
    @Binding var showAddLoginSheet: Bool
    @Binding var showWallpaperGallery: Bool

    private var pal: AppThemePalette { theme.palette }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 1. Saved SECURE Login IDs (Persists Across Reinstalls in Keychain)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Saved SECURE Login IDs", systemImage: "person.badge.key.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(pal.fg)
                        Spacer()
                        Button {
                            showAddLoginSheet = true
                        } label: {
                            Label("Add", systemImage: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(pal.accent)
                                .foregroundColor(.white)
                                .cornerRadius(7)
                        }
                    }

                    if savedLogins.accounts.isEmpty {
                        Text("Save multiple SECURE User IDs here so you can auto-fill login in 1 tap from the browser toolbar.")
                            .font(.system(size: 11))
                            .foregroundColor(pal.muted)
                    } else {
                        ForEach(savedLogins.accounts) { acc in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(acc.label)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(pal.fg)
                                    Text(acc.userId)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundColor(pal.muted)
                                }
                                Spacer()
                                Button("Fill") {
                                    Task { _ = await browser.autoFillLogin(userId: acc.userId, password: acc.password) }
                                }
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(SecureTheme.blue)
                                .foregroundColor(.white)
                                .cornerRadius(6)

                                Button {
                                    savedLogins.delete(acc)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundColor(SecureTheme.red)
                                        .padding(4)
                                }
                            }
                            .padding(8)
                            .background(pal.bg.opacity(0.6))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(11)
                .background(pal.card.opacity(0.82))
                .cornerRadius(11)
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(pal.line.opacity(0.7), lineWidth: 1))

                // 2. Appearance, Frosted Glass & Wallpapers (Ported from PC ui_theme.py)
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Label("Appearance, Glass & Wallpapers", systemImage: "paintpalette.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(pal.fg)
                        Spacer()
                        Text(pal.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(pal.accent)
                    }

                    Toggle(isOn: $theme.frostedGlass) {
                        Text("Frosted Glass Effect")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(pal.fg)
                    }
                    .tint(pal.accent)

                    Picker("Wallpaper", selection: $theme.wallpaper) {
                        ForEach(WallpaperStyle.allCases) { wp in
                            Text(wp.rawValue).tag(wp)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: theme.wallpaper) { _ in
                        if theme.customWallpaperKind != .none {
                            theme.clearCustomWallpaper()
                        }
                    }

                    // HD Photo & 120Hz Live MP4 Wallpaper Gallery Launcher
                    Button {
                        showWallpaperGallery = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: theme.customWallpaperKind == .live ? "play.rectangle.fill" : "photo.on.rectangle.angled")
                                .font(.system(size: 13, weight: .bold))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("HD & Live MP4 Wallpapers")
                                    .font(.system(size: 12, weight: .bold))
                                Text(theme.customWallpaperKind == .none ? "Browse 129 Live MP4 + 250+ HD Photos (120Hz)" : "Active: \(theme.customWallpaperTitle)")
                                    .font(.system(size: 10))
                                    .opacity(0.88)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(
                            LinearGradient(
                                colors: [pal.accent, pal.orb1],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(9)
                    }

                    if theme.customWallpaperKind != .none {
                        HStack(spacing: 8) {
                            Text("Dim")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(pal.muted)
                            Slider(value: $theme.wallpaperDimming, in: 0.10...0.75, step: 0.02)
                                .tint(pal.accent)
                            Button("Clear") {
                                theme.clearCustomWallpaper()
                            }
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(SecureTheme.red)
                        }
                        .padding(.horizontal, 4)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                        ForEach(AppThemePalette.all) { item in
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    theme.currentId = item.id
                                }
                            } label: {
                                HStack(spacing: 7) {
                                    Circle()
                                        .fill(item.accent)
                                        .frame(width: 14, height: 14)
                                        .overlay(Circle().stroke(item.bg, lineWidth: 2))
                                    Text(item.name)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(item.fg)
                                        .lineLimit(1)
                                    Spacer()
                                    if theme.currentId == item.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(item.accent)
                                    }
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 8)
                                .background(item.bg)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(theme.currentId == item.id ? item.accent : item.line, lineWidth: theme.currentId == item.id ? 1.5 : 1)
                                )
                            }
                        }
                    }
                }
                .padding(11)
                .background(pal.card.opacity(0.82))
                .cornerRadius(11)
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(pal.line.opacity(0.7), lineWidth: 1))

                // 3. Cloud License Activation (Keychain Persistent + Syncs Gemini & Claude Keys)
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("SECURE AI Cloud License")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(pal.fg)
                        Spacer()
                        Text(license.isActivated ? "CLOUD ACTIVE" : "NOT ACTIVATED")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(license.isActivated ? SecureTheme.green.opacity(0.2) : SecureTheme.red.opacity(0.2))
                            .foregroundColor(license.isActivated ? SecureTheme.green : SecureTheme.red)
                            .cornerRadius(6)
                    }

                    Text("Saved in Keychain (survives reinstalls) and synced with your PC License Manager & AI keys.")
                        .font(.system(size: 10.5))
                        .foregroundColor(pal.muted)

                    TextField("License Key (e.g. LM-XXXX-XXXX-XXXX-XXXX)", text: $license.licenseKey)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                        .font(.system(size: 12, design: .monospaced))

                    Button {
                        Task { await license.activateLicense() }
                    } label: {
                        HStack(spacing: 6) {
                            if license.isChecking { ProgressView().tint(.white) }
                            Text(license.isChecking ? "Syncing with Cloud Database..." : "Activate & Sync Cloud Keys")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(pal.accent)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(license.isChecking)

                    Text(license.statusMessage)
                        .font(.system(size: 11))
                        .foregroundColor(license.isActivated ? SecureTheme.green : SecureTheme.amber)

                    if !license.cloudGeminiKey.isEmpty || !license.cloudAnthropicKey.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill").foregroundColor(SecureTheme.green)
                            Text("Synced from Admin: \(license.cloudGeminiKey.isEmpty ? "" : "Gemini ") \(license.cloudAnthropicKey.isEmpty ? "" : "Claude")")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(SecureTheme.green)
                        }
                    }

                    Text("Stable Device ID: \(license.deviceId.prefix(16))... (\(license.osInfo))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(pal.muted)
                }
                .padding(11)
                .background(pal.card.opacity(0.82))
                .cornerRadius(11)
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(pal.line.opacity(0.7), lineWidth: 1))

                // 4. Optional Manual Gemini API Key Override
                VStack(alignment: .leading, spacing: 6) {
                    Text("Custom Gemini API Key (Optional Override)")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(pal.fg)
                    SecureField("Auto-synced from License Manager (or paste AIza...)", text: $geminiApiKey)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
                .padding(11)
                .background(pal.card.opacity(0.82))
                .cornerRadius(11)
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(pal.line.opacity(0.7), lineWidth: 1))

                // 5. Live Automation Log Console
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Live Automation Log")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(pal.fg)
                        Spacer()
                        Button("Clear") { automation.logs.removeAll() }
                            .font(.system(size: 11))
                            .foregroundColor(pal.muted)
                    }
                    if automation.logs.isEmpty {
                        Text("No logs yet. Load an estimate and press START.")
                            .font(.system(size: 11))
                            .foregroundColor(pal.muted)
                    } else {
                        ForEach(automation.logs.prefix(40), id: \.self) { line in
                            Text(line)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(pal.fg.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(11)
                .background(pal.card.opacity(0.82))
                .cornerRadius(11)
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(pal.line.opacity(0.7), lineWidth: 1))
            }
            .padding(12)
        }
    }
}
