import Foundation
import UIKit

@MainActor
final class LicenseService: ObservableObject {
    // Matches 2_SECURE_AI_Customer_App/MONGODB_URI.txt & license_client.py
    static let defaultCloudMongoURI = "mongodb+srv://mgnrega:gaurav2323@cluster0.8albao0.mongodb.net/?appName=Cluster0"
    static let licenseDBName = "lazyman_license_db"

    @Published var licenseKey: String {
        didSet { UserDefaults.standard.set(licenseKey, forKey: "secure_ai_license_key") }
    }
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "secure_ai_cloud_uri_v2") }
    }
    @Published var isActivated: Bool {
        didSet { UserDefaults.standard.set(isActivated, forKey: "secure_ai_activated_cloud_v2") }
    }
    @Published var customerName: String {
        didSet { UserDefaults.standard.set(customerName, forKey: "secure_ai_customer_name") }
    }
    @Published var planName: String {
        didSet { UserDefaults.standard.set(planName, forKey: "secure_ai_plan_name") }
    }
    @Published var cloudGeminiKey: String = ""
    @Published var statusMessage: String = "Enter your license key to activate with Cloud Database."
    @Published var isChecking: Bool = false

    let deviceId: String
    let deviceName: String
    let osInfo: String

    init() {
        self.licenseKey = UserDefaults.standard.string(forKey: "secure_ai_license_key") ?? ""
        let savedURI = UserDefaults.standard.string(forKey: "secure_ai_cloud_uri_v2") ?? ""
        self.serverURL = savedURI.isEmpty ? Self.defaultCloudMongoURI : savedURI
        self.isActivated = UserDefaults.standard.bool(forKey: "secure_ai_activated_cloud_v2")
        self.customerName = UserDefaults.standard.string(forKey: "secure_ai_customer_name") ?? ""
        self.planName = UserDefaults.standard.string(forKey: "secure_ai_plan_name") ?? ""
        self.deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "IPAD-PRO-UNKNOWN"
        self.deviceName = UIDevice.current.name
        self.osInfo = "iPadOS \(UIDevice.current.systemVersion)"
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

    /// Re-verifies an already activated license against the Cloud Database on launch.
    func verifyOnLaunch() async {
        guard isActivated, !licenseKey.isEmpty else { return }
        let target = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTarget = target.isEmpty ? Self.defaultCloudMongoURI : target
        guard effectiveTarget.hasPrefix("mongodb+srv://") || effectiveTarget.hasPrefix("mongodb://") else { return }
        await activateViaMongoDB(uri: effectiveTarget, key: licenseKey.uppercased(), isVerifyOnly: true)
    }

    // MARK: - Direct MongoDB Atlas Sync (100% Parity with PC Customer App & Laptop License Manager)
    private func activateViaMongoDB(uri: String, key: String, isVerifyOnly: Bool = false) async {
        do {
            let client = try MongoWireClient(uri: uri)
            defer { client.disconnect() }

            let now = try await client.connectAndAuthenticate()
            let db = Self.licenseDBName

            // 1. Find license in `licenses` collection
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

            // 2. Check existing devices for this key
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
                    if dId == deviceId && dStatus == "BLOCKED" {
                        thisDeviceBlocked = true
                    }
                    if dStatus == "ACTIVE" {
                        activeDevices.append(dId)
                    }
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

            // 3. Update `licenses` document (status = ACTIVE, activated_at = now, expires_at)
            var licSet: [(String, MongoWireClient.BSONValue)] = [
                ("status", .string("ACTIVE"))
            ]
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

            // 4. Upsert `devices` document so Laptop License Manager immediately shows this iPad!
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

            // 5. Write audit log entry (matches mongo_backend.py _log)
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

            // 6. Optional: pull shared Gemini API key from `global_settings` if configured in Admin App
            if let settingsRes = try? await client.runCommand(database: db, command: MongoWireClient.BSONDoc([
                ("find", .string("global_settings")),
                ("filter", .document([("k", .string("gemini_api_key"))])),
                ("limit", .int32(1))
            ])),
               let sCur = settingsRes["cursor"]?.docValue,
               let sBatch = MongoWireClient.BSONDoc(sCur)["firstBatch"]?.arrayValue,
               let sFirst = sBatch.first?.docValue,
               let gKey = MongoWireClient.BSONDoc(sFirst)["v"]?.stringValue,
               !gKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cloudGeminiKey = gKey.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            customerName = lic["customer_name"]?.stringValue ?? ""
            planName = lic["plan_name"]?.stringValue ?? (isLifetime ? "Lifetime" : "Active")
            isActivated = true
            statusMessage = "Cloud Database Synced! Active on \(deviceName) (\(planName))."
        } catch {
            if !isVerifyOnly {
                isActivated = false
            }
            statusMessage = "Cloud sync failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Optional HTTP Central License Server Support
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
