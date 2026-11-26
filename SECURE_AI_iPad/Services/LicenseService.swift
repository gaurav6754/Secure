import Foundation
import UIKit

@MainActor
final class LicenseService: ObservableObject {
    static let defaultCloudMongoURI = "mongodb+srv://mgnrega:gaurav2323@cluster0.8albao0.mongodb.net/?appName=Cluster0"
    static let licenseDBName = "lazyman_license_db"

    // Keychain keys (survive app reinstalls!)
    private static let kcLicenseKey = "kc_secure_ai_license_key"
    private static let kcCloudURI = "kc_secure_ai_cloud_uri"
    private static let kcActivated = "kc_secure_ai_activated"
    private static let kcDeviceID = "kc_secure_ai_stable_device_id"
    private static let kcCustomer = "kc_secure_ai_customer"
    private static let kcPlan = "kc_secure_ai_plan"
    private static let kcGeminiKey = "kc_secure_ai_cloud_gemini"
    private static let kcAnthropicKey = "kc_secure_ai_cloud_anthropic"
    private static let kcAIProvider = "kc_secure_ai_cloud_provider"

    @Published var licenseKey: String {
        didSet { KeychainHelper.save(licenseKey, forKey: Self.kcLicenseKey) }
    }
    @Published var serverURL: String {
        didSet { KeychainHelper.save(serverURL, forKey: Self.kcCloudURI) }
    }
    @Published var isActivated: Bool {
        didSet { KeychainHelper.save(isActivated ? "1" : "0", forKey: Self.kcActivated) }
    }
    @Published var customerName: String {
        didSet { KeychainHelper.save(customerName, forKey: Self.kcCustomer) }
    }
    @Published var planName: String {
        didSet { KeychainHelper.save(planName, forKey: Self.kcPlan) }
    }
    @Published var cloudGeminiKey: String {
        didSet { KeychainHelper.save(cloudGeminiKey, forKey: Self.kcGeminiKey) }
    }
    @Published var cloudAnthropicKey: String {
        didSet { KeychainHelper.save(cloudAnthropicKey, forKey: Self.kcAnthropicKey) }
    }
    @Published var cloudAIProvider: String {
        didSet { KeychainHelper.save(cloudAIProvider, forKey: Self.kcAIProvider) }
    }
    @Published var statusMessage: String = "Enter your license key to activate with Cloud Database."
    @Published var isChecking: Bool = false

    let deviceId: String
    let deviceName: String
    let osInfo: String

    init() {
        // Stable device ID stored in Keychain so reinstalling the IPA never counts as a new device
        if let savedDevId = KeychainHelper.loadString(forKey: Self.kcDeviceID), !savedDevId.isEmpty {
            self.deviceId = savedDevId
        } else {
            let newId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            KeychainHelper.save(newId, forKey: Self.kcDeviceID)
            self.deviceId = newId
        }

        let kcKey = KeychainHelper.loadString(forKey: Self.kcLicenseKey)
        self.licenseKey = kcKey ?? UserDefaults.standard.string(forKey: "secure_ai_license_key") ?? ""

        let kcURI = KeychainHelper.loadString(forKey: Self.kcCloudURI)
        let savedURI = kcURI ?? UserDefaults.standard.string(forKey: "secure_ai_cloud_uri_v2") ?? ""
        self.serverURL = savedURI.isEmpty ? Self.defaultCloudMongoURI : savedURI

        let kcAct = KeychainHelper.loadString(forKey: Self.kcActivated)
        self.isActivated = (kcAct == "1") || UserDefaults.standard.bool(forKey: "secure_ai_activated_cloud_v2")

        self.customerName = KeychainHelper.loadString(forKey: Self.kcCustomer) ?? ""
        self.planName = KeychainHelper.loadString(forKey: Self.kcPlan) ?? ""
        self.cloudGeminiKey = KeychainHelper.loadString(forKey: Self.kcGeminiKey) ?? ""
        self.cloudAnthropicKey = KeychainHelper.loadString(forKey: Self.kcAnthropicKey) ?? ""
        self.cloudAIProvider = KeychainHelper.loadString(forKey: Self.kcAIProvider) ?? "gemini"
        self.deviceName = UIDevice.current.name
        self.osInfo = "iPadOS \(UIDevice.current.systemVersion)"

        if isActivated && !licenseKey.isEmpty {
            self.statusMessage = "Restored active Cloud license (\(planName.isEmpty ? "Active" : planName))."
        }
    }

    func activateLicense() async {
        let cleanKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanKey.isEmpty else {
            isActivated = false
            statusMessage = "Enter a valid SECURE AI license key first."
            return
        }
        licenseKey = cleanKey

        let target = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTarget = target.isEmpty ? Self.defaultCloudMongoURI : target

        isChecking = true
        statusMessage = "Connecting to SECURE AI Cloud Database..."
        defer { isChecking = false }

        if effectiveTarget.hasPrefix("mongodb+srv://") || effectiveTarget.hasPrefix("mongodb://") {
            await activateViaMongoDB(uri: effectiveTarget, key: cleanKey)
        } else {
            await activateViaHTTP(baseURL: effectiveTarget, key: cleanKey)
        }
    }

    /// Re-verifies license & syncs Gemini + Anthropic API keys from Laptop License Manager on launch.
    func verifyOnLaunch() async {
        guard !licenseKey.isEmpty else { return }
        let target = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTarget = target.isEmpty ? Self.defaultCloudMongoURI : target
        guard effectiveTarget.hasPrefix("mongodb+srv://") || effectiveTarget.hasPrefix("mongodb://") else { return }
        await activateViaMongoDB(uri: effectiveTarget, key: licenseKey.uppercased(), isVerifyOnly: true)
    }

    private func activateViaMongoDB(uri: String, key: String, isVerifyOnly: Bool = false) async {
        do {
            let client = try MongoWireClient(uri: uri)
            defer { client.disconnect() }

            let now = try await client.connectAndAuthenticate()
            let db = Self.licenseDBName

            let licFind = try await client.runCommand(database: db, command: MongoWireClient.BSONDoc([
                ("find", .string("licenses")),
                ("filter", .document([
                    ("license_key", .string(key)),
                    ("deleted", .document([("$ne", .int32(1))]))
                ])),
                ("limit", .int32(1))
            ]))

            guard let cursor = licFind["cursor"]?.docValue,
                  let batch = MongoWireClient.BSONDoc(cursor)["firstBatch"]?.arrayValue,
                  let licVal = batch.first,
                  let licPairs = licVal.docValue else {
                isActivated = false
                statusMessage = "Invalid License Key (not found in Cloud Database)."
                return
            }

            let lic = MongoWireClient.BSONDoc(licPairs)
            let rawStatus = (lic["status"]?.stringValue ?? "UNUSED").uppercased()
            let isLifetime = lic["is_lifetime"]?.boolValue ?? false
            let expiresAt = lic["expires_at"]?.int64Value ?? 0
            let activatedAt = lic["activated_at"]?.int64Value ?? 0
            let durationSec = lic["duration_seconds"]?.int64Value ?? Int64(30 * 86400)
            let maxDevices = Int(lic["max_devices"]?.int64Value ?? 1)

            if rawStatus == "REVOKED" {
                isActivated = false
                statusMessage = "License Revoked by Administrator."
                return
            }
            if rawStatus == "SUSPENDED" {
                isActivated = false
                statusMessage = "License Suspended by Administrator."
                return
            }
            if !isLifetime && expiresAt > 0 && now >= expiresAt {
                isActivated = false
                statusMessage = "License Expired."
                return
            }

            let devFind = try await client.runCommand(database: db, command: MongoWireClient.BSONDoc([
                ("find", .string("devices")),
                ("filter", .document([("license_key", .string(key))]))
            ]))

            var activeDevices: [String] = []
            var thisDeviceBlocked = false
            if let dCursor = devFind["cursor"]?.docValue,
               let dBatch = MongoWireClient.BSONDoc(dCursor)["firstBatch"]?.arrayValue {
                for item in dBatch {
                    guard let dp = item.docValue else { continue }
                    let dDoc = MongoWireClient.BSONDoc(dp)
                    let dId = dDoc["device_id"]?.stringValue ?? ""
                    let dStatus = (dDoc["status"]?.stringValue ?? "").uppercased()
                    if dId == deviceId && dStatus == "BLOCKED" { thisDeviceBlocked = true }
                    if dStatus == "ACTIVE" { activeDevices.append(dId) }
                }
            }

            if thisDeviceBlocked {
                isActivated = false
                statusMessage = "This iPad has been blocked by the Administrator."
                return
            }

            let alreadyBound = activeDevices.contains(deviceId)
            if !alreadyBound && activeDevices.count >= maxDevices {
                isActivated = false
                statusMessage = maxDevices == 1
                    ? "This license is already activated on another device."
                    : "Maximum device limit (\(maxDevices)) reached."
                return
            }

            var licSet: [(String, MongoWireClient.BSONValue)] = [("status", .string("ACTIVE"))]
            if activatedAt == 0 {
                licSet.append(("activated_at", .int64(now)))
                if !isLifetime && expiresAt == 0 {
                    licSet.append(("expires_at", .int64(now + durationSec)))
                }
            }

            _ = try await client.runCommand(database: db, command: MongoWireClient.BSONDoc([
                ("update", .string("licenses")),
                ("updates", .array([
                    .document([
                        ("q", .document([("license_key", .string(key))])),
                        ("u", .document([("$set", .document(licSet))])),
                        ("upsert", .bool(false))
                    ])
                ]))
            ]))

            _ = try await client.runCommand(database: db, command: MongoWireClient.BSONDoc([
                ("update", .string("devices")),
                ("updates", .array([
                    .document([
                        ("q", .document([
                            ("license_key", .string(key)),
                            ("device_id", .string(deviceId))
                        ])),
                        ("u", .document([
                            ("$set", .document([
                                ("computer_name", .string(deviceName)),
                                ("os_info", .string(osInfo)),
                                ("last_verified_at", .int64(now)),
                                ("status", .string("ACTIVE"))
                            ])),
                            ("$setOnInsert", .document([
                                ("first_activated_at", .int64(now))
                            ]))
                        ])),
                        ("upsert", .bool(true))
                    ])
                ]))
            ]))

            if !isVerifyOnly {
                _ = try? await client.runCommand(database: db, command: MongoWireClient.BSONDoc([
                    ("insert", .string("audit_logs")),
                    ("documents", .array([
                        .document([
                            ("timestamp", .int64(now)),
                            ("event_type", .string("LICENSE_ACTIVATED")),
                            ("license_key", .string(key)),
                            ("device_id", .string(deviceId)),
                            ("actor", .string("CUSTOMER")),
                            ("details", .string("Activated on iPad '\(deviceName)' (\(osInfo))")),
                            ("ip_address", .string("MongoDB-Cloud"))
                        ])
                    ]))
                ]))
            }

            // Sync ALL AI keys (Gemini + Anthropic Claude + preferred provider) from Laptop License Manager's global_settings!
            if let settingsRes = try? await client.runCommand(database: db, command: MongoWireClient.BSONDoc([
                ("find", .string("global_settings")),
                ("filter", .document([]))
            ])),
               let sCur = settingsRes["cursor"]?.docValue,
               let sBatch = MongoWireClient.BSONDoc(sCur)["firstBatch"]?.arrayValue {
                for entry in sBatch {
                    guard let pairs = entry.docValue else { continue }
                    let doc = MongoWireClient.BSONDoc(pairs)
                    let k = doc["k"]?.stringValue ?? ""
                    let v = (doc["v"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if k == "gemini_api_key" && !v.isEmpty { cloudGeminiKey = v }
                    if k == "anthropic_api_key" && !v.isEmpty { cloudAnthropicKey = v }
                    if k == "ai_provider" && !v.isEmpty { cloudAIProvider = v.lowercased() }
                }
            }

            customerName = lic["customer_name"]?.stringValue ?? ""
            planName = lic["plan_name"]?.stringValue ?? (isLifetime ? "Lifetime" : "Active")
            isActivated = true
            var syncedKeys: [String] = []
            if !cloudGeminiKey.isEmpty { syncedKeys.append("Gemini") }
            if !cloudAnthropicKey.isEmpty { syncedKeys.append("Claude") }
            let keyNote = syncedKeys.isEmpty ? "" : " • Synced \(syncedKeys.joined(separator: " + ")) AI Key"
            statusMessage = "Cloud Active on \(deviceName) (\(planName))\(keyNote)."
        } catch {
            if !isVerifyOnly { isActivated = false }
            statusMessage = "Cloud sync failed: \(error.localizedDescription)"
        }
    }

    private func activateViaHTTP(baseURL: String, key: String) async {
        let cleanServer = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanServer)/api/v1/license/activate") else {
            isActivated = false
            statusMessage = "Invalid Central License Server URL."
            return
        }

        let payload: [String: Any] = [
            "license_key": key,
            "device_id": deviceId,
            "computer_name": deviceName,
            "os_info": osInfo,
            "client_nonce": UUID().uuidString
        ]

        do {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 12
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            if code == 200, (json["ok"] as? Bool == true || json["valid"] as? Bool == true) {
                isActivated = true
                statusMessage = "Activated via License Server on \(deviceName)."
            } else {
                isActivated = false
                statusMessage = (json["message"] as? String) ?? "Activation rejected (HTTP \(code))."
            }
        } catch {
            isActivated = false
            statusMessage = "Server unreachable: \(error.localizedDescription)"
        }
    }
}
