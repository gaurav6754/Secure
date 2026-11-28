import Foundation
import UIKit

@MainActor
final class AutomationController: ObservableObject {
    @Published var activeEstimate: EstimateDocument? = nil
    @Published var isVerifiedByUser: Bool = false
    @Published var speed: SpeedPreset = .x2

    @Published var isRunning: Bool = false
    @Published var isPaused: Bool = false
    @Published var currentStepLabel: String = "Idle"
    @Published var lastErrorBanner: String? = nil
    @Published var completedSteps: Int = 0
    @Published var totalSteps: Int = 0
    @Published var logs: [String] = []
    @Published var mismatches: [VerifyMismatch] = []

    private var runTask: Task<Void, Never>? = nil
    private var stopRequested: Bool = false

    func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(message)"
        logs.insert(line, at: 0)
        if logs.count > 250 { logs.removeLast() }
    }

    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func buildUnits(from est: EstimateDocument) -> [AutomationUnit] {
        var units: [AutomationUnit] = []
        for (hi, heading) in est.headings.enumerated() {
            units.append(AutomationUnit(
                id: "H\(hi)",
                kind: .addHeading,
                label: "Heading \(hi + 1): \(heading.text.prefix(38))",
                headingIndex: hi,
                itemIndex: nil,
                headingText: heading.text,
                item: nil,
                lumpSum: nil
            ))
            for (ii, item) in heading.items.enumerated() {
                units.append(AutomationUnit(
                    id: "S\(hi).\(ii)",
                    kind: .addItem,
                    label: "Add Item \(hi + 1).\(ii + 1): \(item.code)",
                    headingIndex: hi,
                    itemIndex: ii,
                    headingText: heading.text,
                    item: item,
                    lumpSum: nil
                ))
                if !item.measurements.isEmpty {
                    units.append(AutomationUnit(
                        id: "M\(hi).\(ii)",
                        kind: .fillMeasurements,
                        label: "Measurements \(hi + 1).\(ii + 1): \(item.code) (\(item.measurements.count) rows)",
                        headingIndex: hi,
                        itemIndex: ii,
                        headingText: heading.text,
                        item: item,
                        lumpSum: nil
                    ))
                }
            }
        }
        for (li, ls) in est.lumpSums.enumerated() {
            units.append(AutomationUnit(
                id: "L\(li)",
                kind: .addLumpSum,
                label: "Lump Sum \(li + 1): \(ls.description.isEmpty ? ls.type : ls.description) (₹\(ls.amount))",
                headingIndex: -1,
                itemIndex: li,
                headingText: nil,
                item: nil,
                lumpSum: ls
            ))
        }
        return units
    }

    func startAutomation(browser: EmbeddedBrowserStore) {
        guard let est = activeEstimate else {
            appendLog("No estimate loaded. Import a PDF or generate via 100% AI first.")
            return
        }
        dismissKeyboard()
        let units = buildUnits(from: est)
        runUnits(units, browser: browser, title: "Estimate Entry")
    }

    func runRepairUnits(browser: EmbeddedBrowserStore) {
        let allRepair = mismatches.flatMap { $0.repairUnits }
        guard !allRepair.isEmpty else {
            appendLog("No repair actions queued.")
            return
        }
        dismissKeyboard()
        runUnits(allRepair, browser: browser, title: "Verify & Fix Repair (Delete + Re-Add)")
    }

    private func runUnits(_ units: [AutomationUnit], browser: EmbeddedBrowserStore, title: String) {
        stop()
        guard !units.isEmpty else { return }

        isRunning = true
        isPaused = false
        stopRequested = false
        lastErrorBanner = nil
        completedSteps = 0
        totalSteps = units.count
        appendLog("Started \(title) (\(units.count) steps at \(speed.rawValue))")

        runTask = Task { @MainActor in
            var unitIdx = 0
            while unitIdx < units.count {
                let unit = units[unitIdx]
                if stopRequested { break }
                while isPaused && !stopRequested {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                if stopRequested { break }

                currentStepLabel = unit.label
                lastErrorBanner = nil
                appendLog("▶ \(unit.label)")

                var stepSucceeded = false
                do {
                    let (ok, message) = try await execute(unit: unit, browser: browser)
                    dismissKeyboard()
                    if ok {
                        appendLog("✓ \(message)")
                        stepSucceeded = true
                        // If an item was already present on portal during Add Item, skip its immediately following Fill Measurements step to prevent duplicating rows
                        if unit.kind == .addItem && message.lowercased().contains("already present") {
                            let nextIdx = unitIdx + 1
                            if nextIdx < queue.count,
                               queue[nextIdx].kind == .fillMeasurements,
                               queue[nextIdx].headingIndex == unit.headingIndex,
                               queue[nextIdx].item?.code.uppercased() == unit.item?.code.uppercased() {
                                appendLog("⏭ Skipped duplicate measurement fill for already-present \(unit.item?.code ?? "")")
                                completedSteps += 1
                                unitIdx += 1
                            }
                        }
                    } else {
                        lastErrorBanner = message
                        isPaused = true
                        appendLog("⚠ PAUSED at \(unit.label): \(message)")
                    }
                } catch {
                    lastErrorBanner = error.localizedDescription
                    isPaused = true
                    appendLog("⚠ PAUSED at \(unit.label): \(error.localizedDescription)")
                }

                if stepSucceeded {
                    completedSteps += 1
                    unitIdx += 1
                    let baseDelayMs = 450.0 / speed.multiplier
                    try? await Task.sleep(nanoseconds: UInt64(max(80.0, baseDelayMs) * 1_000_000))
                }
            }

            _ = try? await browser.callAutomationJS("if (window.__SECURE_AI_IPAD__) window.__SECURE_AI_IPAD__.hideCursor();")
            isRunning = false
            isPaused = false
            currentStepLabel = stopRequested ? "Stopped by user" : "Completed \(completedSteps)/\(totalSteps)"
            appendLog(stopRequested ? "■ Automation stopped." : "✅ Finished \(title)!")
        }
    }

    func togglePause() {
        guard isRunning else { return }
        isPaused.toggle()
        if !isPaused { lastErrorBanner = nil }
        appendLog(isPaused ? "⏸ Paused" : "▶ Resumed")
    }

    func stop() {
        stopRequested = true
        runTask?.cancel()
        runTask = nil
        isRunning = false
        isPaused = false
        lastErrorBanner = nil
    }

    func verifyAgainstLivePortal(browser: EmbeddedBrowserStore) async {
        guard let target = activeEstimate else {
            appendLog("Load your PDF or AI estimate first before running Verify.")
            return
        }
        appendLog("🔍 Scanning opened SECURE estimate in built-in browser...")
        do {
            let raw = try await browser.callAutomationJS("return await window.__SECURE_AI_IPAD__.scrapeCurrentEstimate();")
            guard let dict = raw as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict),
                  let scraped = try? JSONDecoder().decode(PortalScrapedEstimate.self, from: data) else {
                appendLog("Could not read estimate structure from current web page.")
                return
            }

            var found: [VerifyMismatch] = []
            for (hi, heading) in target.headings.enumerated() {
                if hi >= scraped.headings.count {
                    var repair: [AutomationUnit] = [
                        AutomationUnit(id: "FIX_H\(hi)", kind: .addHeading, label: "Add Missing Heading: \(heading.text)", headingIndex: hi, itemIndex: nil, headingText: heading.text, item: nil, lumpSum: nil)
                    ]
                    for (ii, it) in heading.items.enumerated() {
                        repair.append(AutomationUnit(id: "FIX_S\(hi).\(ii)", kind: .addItem, label: "Add Item \(it.code)", headingIndex: hi, itemIndex: ii, headingText: heading.text, item: it, lumpSum: nil))
                        if !it.measurements.isEmpty {
                            repair.append(AutomationUnit(id: "FIX_M\(hi).\(ii)", kind: .fillMeasurements, label: "Fill Measurements \(it.code)", headingIndex: hi, itemIndex: ii, headingText: heading.text, item: it, lumpSum: nil))
                        }
                    }
                    found.append(VerifyMismatch(
                        category: "Missing Heading",
                        summary: "Heading \(hi + 1) '\(heading.text)' is missing on SECURE portal.",
                        headingIndex: hi,
                        itemIndex: nil,
                        repairUnits: repair
                    ))
                    continue
                }

                let portalHeading = scraped.headings[hi]
                let portalByCode = Dictionary(portalHeading.items.map { ($0.code.uppercased(), $0) }, uniquingKeysWith: { first, _ in first })
                let expectedCodes = Set(heading.items.map { $0.code.uppercased() })

                for (ii, item) in heading.items.enumerated() {
                    let key = item.code.uppercased()
                    guard let pItem = portalByCode[key] else {
                        var repair: [AutomationUnit] = [
                            AutomationUnit(id: "FIX_ADD_\(hi).\(ii)", kind: .addItem, label: "Add Missing Item \(item.code)", headingIndex: hi, itemIndex: ii, headingText: heading.text, item: item, lumpSum: nil)
                        ]
                        if !item.measurements.isEmpty {
                            repair.append(AutomationUnit(id: "FIX_MEAS_\(hi).\(ii)", kind: .fillMeasurements, label: "Fill Measurements \(item.code)", headingIndex: hi, itemIndex: ii, headingText: heading.text, item: item, lumpSum: nil))
                        }
                        found.append(VerifyMismatch(
                            category: "Missing Item",
                            summary: "Heading \(hi + 1): Item \(item.code) missing on portal.",
                            headingIndex: hi,
                            itemIndex: ii,
                            repairUnits: repair
                        ))
                        continue
                    }

                    // Compare actual net quantity on SECURE portal vs PDF expected quantity!
                    let expectedQty = item.totalQty
                    let portalQty = pItem.quantity
                    let tol = max(0.05, expectedQty * 0.005)
                    if expectedQty > 0 && abs(portalQty - expectedQty) > tol {
                        var repair: [AutomationUnit] = [
                            AutomationUnit(id: "FIX_DEL_QTY_\(hi).\(ii)", kind: .deleteItem, label: "Delete Wrong Qty \(item.code)", headingIndex: hi, itemIndex: ii, headingText: heading.text, item: item, lumpSum: nil),
                            AutomationUnit(id: "FIX_READD_QTY_\(hi).\(ii)", kind: .addItem, label: "Re-Add \(item.code)", headingIndex: hi, itemIndex: ii, headingText: heading.text, item: item, lumpSum: nil)
                        ]
                        if !item.measurements.isEmpty {
                            repair.append(AutomationUnit(id: "FIX_REMEAS_QTY_\(hi).\(ii)", kind: .fillMeasurements, label: "Re-Fill Measurements \(item.code)", headingIndex: hi, itemIndex: ii, headingText: heading.text, item: item, lumpSum: nil))
                        }
                        found.append(VerifyMismatch(
                            category: "Qty Mismatch",
                            summary: String(format: "Heading %d: %@ qty is %.2f on portal (PDF expects %.2f) — will Delete & Re-Add.", hi + 1, item.code, portalQty, expectedQty),
                            headingIndex: hi,
                            itemIndex: ii,
                            repairUnits: repair
                        ))
                    }
                }

                for pItem in portalHeading.items where !expectedCodes.contains(pItem.code.uppercased()) {
                    let delItem = EstimateItem(code: pItem.code, description: pItem.description)
                    found.append(VerifyMismatch(
                        category: "Extra Item",
                        summary: "Heading \(hi + 1): Extra item \(pItem.code) on portal (will delete).",
                        headingIndex: hi,
                        itemIndex: nil,
                        repairUnits: [
                            AutomationUnit(id: "FIX_DEL_\(hi)_\(pItem.code)", kind: .deleteItem, label: "Delete Extra Item \(pItem.code)", headingIndex: hi, itemIndex: nil, headingText: heading.text, item: delItem, lumpSum: nil)
                        ]
                    ))
                }
            }

            // Compare Lump Sums (Missing, Amount Mismatch, and Extra portal Lump Sums)
            var remainingPortalLS = scraped.lumpSums.enumerated().map { ($0.offset, $0.element) }
            for (li, expectedLS) in target.lumpSums.enumerated() {
                let (expectedKey, _) = mapLumpSumKeyword(expectedLS)
                let expectedAmt = expectedLS.numericAmount
                if let matchIdx = remainingPortalLS.firstIndex(where: { (_, pLS) in
                    let (pKey, _) = mapLumpSumKeyword(LumpSumItem(type: "Material", description: pLS.description, amount: String(pLS.amount)))
                    return pKey.lowercased() == expectedKey.lowercased()
                }) {
                    let (_, pLS) = remainingPortalLS.remove(at: matchIdx)
                    if expectedAmt > 0 && abs(pLS.amount - expectedAmt) > 2.0 {
                        let delLS = LumpSumItem(type: expectedLS.type, description: pLS.description, amount: String(pLS.amount))
                        found.append(VerifyMismatch(
                            category: "Lump Sum Mismatch",
                            summary: String(format: "Lump Sum '%@' is ₹%.0f on portal (PDF expects ₹%.0f) — will Delete & Re-Add.", expectedKey, pLS.amount, expectedAmt),
                            headingIndex: -1,
                            itemIndex: nil,
                            repairUnits: [
                                AutomationUnit(id: "FIX_DEL_LS_\(li)", kind: .deleteLumpSum, label: "Delete Wrong Lump Sum \(expectedKey)", headingIndex: -1, itemIndex: nil, headingText: nil, item: nil, lumpSum: delLS),
                                AutomationUnit(id: "FIX_ADD_LS_\(li)", kind: .addLumpSum, label: "Re-Add Lump Sum \(expectedKey)", headingIndex: -1, itemIndex: nil, headingText: nil, item: nil, lumpSum: expectedLS)
                            ]
                        ))
                    }
                } else if expectedAmt > 0 {
                    found.append(VerifyMismatch(
                        category: "Missing Lump Sum",
                        summary: String(format: "Lump Sum '%@' (₹%.0f) is missing on portal.", expectedKey, expectedAmt),
                        headingIndex: -1,
                        itemIndex: nil,
                        repairUnits: [
                            AutomationUnit(id: "FIX_MISS_LS_\(li)", kind: .addLumpSum, label: "Add Missing Lump Sum \(expectedKey)", headingIndex: -1, itemIndex: nil, headingText: nil, item: nil, lumpSum: expectedLS)
                        ]
                    ))
                }
            }
            for (pi, pLS) in remainingPortalLS where pLS.amount > 0 {
                let delLS = LumpSumItem(type: "Material", description: pLS.description, amount: String(pLS.amount))
                found.append(VerifyMismatch(
                    category: "Extra Lump Sum",
                    summary: String(format: "Extra Lump Sum '%@' (₹%.0f) on portal (will delete).", pLS.description, pLS.amount),
                    headingIndex: -1,
                    itemIndex: nil,
                    repairUnits: [
                        AutomationUnit(id: "FIX_EXTRA_LS_\(pi)", kind: .deleteLumpSum, label: "Delete Extra Lump Sum \(pLS.description)", headingIndex: -1, itemIndex: nil, headingText: nil, item: nil, lumpSum: delLS)
                    ]
                ))
            }

            mismatches = found
            if found.isEmpty {
                appendLog("✅ Verify complete: All headings, SOR quantities & Lump Sums match the opened SECURE draft!")
            } else {
                appendLog("⚠ Found \(found.count) mismatch(es). Tap 'Auto-Fix (Delete & Re-Add)' to repair.")
            }
        } catch {
            appendLog("Verify failed: \(error.localizedDescription)")
        }
    }

    private func execute(unit: AutomationUnit, browser: EmbeddedBrowserStore) async throws -> (Bool, String) {
        _ = try? await browser.callAutomationJS("window.__SECURE_AI_SPEED__ = spd;", arguments: ["spd": speed.multiplier])
        switch unit.kind {
        case .addHeading:
            let res = try await browser.callAutomationJS(
                "return await window.__SECURE_AI_IPAD__.addHeading(text);",
                arguments: ["text": unit.headingText ?? "HEADING"]
            )
            return extractJSResult(res)

        case .addItem:
            guard let item = unit.item else { return (true, "Skipped empty item") }
            let isTM = item.code.uppercased().contains(".TM.")
            let res = try await browser.callAutomationJS(
                "return await window.__SECURE_AI_IPAD__.addItem(hi, hText, code, isTM);",
                arguments: ["hi": unit.headingIndex, "hText": unit.headingText ?? "", "code": item.code, "isTM": isTM]
            )
            return extractJSResult(res)

        case .fillMeasurements:
            guard let item = unit.item else { return (true, "Skipped empty measurements") }
            let rowsArray: [[String: Any]] = item.measurements.map { r in
                [
                    "desc": r.desc,
                    "no": r.no,
                    "l": r.l,
                    "b": r.b,
                    "d": r.d,
                    "cf": r.cf,
                    "isDeduction": r.isDeduction
                ]
            }
            let res = try await browser.callAutomationJS(
                "return await window.__SECURE_AI_IPAD__.fillMeasurements(hi, hText, code, rows);",
                arguments: ["hi": unit.headingIndex, "hText": unit.headingText ?? "", "code": item.code, "rows": rowsArray]
            )
            return extractJSResult(res)

        case .addLumpSum:
            guard let ls = unit.lumpSum else { return (true, "Skipped empty lump sum") }
            let (keyword, customDesc) = mapLumpSumKeyword(ls)
            let res = try await browser.callAutomationJS(
                "return await window.__SECURE_AI_IPAD__.addLumpSum(kw, desc, amt);",
                arguments: ["kw": keyword, "desc": customDesc, "amt": ls.amount]
            )
            return extractJSResult(res)

        case .deleteItem:
            guard let item = unit.item else { return (true, "Skipped delete") }
            let res = try await browser.callAutomationJS(
                "return await window.__SECURE_AI_IPAD__.deleteItemInHeading(hi, code);",
                arguments: ["hi": unit.headingIndex, "code": item.code]
            )
            return extractJSResult(res)

        case .deleteHeading:
            return (true, "Delete heading handled")

        case .deleteLumpSum:
            guard let ls = unit.lumpSum else { return (true, "Skipped empty lump sum delete") }
            let res = try await browser.callAutomationJS(
                "return await window.__SECURE_AI_IPAD__.deleteLumpSum(desc, amt);",
                arguments: ["desc": ls.description, "amt": ls.numericAmount]
            )
            return extractJSResult(res)
        }
    }

    private func mapLumpSumKeyword(_ ls: LumpSumItem) -> (String, String) {
        // ONLY inspect ls.description (NEVER ls.type, because "Material" contains substring "mate"!)
        let descLow = ls.description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pairs: [(String, String)] = [
            ("conveyance", "Conveyance"),
            ("carriage", "Conveyance"),
            ("electrification", "Electrification"),
            ("gst", "GST"),
            ("miscellaneous", "Miscellaneous"),
            ("misc", "Miscellaneous"),
            ("conting", "Miscellaneous"),
            ("royalty", "Miscellaneous"),
            ("display", "Display"),
            ("sign board", "Display"),
            ("signboard", "Display"),
            ("cib", "Display"),
            ("board", "Display"),
            ("labour", "Labour"),
            ("welfare", "Labour"),
            ("cess", "Labour"),
            ("quality", "Quality"),
            ("survey", "Quality"),
            ("testing", "Quality"),
            ("worksite", "Worksite"),
            ("work site", "Worksite"),
            ("creche", "Worksite"),
            ("drinking", "Worksite"),
            ("first aid", "Worksite"),
            ("first-aid", "Worksite"),
            ("bf/t/a", "BF"),
            ("bft/ta", "BF"),
            ("bft", "BF")
        ]
        for (needle, kw) in pairs where descLow.contains(needle) {
            return (kw, "")
        }
        // Only match standalone word "mate" (never "material" or "estimate")
        if descLow.range(of: #"\bmate\b"#, options: .regularExpression) != nil {
            return ("BF", "")
        }
        return ("Miscellaneous", ls.description)
    }

    private func extractJSResult(_ raw: Any?) -> (Bool, String) {
        if let dict = raw as? [String: Any] {
            let ok = (dict["ok"] as? Bool) ?? true
            let msg = (dict["message"] as? String) ?? "Done"
            return (ok, msg)
        }
        return (false, "No response from SECURE page script.")
    }
}
