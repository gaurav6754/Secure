import Foundation

struct MeasurementRow: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var desc: String
    var no: String
    var l: String
    var b: String
    var d: String
    var cf: String
    var qty: String
    var isDeduction: Bool = false

    enum CodingKeys: String, CodingKey {
        case desc, no, l, b, d, cf, qty, isDeduction
    }

    init(
        id: UUID = UUID(),
        desc: String = "",
        no: String = "1",
        l: String = "",
        b: String = "",
        d: String = "",
        cf: String = "",
        qty: String = "",
        isDeduction: Bool = false
    ) {
        self.id = id
        self.desc = desc
        self.no = no
        self.l = l
        self.b = b
        self.d = d
        self.cf = cf
        self.qty = qty
        self.isDeduction = isDeduction
    }

    var computedQty: Double {
        if let q = Double(qty), q != 0 {
            return isDeduction ? -abs(q) : abs(q)
        }
        let nVal = Double(no) ?? 1.0
        let lVal = Double(l) ?? 1.0
        let bVal = Double(b) ?? 1.0
        let dVal = Double(d) ?? 1.0
        let cVal = Double(cf) ?? 1.0
        let hasAny = !l.isEmpty || !b.isEmpty || !d.isEmpty || !no.isEmpty
        let raw = hasAny ? (nVal * lVal * bVal * dVal * cVal) : 0.0
        return isDeduction ? -abs(raw) : abs(raw)
    }
}

struct EstimateItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var code: String
    var description: String
    var unit: String
    var rate: Double
    var reportedAmount: Double? = nil
    var measurements: [MeasurementRow]

    enum CodingKeys: String, CodingKey {
        case code, description, unit, rate, reportedAmount, measurements
    }

    init(
        id: UUID = UUID(),
        code: String,
        description: String = "",
        unit: String = "cum",
        rate: Double = 0.0,
        reportedAmount: Double? = nil,
        measurements: [MeasurementRow] = []
    ) {
        self.id = id
        self.code = code
        self.description = description
        self.unit = unit
        self.rate = rate
        self.reportedAmount = reportedAmount
        self.measurements = measurements
    }

    var totalQty: Double {
        measurements.reduce(0.0) { $0 + $1.computedQty }
    }

    var totalAmount: Double {
        if let rep = reportedAmount, rep > 0 { return rep }
        return max(0.0, totalQty) * rate
    }
}

struct EstimateHeading: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var text: String
    var items: [EstimateItem]

    enum CodingKeys: String, CodingKey {
        case text, items
    }

    init(id: UUID = UUID(), text: String, items: [EstimateItem] = []) {
        self.id = id
        self.text = text
        self.items = items
    }
}

struct LumpSumItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var type: String
    var description: String
    var amount: String

    enum CodingKeys: String, CodingKey {
        case type, description, amount
    }

    init(id: UUID = UUID(), type: String = "Material", description: String = "", amount: String = "0") {
        self.id = id
        self.type = type
        self.description = description
        self.amount = amount
    }

    var numericAmount: Double {
        Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0.0
    }
}

struct EstimateDocument: Codable, Hashable {
    var title: String = ""
    var workCode: String = ""
    var sourceName: String = ""
    var headings: [EstimateHeading] = []
    var lumpSums: [LumpSumItem] = []
    var reportedGrandTotal: Double? = nil
    var warnings: [String] = []
    var autoFixes: [String] = []

    var totalItemCount: Int {
        headings.reduce(0) { $0 + $1.items.count }
    }

    var totalMeasurementCount: Int {
        headings.reduce(0) { hSum, h in
            hSum + h.items.reduce(0) { $0 + $1.measurements.count }
        }
    }

    var estimatedGrandTotal: Double {
        if let rep = reportedGrandTotal, rep > 0 {
            return rep
        }
        let itemsSum = headings.reduce(0.0) { hSum, h in
            hSum + h.items.reduce(0.0) { $0 + $1.totalAmount }
        }
        let lumpSum = lumpSums.reduce(0.0) { $0 + $1.numericAmount }
        return itemsSum + lumpSum
    }

    /// Proportionally scales primary Length (L) measurements while preserving headings, SOR codes, and cross-section (B, D).
    func scaledByLength(from oldLength: Double, to newLength: Double) -> EstimateDocument {
        guard oldLength > 0, newLength > 0 else { return self }
        let ratio = newLength / oldLength
        var copy = self
        copy.reportedGrandTotal = nil
        for hi in copy.headings.indices {
            for ii in copy.headings[hi].items.indices {
                copy.headings[hi].items[ii].reportedAmount = nil
                for mi in copy.headings[hi].items[ii].measurements.indices {
                    let row = copy.headings[hi].items[ii].measurements[mi]
                    if let lVal = Double(row.l), lVal > 0 {
                        let newL = lVal * ratio
                        copy.headings[hi].items[ii].measurements[mi].l = String(format: "%.3f", newL)
                            .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
                        copy.headings[hi].items[ii].measurements[mi].qty = ""
                    }
                }
            }
        }
        copy.autoFixes.append(String(format: "Proportionally scaled lengths from %.2f to %.2f (factor %.3fx)", oldLength, newLength, ratio))
        return copy
    }
}

struct SORCatalogItem: Codable, Identifiable, Hashable {
    var id: String { code }
    let code: String
    let section: String
    let description: String
    let unit: String
    let rate: Double
}

enum SpeedPreset: String, CaseIterable, Identifiable {
    case x1 = "1x"
    case x2 = "2x"
    case x3 = "3x"
    case x5 = "5x"

    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .x1: return 1.0
        case .x2: return 2.0
        case .x3: return 3.0
        case .x5: return 5.0
        }
    }
}

enum AutomationUnitKind: String, Codable {
    case addHeading
    case addItem
    case fillMeasurements
    case addLumpSum
    case deleteItem
    case deleteHeading
    case deleteLumpSum
}

struct AutomationUnit: Identifiable {
    let id: String
    let kind: AutomationUnitKind
    let label: String
    let headingIndex: Int
    let itemIndex: Int?
    let headingText: String?
    let item: EstimateItem?
    let lumpSum: LumpSumItem?
}

struct PortalScrapedItem: Codable {
    let code: String
    let description: String
    let quantity: Double
    let amount: Double
}

struct PortalScrapedHeading: Codable {
    let index: Int
    let text: String
    let items: [PortalScrapedItem]
}

struct PortalScrapedLumpSum: Codable {
    let description: String
    let amount: Double
}

struct PortalScrapedEstimate: Codable {
    let headings: [PortalScrapedHeading]
    let lumpSums: [PortalScrapedLumpSum]
}

struct VerifyMismatch: Identifiable {
    let id = UUID()
    let category: String
    let summary: String
    let headingIndex: Int
    let itemIndex: Int?
    let repairUnits: [AutomationUnit]
}
