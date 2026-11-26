import Foundation
import PDFKit

/// Native iPadOS port of SECURE AI's `estimate_parser.py` using Apple PDFKit.
/// Matches PC parser behavior on Bihar SECURE Detailed Estimate PDFs:
/// - Recognizes `Heading / Description: 1 - RCC DRAIN` headings
/// - Stops measurement capture strictly at `LIST` (never reads labour/material rate-analysis rows)
/// - Handles wrapped multi-line measurement descriptions and CF/Quantity columns accurately
/// - Parses multi-line `Lump sum Type :` entries while ignoring `Lumpsum Admin` / `Lumpsum Material` summary lines
/// - Extracts official `Say ... @ (₹) rate / unit amount` and `Rounded Total (₹)`
final class PDFEstimateParser {
    static let shared = PDFEstimateParser()

    private(set) var catalogByCode: [String: SORCatalogItem] = [:]
    private(set) var catalogList: [SORCatalogItem] = []

    private init() {
        loadBundledCatalog()
    }

    private func loadBundledCatalog() {
        guard let url = Bundle.main.url(forResource: "official_54_catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([SORCatalogItem].self, from: data) else {
            return
        }
        catalogList = items
        var map: [String: SORCatalogItem] = [:]
        for item in items {
            map[item.code.uppercased()] = item
        }
        catalogByCode = map
    }

    func parsePDF(at url: URL) throws -> EstimateDocument {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: url)
        return try parsePDFData(data, sourceName: url.lastPathComponent)
    }

    func parsePDFData(_ data: Data, sourceName: String) throws -> EstimateDocument {
        guard let pdfDoc = PDFDocument(data: data) else {
            throw NSError(domain: "PDFEstimateParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Selected file is not a valid PDF document."])
        }

        var rawLines: [String] = []
        for pageIndex in 0..<pdfDoc.pageCount {
            guard let page = pdfDoc.page(at: pageIndex),
                  let text = page.string else { continue }
            let lines = text.components(separatedBy: .newlines)
            rawLines.append(contentsOf: lines)
        }

        return parseLines(rawLines, sourceName: sourceName)
    }

    func parseLines(_ lines: [String], sourceName: String) -> EstimateDocument {
        var est = EstimateDocument(sourceName: sourceName)

        var currentHeadingIndex: Int? = nil
        var currentItemIndex: Int? = nil
        var inMeasurementBlock = false
        var pendingDescParts: [String] = []
        var pendingLump: LumpSumItem? = nil
        var inSummarySection = false

        let workCodeRegex = try! NSRegularExpression(pattern: #"^\d{5,}/\w+/(?:\w+/)?\d+$"#)
        let secureHeadingRegex = try! NSRegularExpression(pattern: #"^Heading\s*/\s*Description\s*:\s*(?:\d+\s*[-–:.]\s*)?(.+)$"#, options: [.caseInsensitive])
        let genericHeadingRegex = try! NSRegularExpression(pattern: #"^HEADING\s*[:\-]?\s*\d*\.?\s*(.+)$"#, options: [.caseInsensitive])
        let sorItemRegex = try! NSRegularExpression(pattern: #"^(?:\d{1,3}\s+)?(\d{1,2}(?:\.TM)?(?:\.[A-Za-z0-9]+){2,6})\s*(?:--|[-–:])\s*(.*)$"#, options: [.caseInsensitive])
        let sayLineRegex = try! NSRegularExpression(pattern: #"^Say\s+([\d.]+)\s+([A-Za-z0-9/]+)\s*@\s*\(?₹?\)?\s*([\d.]+)\s*/\s*([A-Za-z0-9/]+)\s+([\d,]+\.?\d*)$"#, options: [.caseInsensitive])
        let totalLineRegex = try! NSRegularExpression(pattern: #"^(?:Rounded\s+)?Total\s*\(₹\)\s*:\s*([\d,]+\.?\d*)$"#, options: [.caseInsensitive])

        func flushPendingLump() {
            if let ls = pendingLump, ls.numericAmount > 0 {
                est.lumpSums.append(ls)
            }
            pendingLump = nil
        }

        for (idx, rawLine) in lines.enumerated() {
            let line = fixLigatures(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            let compact = line.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            if compact.isEmpty { continue }

            // Skip page headers/footers like "11/9/26, 9:44 PM Secure Print" or "about:blank 1/14"
            if compact.hasPrefix("about:blank") || compact.contains("Secure Print") {
                continue
            }

            // Summary section boundary (after lump sums)
            if compact.hasPrefix("Shape Type") || compact.hasPrefix("Measurement Length") || compact.hasPrefix("Unskilled Manpower") {
                flushPendingLump()
                inMeasurementBlock = false
                inSummarySection = true
                continue
            }

            // Grand Total / Rounded Total
            if let m = totalLineRegex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)) {
                flushPendingLump()
                inMeasurementBlock = false
                inSummarySection = true
                let amtStr = rangeString(compact, m.range(at: 1)).replacingOccurrences(of: ",", with: "")
                if let val = Double(amtStr), val > 0 {
                    est.reportedGrandTotal = val
                }
                continue
            }

            // Ignore summary lines like "Lumpsum Admin 0.00" and "Lumpsum Material 254484.00"
            if inSummarySection {
                continue
            }

            // Work Code & Title
            if est.workCode.isEmpty,
               workCodeRegex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)) != nil {
                est.workCode = compact
                if idx > 0 && est.title.isEmpty {
                    let prev = fixLigatures(lines[idx - 1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let prev2 = idx >= 2 ? fixLigatures(lines[idx - 2]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                    if !prev2.isEmpty && !prev2.hasPrefix("AS No:") && !prev2.hasPrefix("SoR Period") {
                        est.title = "\(prev2) \(prev)".trimmingCharacters(in: .whitespaces)
                    } else {
                        est.title = prev
                    }
                }
                continue
            }

            // 1. SECURE Heading match: "Heading / Description: 1 - RCC DRAIN"
            if let m = secureHeadingRegex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)) {
                flushPendingLump()
                inMeasurementBlock = false
                pendingDescParts.removeAll()
                let hText = cleanHeadingText(rangeString(compact, m.range(at: 1)))
                if !hText.isEmpty {
                    est.headings.append(EstimateHeading(text: hText))
                    currentHeadingIndex = est.headings.count - 1
                    currentItemIndex = nil
                }
                continue
            }
            if let m = genericHeadingRegex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)) {
                flushPendingLump()
                inMeasurementBlock = false
                pendingDescParts.removeAll()
                let hText = cleanHeadingText(rangeString(compact, m.range(at: 1)))
                if !hText.isEmpty {
                    est.headings.append(EstimateHeading(text: hText))
                    currentHeadingIndex = est.headings.count - 1
                    currentItemIndex = nil
                }
                continue
            }

            // 2. Multi-line Lump Sum start: "Lump sum Type :"
            if compact.range(of: #"^(?:\d{1,3}\s+)?Lump\s*sum\s*Type\s*:"#, options: [.regularExpression, .caseInsensitive]) != nil {
                flushPendingLump()
                inMeasurementBlock = false
                pendingDescParts.removeAll()
                currentItemIndex = nil
                var ls = LumpSumItem(type: "Material", description: "", amount: "0")
                if let colonIdx = compact.firstIndex(of: ":") {
                    let rest = String(compact[compact.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                    if !rest.isEmpty {
                        parseLumpSumTokens(rest, into: &ls)
                    }
                }
                pendingLump = ls
                if ls.numericAmount > 0 {
                    flushPendingLump()
                }
                continue
            }

            // Continue collecting multi-line Lump Sum fields until amount arrives
            if var ls = pendingLump {
                // Skip standalone serial number line (e.g. "5")
                if compact.range(of: #"^\d{1,2}$"#, options: .regularExpression) != nil {
                    continue
                }
                parseLumpSumTokens(compact, into: &ls)
                pendingLump = ls
                if ls.numericAmount > 0 {
                    flushPendingLump()
                }
                continue
            }

            // 3. CRITICAL: STOP measurement capture immediately at "LIST" or rate-analysis header!
            let up = compact.uppercased()
            if up == "LIST" || up.hasPrefix("LIST ") || (compact.lowercased().contains("code") && compact.lowercased().contains("rate") && compact.lowercased().contains("unit")) {
                inMeasurementBlock = false
                pendingDescParts.removeAll()
                continue
            }

            // 4. Official "Say <qty> <unit> @ (₹) <rate> / <unit> <amount>" summary line per item
            if let hi = currentHeadingIndex, let ii = currentItemIndex,
               let m = sayLineRegex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)) {
                inMeasurementBlock = false
                pendingDescParts.removeAll()
                let unit = rangeString(compact, m.range(at: 2))
                let rate = Double(rangeString(compact, m.range(at: 3))) ?? 0.0
                let amt = Double(rangeString(compact, m.range(at: 5)).replacingOccurrences(of: ",", with: "")) ?? 0.0
                if !unit.isEmpty { est.headings[hi].items[ii].unit = unit }
                if rate > 0 { est.headings[hi].items[ii].rate = rate }
                if amt > 0 { est.headings[hi].items[ii].reportedAmount = amt }
                continue
            }

            // 5. SOR Item Code line: "1 54.TM.2.42.A -- Earth work..."
            if let m = sorItemRegex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)) {
                inMeasurementBlock = false
                pendingDescParts.removeAll()
                let code = rangeString(compact, m.range(at: 1)).uppercased()
                let desc = rangeString(compact, m.range(at: 2)).trimmingCharacters(in: .whitespaces)
                if currentHeadingIndex == nil {
                    est.headings.append(EstimateHeading(text: deriveHeading(for: code, desc: desc)))
                    currentHeadingIndex = est.headings.count - 1
                }
                let catMatch = catalogByCode[code]
                let finalDesc = desc.isEmpty ? (catMatch?.description ?? code) : desc
                let newItem = EstimateItem(
                    code: code,
                    description: finalDesc,
                    unit: catMatch?.unit ?? "cum",
                    rate: catMatch?.rate ?? 0.0,
                    reportedAmount: nil,
                    measurements: []
                )
                est.headings[currentHeadingIndex!].items.append(newItem)
                currentItemIndex = est.headings[currentHeadingIndex!].items.count - 1
                continue
            }

            // 6. Measurement table header: "Sl No Description No L B D CF Quantity Remark"
            let low = compact.lowercased()
            if (low.contains("sl no") || low.contains("description")) && low.contains("quantity") && (low.contains("cf") || low.contains("no l")) && !low.contains("rate") {
                inMeasurementBlock = true
                pendingDescParts.removeAll()
                continue
            }

            // 7. Measurement rows strictly inside measurement block (between Sl No header and LIST)
            if inMeasurementBlock, let hi = currentHeadingIndex, let ii = currentItemIndex {
                // Skip pure boundary lines
                if low.hasPrefix("total quantity") || low.hasPrefix("net total") || low.hasPrefix("unskilled") {
                    inMeasurementBlock = false
                    pendingDescParts.removeAll()
                    continue
                }

                if let row = parseSecureMeasurementLine(compact, pendingDescParts: &pendingDescParts) {
                    est.headings[hi].items[ii].measurements.append(row)
                }
            }
        }

        flushPendingLump()
        est.headings.removeAll { $0.items.isEmpty }
        if est.headings.isEmpty {
            est.warnings.append("No selectable SECURE headings/items found in PDF text. Tap 'Extract This PDF with 100% AI Vision' to read it with Gemini Vision.")
        }
        return est
    }

    /// Parses a SECURE measurement row (including wrapped multi-line descriptions where numbers appear on the last line).
    private func parseSecureMeasurementLine(_ compact: String, pendingDescParts: inout [String]) -> MeasurementRow? {
        // Standalone serial number line like "1" or "2" before a wrapped description
        if compact.range(of: #"^\d{1,3}$"#, options: .regularExpression) != nil {
            pendingDescParts.removeAll()
            return nil
        }

        // Tokenize and strip trailing "-" remark marker
        var tokens = compact.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if tokens.last == "-" || tokens.last == "–" {
            tokens.removeLast()
        }

        // Count numeric tokens at the tail of the line
        var tailNumbers: [String] = []
        var idx = tokens.count - 1
        while idx >= 0 {
            let t = tokens[idx]
            if isNumberToken(t) {
                tailNumbers.insert(t, at: 0)
                idx -= 1
            } else {
                break
            }
        }

        // Need at least 3 trailing numbers for a SECURE measurement row (e.g. No, CF, Qty)
        if tailNumbers.count < 3 {
            // This line is wrapped description text (e.g., "DRESSING", "LEVELING", "Centring and")
            pendingDescParts.append(compact)
            return nil
        }

        // Leading text tokens before the trailing numbers
        var descTokens = idx >= 0 ? Array(tokens[0...idx]) : []
        // Drop leading Sl No (e.g. "1" in "1 Earth work 1 80.000 0.762 1.295 1.0 78.9430")
        if let first = descTokens.first, first.range(of: #"^\d{1,3}\.?$"#, options: .regularExpression) != nil {
            descTokens.removeFirst()
        }

        // If descTokens is empty and tailNumbers has an extra leading serial number (unlikely because wrapped desc was above)
        let combinedDesc = (pendingDescParts + descTokens).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        pendingDescParts.removeAll()

        let isDed = combinedDesc.lowercased().contains("deduct") || combinedDesc.lowercased().hasPrefix("less") || (tailNumbers.last?.hasPrefix("-") == true)
        let nums = tailNumbers.map { $0.replacingOccurrences(of: "-", with: "") }

        // SECURE column order: [No, L, B, D, CF, Quantity]
        // CF (typically 1.0) is always second-to-last and Quantity is always last.
        switch nums.count {
        case 3:
            // [No, CF, Qty] (e.g., serving drinking water: 30, 1.0, 30.0000)
            return MeasurementRow(desc: combinedDesc, no: nums[0], l: "", b: "", d: "", cf: nums[1], qty: nums[2], isDeduction: isDed)
        case 4:
            // [No, L, CF, Qty]
            return MeasurementRow(desc: combinedDesc, no: nums[0], l: nums[1], b: "", d: "", cf: nums[2], qty: nums[3], isDeduction: isDed)
        case 5:
            // [No, L, B, CF, Qty] (e.g., BFS / Plaster / Shuttering / Paver Block)
            return MeasurementRow(desc: combinedDesc, no: nums[0], l: nums[1], b: nums[2], d: "", cf: nums[3], qty: nums[4], isDeduction: isDed)
        default:
            // 6+ -> take last 6: [No, L, B, D, CF, Qty] (e.g., Earthwork / Sand / PCC / RCC / TMT)
            let s = Array(nums.suffix(6))
            return MeasurementRow(desc: combinedDesc, no: s[0], l: s[1], b: s[2], d: s[3], cf: s[4], qty: s[5], isDeduction: isDed)
        }
    }

    private func parseLumpSumTokens(_ text: String, into ls: inout LumpSumItem) {
        let tokens = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var descParts: [String] = []
        for t in tokens {
            let cleaned = t.replacingOccurrences(of: ",", with: "")
            let low = t.lowercased()
            if ["material", "labour", "labor", "admin"].contains(low) {
                ls.type = t.capitalized
            } else if let v = Double(cleaned), v > 0, (t.contains(".") || v >= 50) {
                ls.amount = cleaned
            } else {
                descParts.append(t)
            }
        }
        if !descParts.isEmpty {
            let added = descParts.joined(separator: " ")
            ls.description = ls.description.isEmpty ? added : "\(ls.description) \(added)"
        }
    }

    private func isNumberToken(_ s: String) -> Bool {
        s.range(of: #"^-?\d+(?:\.\d+)?$"#, options: .regularExpression) != nil
    }

    private func fixLigatures(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{FB01}", with: "fi")
            .replacingOccurrences(of: "\u{FB02}", with: "fl")
            .replacingOccurrences(of: "\u{FB00}", with: "ff")
            .replacingOccurrences(of: "\u{FB03}", with: "ffi")
            .replacingOccurrences(of: "\u{FB04}", with: "ffl")
    }

    private func cleanHeadingText(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-")))
    }

    private func deriveHeading(for code: String, desc: String) -> String {
        let low = desc.lowercased()
        if low.contains("earth") || low.contains("excavat") { return "EARTHWORK" }
        if low.contains("brick") { return "BRICK WORK" }
        if low.contains("concrete") || low.contains("pcc") || low.contains("rcc") { return "CONCRETE WORK" }
        if low.contains("plaster") { return "PLASTERING & FINISHING" }
        if low.contains("paver") || low.contains("interlock") { return "PAVER BLOCK WORK" }
        return "CIVIL WORK (\(code.components(separatedBy: ".").first ?? "54"))"
    }

    private func rangeString(_ text: String, _ range: NSRange) -> String {
        guard range.location != NSNotFound, let r = Range(range, in: text) else { return "" }
        return String(text[r])
    }
}
