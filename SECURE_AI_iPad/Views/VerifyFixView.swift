import SwiftUI

struct VerifyFixView: View {
    @EnvironmentObject var browser: EmbeddedBrowserStore
    @EnvironmentObject var automation: AutomationController
    @State private var isScanning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Verify & Fix Error")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(SecureTheme.fg)

                Text("Compares your loaded PDF or AI estimate against the SECURE draft currently open in the built-in browser. Any mismatched or extra item is repaired using Delete & Re-Add (with automatic SweetAlert2 confirmation).")
                    .font(.system(size: 11))
                    .foregroundColor(SecureTheme.muted)

                Button {
                    Task {
                        isScanning = true
                        await automation.verifyAgainstLivePortal(browser: browser)
                        isScanning = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isScanning {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "magnifyingglass.circle.fill")
                        }
                        Text(isScanning ? "Scanning SECURE Page..." : "Scan Open SECURE Estimate")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(SecureTheme.blue)
                    .foregroundColor(.white)
                    .cornerRadius(9)
                }
                .disabled(automation.activeEstimate == nil || isScanning || automation.isRunning)

                if automation.activeEstimate == nil {
                    Text("Load an estimate in the PDF or 100% AI tab first.")
                        .font(.system(size: 12))
                        .foregroundColor(SecureTheme.amber)
                }

                if !automation.mismatches.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Detected Mismatches (\(automation.mismatches.count))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(SecureTheme.amber)

                        ForEach(automation.mismatches) { mm in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mm.category.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(mm.category.contains("Extra") ? SecureTheme.red : SecureTheme.amber)
                                Text(mm.summary)
                                    .font(.system(size: 12))
                                    .foregroundColor(SecureTheme.fg)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(9)
                            .background(SecureTheme.card)
                            .cornerRadius(8)
                        }

                        Button {
                            automation.runRepairUnits(browser: browser)
                        } label: {
                            Label("Auto-Fix Errors (Delete & Re-Add)", systemImage: "wrench.and.screwdriver.fill")
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(SecureTheme.green)
                                .foregroundColor(.black)
                                .cornerRadius(10)
                        }
                        .disabled(automation.isRunning)
                    }
                } else if automation.activeEstimate != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(SecureTheme.green)
                        Text("No unresolved mismatches queued.")
                            .font(.system(size: 12))
                            .foregroundColor(SecureTheme.muted)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SecureTheme.card.opacity(0.6))
                    .cornerRadius(8)
                }
            }
            .padding(14)
        }
    }
}
