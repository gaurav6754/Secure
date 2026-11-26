import Foundation
import UniformTypeIdentifiers

struct AIAttachment: Identifiable, Hashable {
    let id = UUID()
    let fileName: String
    let mimeType: String
    let data: Data
}

/// 100% AI Estimate Generator powered by Google Gemini API (gemini-2.5-flash)
/// Grounded in the bundled 605-item Bihar MGNREGA SOR catalog (`official_54_catalog.json`).
final class GeminiAIService {
    static let shared = GeminiAIService()
    private init() {}

    func generateEstimate(
        prompt: String,
        attachments: [AIAttachment],
        apiKey: String
    ) async throws -> EstimateDocument {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw NSError(domain: "GeminiAIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Please enter your free Google Gemini API key in Settings first."])
        }

        let catalogSummary = buildRelevantCatalogContext(for: prompt)
        let systemInstruction = """
        You are SECURE AI, a senior Bihar Gram Panchayat / MGNREGA Civil Engineering Estimation Engine.
        CRITICAL RULES:
        1. Output STRICTLY in ENGLISH only, even if the user prompt is in Hindi, Bhojpuri, Maithili, Bengali, or any Indian language.
        2. Return ONLY valid raw JSON (no markdown fences, no commentary) matching this exact schema:
        {
          "title": "Descriptive English Estimate Title",
          "workCode": "",
          "headings": [
            {
              "text": "HEADING NAME IN CAPS",
              "items": [
                {
                  "code": "54.TM.2.42.A",
                  "description": "Exact SOR item description",
                  "unit": "cum",
                  "rate": 194.4,
                  "measurements": [
                    { "desc": "Short measurement label", "no": "1", "l": "100", "b": "3.0", "d": "0.15", "cf": "", "qty": "", "isDeduction": false }
                  ]
                }
              ]
            }
          ],
          "lumpSums": [
            { "type": "Material", "description": "Display Board / CIB", "amount": "5000" }
          ]
        }
        3. Use ONLY real Bihar SECURE SOR item codes from the catalog provided below (or exact codes from an attached sample estimate PDF).
        4. If an attached sample PDF is provided with a requested new length (e.g., 400 ft -> 500 ft), preserve all headings, SOR codes, and cross-section dimensions (B, D) while scaling lengths proportionally.
        5. Keep every measurement dimension numeric (no units inside l/b/d/no fields). Use isDeduction=true for deductions.
        6. Include realistic Bihar MGNREGA Lump Sum items where appropriate (e.g., Conveyance - M, Display Board / CIB - M, Labour Welfare fund/Cess - A, Quality control and Survey - A, Miscellaneous /Contingencies charges - M).

        BIHAR MGNREGA SOR CATALOG EXCERPT:
        \(catalogSummary)
        """

        var parts: [[String: Any]] = [
            ["text": "User Civil Engineering Request:\n\(prompt)\n\nGenerate the complete SECURE estimate JSON strictly in English."]
        ]

        for att in attachments {
            parts.append([
                "inline_data": [
                    "mime_type": att.mimeType,
                    "data": att.data.base64EncodedString()
                ]
            ])
        }

        let payload: [String: Any] = [
            "system_instruction": ["parts": [["text": systemInstruction]]],
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json"
            ]
        ]

        let models = ["gemini-2.5-flash", "gemini-2.0-flash"]
        var lastError: Error = NSError(domain: "GeminiAIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Gemini request failed."])

        for model in models {
            do {
                let rawJSON = try await postGemini(model: model, apiKey: cleanKey, payload: payload)
                return try decodeEstimateJSON(rawJSON, sourceName: "100% AI (\(model))")
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func postGemini(model: String, apiKey: String, payload: [String: Any]) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else {
            throw NSError(domain: "GeminiAIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Gemini endpoint URL."])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "GeminiAIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "No HTTP response from Gemini."])
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "Unknown API error"
            throw NSError(domain: "GeminiAIService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Gemini HTTP \(http.statusCode): \(bodyText.prefix(280))"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.compactMap({ $0["text"] as? String }).joined().nilIfEmpty else {
            throw NSError(domain: "GeminiAIService", code: 502, userInfo: [NSLocalizedDescriptionKey: "Gemini returned an empty response."])
        }
        return text
    }

    private func decodeEstimateJSON(_ rawText: String, sourceName: String) throws -> EstimateDocument {
        var cleaned = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
            cleaned = cleaned.replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
        }
        guard let data = cleaned.data(using: .utf8) else {
            throw NSError(domain: "GeminiAIService", code: 503, userInfo: [NSLocalizedDescriptionKey: "Failed to encode AI JSON output."])
        }

        struct RawEst: Codable {
            let title: String?
            let workCode: String?
            let headings: [EstimateHeading]?
            let lumpSums: [LumpSumItem]?
        }

        let decoded = try JSONDecoder().decode(RawEst.self, from: data)
        var est = EstimateDocument(
            title: decoded.title ?? "AI Generated Estimate",
            workCode: decoded.workCode ?? "",
            sourceName: sourceName,
            headings: decoded.headings ?? [],
            lumpSums: decoded.lumpSums ?? []
        )

        // Enrich missing rates/units from official catalog
        let map = PDFEstimateParser.shared.catalogByCode
        for hi in est.headings.indices {
            for ii in est.headings[hi].items.indices {
                let code = est.headings[hi].items[ii].code.uppercased()
                if let match = map[code] {
                    if est.headings[hi].items[ii].rate <= 0 {
                        est.headings[hi].items[ii].rate = match.rate
                    }
                    if est.headings[hi].items[ii].unit.isEmpty {
                        est.headings[hi].items[ii].unit = match.unit
                    }
                }
            }
        }
        return est
    }

    private func buildRelevantCatalogContext(for prompt: String) -> String {
        let all = PDFEstimateParser.shared.catalogList
        guard !all.isEmpty else { return "(Catalog not bundled)" }
        let words = Set(prompt.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 3 })

        let scored = all.map { item -> (SORCatalogItem, Int) in
            let hay = "\(item.code) \(item.description) \(item.section)".lowercased()
            var score = 0
            for w in words where hay.contains(w) { score += 2 }
            if item.code.hasPrefix("54.") { score += 1 }
            return (item, score)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(75)

        return scored.map { item, _ in
            "\(item.code) | \(item.unit) | ₹\(item.rate) | \(item.description.prefix(120))"
        }.joined(separator: "\n")
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
