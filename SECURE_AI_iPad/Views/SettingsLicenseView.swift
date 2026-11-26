import SwiftUI

struct SettingsLicenseView: View {
    @EnvironmentObject var browser: EmbeddedBrowserStore
    @EnvironmentObject var automation: AutomationController
    @EnvironmentObject var license: LicenseService
    @EnvironmentObject var theme: ThemeManager
    @Binding var geminiApiKey: String

    private var pal: AppThemePalette { theme.palette }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Appearance & Themes (Ported from PC ui_theme.py)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Appearance & Themes", systemImage: "paintpalette.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(pal.fg)
                        Spacer()
                        Text(pal.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(pal.accent)
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
                .padding(10)
                .background(pal.card)
                .cornerRadius(9)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(pal.line, lineWidth: 1))

                // Google Gemini API Key
                VStack(alignment: .leading, spacing: 6) {
                    Text("Google Gemini API Key (100% AI)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(pal.fg)

                    SecureField("Paste AIza... key here", text: $geminiApiKey)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    Button {
                        browser.navigate(input: "https://aistudio.google.com/apikey")
                    } label: {
                        Label("Get Free Gemini API Key in Browser", systemImage: "key.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(pal.accent)
                    }
                }
                .padding(10)
                .background(pal.card)
                .cornerRadius(9)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(pal.line, lineWidth: 1))

                // Cloud License Activation
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

                    Text("Connected to the same MongoDB Atlas Cloud Database as your PC License Manager.")
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
                            if license.isChecking {
                                ProgressView().tint(.white)
                            }
                            Text(license.isChecking ? "Syncing with Cloud Database..." : "Activate & Sync with Cloud")
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

                    if !license.customerName.isEmpty || !license.planName.isEmpty {
                        Text("Customer: \(license.customerName.isEmpty ? "-" : license.customerName) • Plan: \(license.planName)")
                            .font(.system(size: 10.5))
                            .foregroundColor(pal.fg)
                    }

                    DisclosureGroup("Cloud Database URI (Advanced)") {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("mongodb+srv://... or https://...", text: $license.serverURL)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .font(.system(size: 11))
                            Button("Restore Default SECURE AI Cloud DB") {
                                license.serverURL = LicenseService.defaultCloudMongoURI
                            }
                            .font(.system(size: 11))
                            .foregroundColor(pal.accent)
                        }
                        .padding(.top, 4)
                    }
                    .font(.system(size: 11))
                    .foregroundColor(pal.muted)

                    Text("Device ID: \(license.deviceId.prefix(16))... (\(license.osInfo))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(pal.muted)
                }
                .padding(10)
                .background(pal.card)
                .cornerRadius(9)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(pal.line, lineWidth: 1))

                // Live Automation Log Console
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
                .padding(10)
                .background(pal.card)
                .cornerRadius(9)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(pal.line, lineWidth: 1))
            }
            .padding(12)
        }
    }
}
