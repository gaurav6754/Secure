import SwiftUI
import UniformTypeIdentifiers

struct AI100GeneratorView: View {
    @EnvironmentObject var automation: AutomationController
    @StateObject private var speech = SpeechRecognizerService()

    @Binding var geminiApiKey: String
    @Binding var incomingAttachment: AIAttachment?
    let onEstimateReady: () -> Void

    @State private var promptText: String = ""
    @State private var selectedLangId: String = "en-IN"
    @State private var attachments: [AIAttachment] = []
    @State private var showFilePicker = false
    @State private var isGenerating = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("100% AI Estimate Generator")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(SecureTheme.fg)
                Text("Speak in English or any Indian language, or attach sample PDFs/site photos. Output is strictly English with official Bihar MGNREGA 54 SOR codes.")
                    .font(.system(size: 11))
                    .foregroundColor(SecureTheme.muted)

                HStack(spacing: 8) {
                    Picker("Voice Lang", selection: $selectedLangId) {
                        ForEach(VoiceLanguageOption.supported) { opt in
                            Text(opt.label).tag(opt.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(SecureTheme.card)
                    .cornerRadius(8)

                    Spacer()

                    Button {
                        speech.toggleRecording(localeIdentifier: selectedLangId) { liveText in
                            promptText = liveText
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.fill")
                            Text(speech.isRecording ? "Stop Mic" : "Mic (Speak)")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(speech.isRecording ? SecureTheme.red : SecureTheme.violet)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }

                if let speechErr = speech.errorMessage {
                    Text(speechErr)
                        .font(.system(size: 11))
                        .foregroundColor(SecureTheme.amber)
                }

                TextEditor(text: $promptText)
                    .frame(minHeight: 120)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(SecureTheme.card)
                    .foregroundColor(SecureTheme.fg)
                    .font(.system(size: 13))
                    .cornerRadius(9)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(SecureTheme.line, lineWidth: 1))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        presetChip("PCC Road 300 ft") {
                            promptText = "Generate a complete Bihar MGNREGA SECURE estimate for a 300 ft long, 10 ft wide PCC Road (M20 grade 150mm thick over 75mm brick soling and sand filling) with Display Board and Cess."
                        }
                        presetChip("RCC Drain 400 ft") {
                            promptText = "Generate a complete Bihar MGNREGA SECURE estimate for a 400 ft long pure RCC drain (internal width 0.60m, depth 0.60m, 150mm walls & base slab with RCC cover slab) using Bihar 54 SOR codes."
                        }
                        presetChip("Paver Block 500 ft") {
                            promptText = "Generate a complete Bihar MGNREGA SECURE estimate for a 500 ft long, 12 ft wide 60mm interlocking paver block road with brick edge wall, sand cushion, and Display Board."
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button {
                            showFilePicker = true
                        } label: {
                            Label("+ Files (PDF, Photo, Plan)", systemImage: "paperclip")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(SecureTheme.panel)
                                .foregroundColor(SecureTheme.fg)
                                .cornerRadius(8)
                        }
                        Spacer()
                        if !attachments.isEmpty {
                            Button("Clear") { attachments.removeAll() }
                                .font(.system(size: 11))
                                .foregroundColor(SecureTheme.red)
                        }
                    }

                    ForEach(attachments) { att in
                        HStack {
                            Image(systemName: "doc.fill").foregroundColor(SecureTheme.accent)
                            Text(att.fileName).font(.system(size: 11)).foregroundColor(SecureTheme.fg).lineLimit(1)
                            Spacer()
                            Text("\(att.data.count / 1024) KB").font(.system(size: 10)).foregroundColor(SecureTheme.muted)
                        }
                        .padding(6)
                        .background(SecureTheme.card)
                        .cornerRadius(6)
                    }
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(SecureTheme.red)
                }

                Button {
                    Task { await runGeneration() }
                } label: {
                    HStack(spacing: 8) {
                        if isGenerating {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isGenerating ? "Generating Estimate..." : "Generate SECURE Estimate")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating ? SecureTheme.panel : SecureTheme.accent)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
            }
            .padding(12)
        }
        .onAppear { consumeIncomingAttachment() }
        .onChange(of: incomingAttachment) { _ in consumeIncomingAttachment() }
        .sheet(isPresented: $showFilePicker) {
            DocumentPickerSheet(
                contentTypes: [.pdf, .png, .jpeg, .plainText, .item, .data],
                allowsMultipleSelection: true
            ) { urls in
                for url in urls {
                    if let data = try? Data(contentsOf: url) {
                        let ext = url.pathExtension.lowercased()
                        let mime = ext == "pdf" ? "application/pdf" : (ext == "png" ? "image/png" : (ext == "jpg" || ext == "jpeg" ? "image/jpeg" : "application/pdf"))
                        attachments.append(AIAttachment(fileName: url.lastPathComponent, mimeType: mime, data: data))
                    }
                }
            }
        }
    }

    private func consumeIncomingAttachment() {
        guard let att = incomingAttachment else { return }
        if !attachments.contains(where: { $0.fileName == att.fileName }) {
            attachments.append(att)
        }
        if promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            promptText = "Extract EVERY heading, Bihar SOR item code, measurement row (No, L, B, D, deductions), and lump sum from the attached estimate PDF accurately in English."
        }
        incomingAttachment = nil
    }

    private func presetChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(SecureTheme.card)
            .foregroundColor(SecureTheme.accent)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(SecureTheme.line, lineWidth: 1))
    }

    private func runGeneration() async {
        errorMessage = nil
        isGenerating = true
        defer { isGenerating = false }

        do {
            let est = try await GeminiAIService.shared.generateEstimate(
                prompt: promptText,
                attachments: attachments,
                apiKey: geminiApiKey
            )
            automation.activeEstimate = est
            automation.isVerifiedByUser = false
            automation.appendLog("✨ 100% AI generated '\(est.title)' (\(est.headings.count) headings, \(est.totalItemCount) items)")
            onEstimateReady()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
