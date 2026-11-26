import SwiftUI
import UniformTypeIdentifiers

struct PDFImportView: View {
    @EnvironmentObject var automation: AutomationController
    @EnvironmentObject var license: LicenseService
    @EnvironmentObject var theme: ThemeManager

    @State private var showDocPicker = false
    @State private var isParsingPDF = false
    @State private var importError: String? = nil
    @State private var lastPickedPDF: AIAttachment? = nil
    @State private var expandedItemIDs: Set<UUID> = []

    @State private var showScaleSheet = false
    @State private var oldLengthText = ""
    @State private var newLengthText = ""

    let onStartRequested: () -> Void
    let onSendScannedPDFToAI: (AIAttachment) -> Void
    let onOpenSettings: () -> Void

    private var pal: AppThemePalette { theme.palette }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !license.isActivated {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("License Activation Required")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(SecureTheme.amber)
                        Text("Activate your SECURE AI key in Settings so it syncs with your Cloud License Manager.")
                            .font(.system(size: 11))
                            .foregroundColor(pal.muted)
                        Button("Open License Settings") {
                            onOpenSettings()
                        }
                        .font(.system(size: 11.5, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(SecureTheme.amber)
                        .foregroundColor(.black)
                        .cornerRadius(7)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SecureTheme.amber.opacity(0.12))
                    .cornerRadius(9)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(SecureTheme.amber.opacity(0.5), lineWidth: 1))
                }

                // Step 1: Import PDF
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Load Estimate PDF")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(pal.fg)

                    HStack(spacing: 8) {
                        Button {
                            showDocPicker = true
                        } label: {
                            HStack(spacing: 6) {
                                if isParsingPDF {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "doc.badge.plus")
                                }
                                Text(isParsingPDF ? "Parsing PDF..." : "Upload PDF from Files")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(pal.accent)
                            .foregroundColor(.white)
                            .cornerRadius(9)
                        }
                        .disabled(isParsingPDF)

                        if automation.activeEstimate != nil {
                            Button {
                                showScaleSheet.toggle()
                            } label: {
                                Label("Scale L", systemImage: "ruler")
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 10)
                                    .background(pal.panel)
                                    .foregroundColor(pal.fg)
                                    .cornerRadius(9)
                            }
                        }
                    }

                    if showScaleSheet, let est = automation.activeEstimate {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Proportional Length Scaling (preserves headings, SOR codes & B/D)")
                                .font(.system(size: 11))
                                .foregroundColor(pal.muted)
                            HStack(spacing: 8) {
                                TextField("Old L (400)", text: $oldLengthText)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                Text("→").foregroundColor(pal.muted)
                                TextField("New L (500)", text: $newLengthText)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                Button("Apply") {
                                    if let o = Double(oldLengthText), let n = Double(newLengthText), o > 0, n > 0 {
                                        automation.activeEstimate = est.scaledByLength(from: o, to: n)
                                        showScaleSheet = false
                                    }
                                }
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(SecureTheme.blue)
                                .foregroundColor(.white)
                                .cornerRadius(7)
                            }
                        }
                        .padding(10)
                        .background(pal.card)
                        .cornerRadius(9)
                    }

                    if let err = importError {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundColor(SecureTheme.red)
                    }
                }

                // Step 2: Expandable PC-Style Estimate Preview
                if let est = automation.activeEstimate {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(est.title.isEmpty ? est.sourceName : est.title)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(pal.fg)
                                    .lineLimit(2)
                                Text("\(est.headings.count) Headings • \(est.totalItemCount) Items • \(est.totalMeasurementCount) Meas • \(est.lumpSums.count) LS")
                                    .font(.system(size: 11))
                                    .foregroundColor(pal.muted)
                            }
                            Spacer()
                            if est.estimatedGrandTotal > 0 {
                                Text("₹\(formatIndian(est.estimatedGrandTotal))")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(SecureTheme.green)
                            }
                        }
                        .padding(10)
                        .background(pal.card)
                        .cornerRadius(9)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(pal.line, lineWidth: 1))

                        if est.headings.isEmpty, let pdfAtt = lastPickedPDF {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("This PDF looks scanned or uses a custom table format. Send it to 100% AI Vision to extract all headings, SOR codes, and measurements automatically.")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(SecureTheme.amber)
                                Button {
                                    onSendScannedPDFToAI(pdfAtt)
                                } label: {
                                    Label("Extract This PDF with 100% AI Vision", systemImage: "sparkles")
                                        .font(.system(size: 12, weight: .bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background(SecureTheme.violet)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                            }
                            .padding(10)
                            .background(pal.card)
                            .cornerRadius(9)
                        }

                        ForEach(Array(est.headings.enumerated()), id: \.element.id) { hi, heading in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("H\(hi + 1). \(heading.text)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(pal.accent)

                                ForEach(heading.items) { item in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Button {
                                            if expandedItemIDs.contains(item.id) {
                                                expandedItemIDs.remove(item.id)
                                            } else {
                                                expandedItemIDs.insert(item.id)
                                            }
                                        } label: {
                                            HStack(alignment: .center, spacing: 6) {
                                                Image(systemName: expandedItemIDs.contains(item.id) ? "chevron.down" : "chevron.right")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundColor(pal.muted)
                                                Text(item.code)
                                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                    .foregroundColor(pal.fg)
                                                Spacer()
                                                Text("\(item.measurements.count) rows • \(String(format: "%.2f", item.totalQty)) \(item.unit)")
                                                    .font(.system(size: 10.5))
                                                    .foregroundColor(pal.muted)
                                            }
                                        }

                                        if expandedItemIDs.contains(item.id) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                ForEach(item.measurements) { m in
                                                    HStack(spacing: 4) {
                                                        if m.isDeduction {
                                                            Text("DED")
                                                                .font(.system(size: 8.5, weight: .bold))
                                                                .padding(.horizontal, 4)
                                                                .padding(.vertical, 1)
                                                                .background(SecureTheme.red.opacity(0.2))
                                                                .foregroundColor(SecureTheme.red)
                                                                .cornerRadius(3)
                                                        }
                                                        Text(m.desc.isEmpty ? "Row" : m.desc)
                                                            .font(.system(size: 10))
                                                            .foregroundColor(pal.fg.opacity(0.85))
                                                            .lineLimit(1)
                                                        Spacer()
                                                        Text("\(m.no)×\(m.l.isEmpty ? "-" : m.l)×\(m.b.isEmpty ? "-" : m.b)×\(m.d.isEmpty ? "-" : m.d) = \(String(format: "%.2f", m.computedQty))")
                                                            .font(.system(size: 9.5, design: .monospaced))
                                                            .foregroundColor(pal.muted)
                                                    }
                                                }
                                            }
                                            .padding(.leading, 14)
                                            .padding(.top, 2)
                                        }
                                    }
                                }
                            }
                            .padding(9)
                            .background(pal.card)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(pal.line.opacity(0.7), lineWidth: 1))
                        }

                        if !est.lumpSums.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("LUMP SUMS (\(est.lumpSums.count))")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(SecureTheme.amber)
                                ForEach(est.lumpSums) { ls in
                                    HStack {
                                        Text(ls.description.isEmpty ? ls.type : ls.description)
                                            .font(.system(size: 11))
                                            .foregroundColor(pal.fg)
                                        Spacer()
                                        Text("₹\(ls.amount)")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(SecureTheme.amber)
                                    }
                                }
                            }
                            .padding(9)
                            .background(pal.card)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(pal.line.opacity(0.7), lineWidth: 1))
                        }
                    }

                    // Step 3: Verify & START
                    if !est.headings.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $automation.isVerifiedByUser) {
                                Text("I have opened the empty SECURE estimate page on the right and verified the rows above.")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(pal.fg)
                            }
                            .tint(SecureTheme.green)

                            let canStart = license.isActivated && automation.isVerifiedByUser && !automation.isRunning
                            Button {
                                onStartRequested()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: automation.isRunning ? "hourglass" : "play.fill")
                                    Text(automation.isRunning ? "RUNNING ON SECURE..." : "START AUTO-ENTRY IN BROWSER")
                                }
                                .font(.system(size: 13.5, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(canStart ? SecureTheme.green : pal.panel)
                                .foregroundColor(canStart ? .black : pal.muted)
                                .cornerRadius(10)
                            }
                            .disabled(!canStart)
                        }
                        .padding(.top, 4)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.up.doc")
                            .font(.system(size: 28))
                            .foregroundColor(pal.muted)
                        Text("Upload a SECURE Estimate PDF or switch to the 100% AI tab to generate one.")
                            .font(.system(size: 12))
                            .foregroundColor(pal.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(pal.card.opacity(0.6))
                    .cornerRadius(10)
                }
            }
            .padding(12)
        }
        .sheet(isPresented: $showDocPicker) {
            DocumentPickerSheet(
                contentTypes: [.pdf, .item, .data],
                allowsMultipleSelection: false
            ) { urls in
                guard let url = urls.first else { return }
                handlePickedPDF(url)
            }
        }
    }

    private func handlePickedPDF(_ url: URL) {
        isParsingPDF = true
        importError = nil
        let fileName = url.lastPathComponent
        Task.detached(priority: .userInitiated) {
            do {
                let data = try Data(contentsOf: url)
                let parsed = try PDFEstimateParser.shared.parsePDFData(data, sourceName: fileName)
                let att = AIAttachment(fileName: fileName, mimeType: "application/pdf", data: data)
                await MainActor.run {
                    lastPickedPDF = att
                    automation.activeEstimate = parsed
                    automation.isVerifiedByUser = false
                    isParsingPDF = false
                    automation.appendLog("Loaded PDF: \(fileName) (\(parsed.headings.count) H, \(parsed.totalItemCount) items, \(parsed.lumpSums.count) LS)")
                }
            } catch {
                await MainActor.run {
                    isParsingPDF = false
                    importError = "Could not read PDF: \(error.localizedDescription)"
                }
            }
        }
    }

    private func formatIndian(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_IN")
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value.rounded()))"
    }
}
