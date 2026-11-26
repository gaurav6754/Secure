import Foundation
import Network
import CryptoKit
import CommonCrypto

/// Zero-dependency native Swift MongoDB Wire Protocol (OP_MSG + SCRAM-SHA-1 / SCRAM-SHA-256 + BSON + TLS)
/// Connects directly to MongoDB Atlas (`mongodb+srv://...`) from iPadOS without third-party packages.
final class MongoWireClient {
    enum MongoError: LocalizedError {
        case invalidURI
        case dnsFailed(String)
        case connectionFailed(String)
        case authFailed(String)
        case commandFailed(String)
        case protocolError(String)

        var errorDescription: String? {
            switch self {
            case .invalidURI: return "Invalid MongoDB connection URI."
            case .dnsFailed(let m): return "Cloud DNS lookup failed: \(m)"
            case .connectionFailed(let m): return "Cloud DB connection failed: \(m)"
            case .authFailed(let m): return "Cloud DB auth failed: \(m)"
            case .commandFailed(let m): return "Cloud DB error: \(m)"
            case .protocolError(let m): return "Cloud DB protocol error: \(m)"
            }
        }
    }

    // MARK: - Minimal BSON Value & Codec
    enum BSONValue {
        case double(Double)
        case string(String)
        case document([(String, BSONValue)])
        case array([BSONValue])
        case binary(UInt8, Data)
        case objectId(Data)
        case bool(Bool)
        case utcDateTime(Int64)
        case null
        case int32(Int32)
        case int64(Int64)

        var stringValue: String? {
            if case .string(let s) = self { return s }
            return nil
        }

        var int64Value: Int64? {
            switch self {
            case .int64(let v): return v
            case .int32(let v): return Int64(v)
            case .double(let v): return Int64(v)
            case .utcDateTime(let ms): return ms / 1000
            default: return nil
            }
        }

        var boolValue: Bool? {
            switch self {
            case .bool(let b): return b
            case .int32(let v): return v != 0
            case .int64(let v): return v != 0
            case .double(let v): return v != 0
            default: return nil
            }
        }

        var docValue: [(String, BSONValue)]? {
            if case .document(let d) = self { return d }
            return nil
        }

        var arrayValue: [BSONValue]? {
            if case .array(let a) = self { return a }
            return nil
        }

        var binaryData: Data? {
            if case .binary(_, let d) = self { return d }
            return nil
        }
    }

    struct BSONDoc {
        var pairs: [(String, BSONValue)]

        init(_ pairs: [(String, BSONValue)] = []) {
            self.pairs = pairs
        }

        subscript(_ key: String) -> BSONValue? {
            pairs.first(where: { $0.0 == key })?.1
        }

        func encode() -> Data {
            var body = Data()
            for (k, v) in pairs {
                BSONDoc.appendElement(key: k, value: v, to: &body)
            }
            body.append(0x00)
            var out = Data()
            var totalLen = Int32(body.count + 4).littleEndian
            out.append(Data(bytes: &totalLen, count: 4))
            out.append(body)
            return out
        }

        private static func appendElement(key: String, value: BSONValue, to body: inout Data) {
            let keyBytes = Data(key.utf8)
            switch value {
            case .double(let d):
                body.append(0x01)
                body.append(keyBytes); body.append(0x00)
                var bits = d.bitPattern.littleEndian
                body.append(Data(bytes: &bits, count: 8))
            case .string(let s):
                body.append(0x02)
                body.append(keyBytes); body.append(0x00)
                let bytes = Data(s.utf8)
                var len = Int32(bytes.count + 1).littleEndian
                body.append(Data(bytes: &len, count: 4))
                body.append(bytes); body.append(0x00)
            case .document(let sub):
                body.append(0x03)
                body.append(keyBytes); body.append(0x00)
                body.append(BSONDoc(sub).encode())
            case .array(let arr):
                body.append(0x04)
                body.append(keyBytes); body.append(0x00)
                let indexed = arr.enumerated().map { (String($0.offset), $0.element) }
                body.append(BSONDoc(indexed).encode())
            case .binary(let subtype, let data):
                body.append(0x05)
                body.append(keyBytes); body.append(0x00)
                var len = Int32(data.count).littleEndian
                body.append(Data(bytes: &len, count: 4))
                body.append(subtype)
                body.append(data)
            case .objectId(let oid):
                body.append(0x07)
                body.append(keyBytes); body.append(0x00)
                body.append(oid.prefix(12))
            case .bool(let b):
                body.append(0x08)
                body.append(keyBytes); body.append(0x00)
                body.append(b ? 0x01 : 0x00)
            case .utcDateTime(let ms):
                body.append(0x09)
                body.append(keyBytes); body.append(0x00)
                var v = ms.littleEndian
                body.append(Data(bytes: &v, count: 8))
            case .null:
                body.append(0x0A)
                body.append(keyBytes); body.append(0x00)
            case .int32(let i):
                body.append(0x10)
                body.append(keyBytes); body.append(0x00)
                var v = i.littleEndian
                body.append(Data(bytes: &v, count: 4))
            case .int64(let i):
                body.append(0x12)
                body.append(keyBytes); body.append(0x00)
                var v = i.littleEndian
                body.append(Data(bytes: &v, count: 8))
            }
        }

        static func decode(from data: Data, offset: inout Int) throws -> BSONDoc {
            guard offset + 4 <= data.count else { throw MongoError.protocolError("Truncated BSON length") }
            let docLen = Int(readInt32(data, offset))
            let endOffset = offset + docLen
            guard docLen >= 5, endOffset <= data.count else { throw MongoError.protocolError("Invalid BSON length \(docLen)") }
            offset += 4
            var pairs: [(String, BSONValue)] = []

            while offset < endOffset - 1 {
                let typeByte = data[offset]
                offset += 1
                if typeByte == 0x00 { break }
                let key = try readCString(data, offset: &offset)
                let val: BSONValue
                switch typeByte {
                case 0x01:
                    let bits = readUInt64(data, offset); offset += 8
                    val = .double(Double(bitPattern: bits))
                case 0x02, 0x0D, 0x0E:
                    let len = Int(readInt32(data, offset)); offset += 4
                    let strData = data.subdata(in: offset..<(offset + max(0, len - 1)))
                    offset += len
                    val = .string(String(data: strData, encoding: .utf8) ?? "")
                case 0x03:
                    let sub = try decode(from: data, offset: &offset)
                    val = .document(sub.pairs)
                case 0x04:
                    let sub = try decode(from: data, offset: &offset)
                    val = .array(sub.pairs.map { $0.1 })
                case 0x05:
                    let len = Int(readInt32(data, offset)); offset += 4
                    let subType = data[offset]; offset += 1
                    let bin = data.subdata(in: offset..<(offset + len))
                    offset += len
                    val = .binary(subType, bin)
                case 0x06, 0x0A, 0x7F, 0xFF:
                    val = .null
                case 0x07:
                    let oid = data.subdata(in: offset..<(offset + 12)); offset += 12
                    val = .objectId(oid)
                case 0x08:
                    let b = data[offset] != 0; offset += 1
                    val = .bool(b)
                case 0x09:
                    let ms = readInt64(data, offset); offset += 8
                    val = .utcDateTime(ms)
                case 0x0B:
                    _ = try readCString(data, offset: &offset)
                    _ = try readCString(data, offset: &offset)
                    val = .null
                case 0x10:
                    let i = readInt32(data, offset); offset += 4
                    val = .int32(i)
                case 0x11:
                    let ts = readInt64(data, offset); offset += 8
                    val = .int64(ts)
                case 0x12:
                    let i = readInt64(data, offset); offset += 8
                    val = .int64(i)
                case 0x13:
                    offset += 16
                    val = .null
                default:
                    throw MongoError.protocolError("Unsupported BSON type 0x\(String(typeByte, radix: 16))")
                }
                pairs.append((key, val))
            }
            offset = endOffset
            return BSONDoc(pairs)
        }

        private static func readCString(_ data: Data, offset: inout Int) throws -> String {
            var end = offset
            while end < data.count && data[end] != 0x00 { end += 1 }
            guard end < data.count else { throw MongoError.protocolError("Unterminated cstring") }
            let str = String(data: data.subdata(in: offset..<end), encoding: .utf8) ?? ""
            offset = end + 1
            return str
        }

        private static func readInt32(_ data: Data, _ offset: Int) -> Int32 {
            var v: Int32 = 0
            _ = withUnsafeMutableBytes(of: &v) { data.copyBytes(to: $0, from: offset..<(offset + 4)) }
            return Int32(littleEndian: v)
        }

        private static func readInt64(_ data: Data, _ offset: Int) -> Int64 {
            var v: Int64 = 0
            _ = withUnsafeMutableBytes(of: &v) { data.copyBytes(to: $0, from: offset..<(offset + 8)) }
            return Int64(littleEndian: v)
        }

        private static func readUInt64(_ data: Data, _ offset: Int) -> UInt64 {
            var v: UInt64 = 0
            _ = withUnsafeMutableBytes(of: &v) { data.copyBytes(to: $0, from: offset..<(offset + 8)) }
            return UInt64(littleEndian: v)
        }
    }

    // MARK: - Connection State
    private let username: String
    private let password: String
    private let srvHost: String
    private let isSRV: Bool
    private let directPort: UInt16
    private var connection: NWConnection?
    private var nextRequestId: Int32 = 1
    private let queue = DispatchQueue(label: "com.secureai.mongo.wire")

    init(uri: String) throws {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("mongodb+srv://") || trimmed.hasPrefix("mongodb://") else {
            throw MongoError.invalidURI
        }
        self.isSRV = trimmed.hasPrefix("mongodb+srv://")
        let normalized = trimmed
            .replacingOccurrences(of: "mongodb+srv://", with: "https://")
            .replacingOccurrences(of: "mongodb://", with: "https://")
        guard let comps = URLComponents(string: normalized),
              let host = comps.host, !host.isEmpty else {
            throw MongoError.invalidURI
        }
        self.username = comps.user ?? ""
        self.password = comps.password ?? ""
        self.srvHost = host
        self.directPort = UInt16(comps.port ?? 27017)
    }

    deinit {
        disconnect()
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    /// Resolves SRV host, connects via TLS, switches to writable primary, negotiates SCRAM-SHA-1 (Atlas default) or SCRAM-SHA-256.
    func connectAndAuthenticate() async throws -> Int64 {
        let seeds: [(String, UInt16)]
        if isSRV {
            seeds = try await resolveSRV(hostname: srvHost)
        } else {
            seeds = [(srvHost, directPort)]
        }
        guard let first = seeds.first else {
            throw MongoError.dnsFailed("No MongoDB hosts returned for \(srvHost)")
        }

        let helloCmd: BSONDoc = username.isEmpty
            ? BSONDoc([("hello", .int32(1))])
            : BSONDoc([("hello", .int32(1)), ("saslSupportedMechs", .string("admin.\(username)"))])

        try await openTLSConnection(host: first.0, port: first.1)
        var hello = try await runCommand(database: "admin", command: helloCmd)

        // If connected to a secondary node, reconnect directly to the writable primary
        if hello["isWritablePrimary"]?.boolValue != true,
           let primary = hello["primary"]?.stringValue {
            let parts = primary.split(separator: ":")
            let pHost = String(parts[0])
            let pPort = parts.count > 1 ? (UInt16(parts[1]) ?? 27017) : 27017
            disconnect()
            try await openTLSConnection(host: pHost, port: pPort)
            hello = try await runCommand(database: "admin", command: helloCmd)
        }

        if !username.isEmpty {
            let mechs = (hello["saslSupportedMechs"]?.arrayValue ?? []).compactMap { $0.stringValue }
            // MongoDB Atlas uses SCRAM-SHA-1 (SCRAM-SHA-256 is disabled on Atlas shared/M0 clusters).
            let preferSHA1 = mechs.contains("SCRAM-SHA-1") || !mechs.contains("SCRAM-SHA-256")
            if preferSHA1 {
                do {
                    try await authenticateSCRAMSHA1(username: username, password: password)
                } catch {
                    try await authenticateSCRAMSHA256(username: username, password: password)
                }
            } else {
                do {
                    try await authenticateSCRAMSHA256(username: username, password: password)
                } catch {
                    try await authenticateSCRAMSHA1(username: username, password: password)
                }
            }
        }

        let serverNow = hello["localTime"]?.int64Value ?? Int64(Date().timeIntervalSince1970)
        return serverNow
    }

    func runCommand(database: String, command: BSONDoc) async throws -> BSONDoc {
        var pairs = command.pairs
        if !pairs.contains(where: { $0.0 == "$db" }) {
            pairs.append(("$db", .string(database)))
        }
        let payloadDoc = BSONDoc(pairs).encode()

        let reqId = nextRequestId
        nextRequestId += 1

        var body = Data()
        var flags: UInt32 = 0
        body.append(Data(bytes: &flags, count: 4))
        body.append(0x00)
        body.append(payloadDoc)

        let totalLen = Int32(16 + body.count)
        var msg = Data()
        var leLen = totalLen.littleEndian
        var leReq = reqId.littleEndian
        var leRespTo: Int32 = 0
        var leOpCode = Int32(2013).littleEndian
        msg.append(Data(bytes: &leLen, count: 4))
        msg.append(Data(bytes: &leReq, count: 4))
        msg.append(Data(bytes: &leRespTo, count: 4))
        msg.append(Data(bytes: &leOpCode, count: 4))
        msg.append(body)

        try await sendAll(msg)

        let header = try await receiveExact(count: 16)
        var respLen: Int32 = 0
        _ = withUnsafeMutableBytes(of: &respLen) { header.copyBytes(to: $0, from: 0..<4) }
        let fullLen = Int(Int32(littleEndian: respLen))
        guard fullLen > 21 else { throw MongoError.protocolError("Short OP_MSG response (\(fullLen) bytes)") }

        let rest = try await receiveExact(count: fullLen - 16)
        var offset = 5
        let doc = try BSONDoc.decode(from: rest, offset: &offset)
        if let ok = doc["ok"]?.boolValue, !ok {
            let errMsg = doc["errmsg"]?.stringValue ?? "Command rejected by MongoDB"
            throw MongoError.commandFailed(errMsg)
        }
        return doc
    }

    // MARK: - SCRAM-SHA-1 Authentication (Required for MongoDB Atlas)
    private func authenticateSCRAMSHA1(username: String, password: String) async throws {
        let cleanUser = username.replacingOccurrences(of: "=", with: "=3D").replacingOccurrences(of: ",", with: "=2C")
        let clientNonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let clientFirstBare = "n=\(cleanUser),r=\(clientNonce)"
        let clientFirstMsg = "n,,\(clientFirstBare)"

        let startRes = try await runCommand(database: "admin", command: BSONDoc([
            ("saslStart", .int32(1)),
            ("mechanism", .string("SCRAM-SHA-1")),
            ("payload", .binary(0x00, Data(clientFirstMsg.utf8))),
            ("autoAuthorize", .int32(1))
        ]))

        guard let convId = startRes["conversationId"]?.int64Value,
              let serverFirstData = startRes["payload"]?.binaryData,
              let serverFirstMsg = String(data: serverFirstData, encoding: .utf8) else {
            throw MongoError.authFailed("Invalid SCRAM-SHA-1 saslStart response.")
        }

        let kv = parseScramKV(serverFirstMsg)
        guard let serverNonce = kv["r"], serverNonce.hasPrefix(clientNonce),
              let saltB64 = kv["s"], let saltData = Data(base64Encoded: saltB64),
              let iterStr = kv["i"], let iterations = UInt32(iterStr), iterations >= 1 else {
            throw MongoError.authFailed("Invalid SCRAM-SHA-1 challenge from server.")
        }

        // MongoDB SCRAM-SHA-1 hashes MD5("<username>:mongo:<password>") as lowercase hex before PBKDF2-SHA1
        let md5Input = Data("\(username):mongo:\(password)".utf8)
        let md5Hex = Insecure.MD5.hash(data: md5Input).map { String(format: "%02x", $0) }.joined()
        let saltedPassword = try pbkdf2(password: md5Hex, salt: saltData, iterations: iterations, algorithm: CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), keyLength: 20)
        let clientKey = hmacSHA1(key: saltedPassword, message: Data("Client Key".utf8))
        let storedKey = Data(Insecure.SHA1.hash(data: clientKey))
        let clientFinalWithoutProof = "c=biws,r=\(serverNonce)"
        let authMessage = "\(clientFirstBare),\(serverFirstMsg),\(clientFinalWithoutProof)"
        let clientSignature = hmacSHA1(key: storedKey, message: Data(authMessage.utf8))
        let clientProof = Data(zip(clientKey, clientSignature).map { $0 ^ $1 })
        let clientFinalMsg = "\(clientFinalWithoutProof),p=\(clientProof.base64EncodedString())"

        let cont1 = try await runCommand(database: "admin", command: BSONDoc([
            ("saslContinue", .int32(1)),
            ("conversationId", .int32(Int32(convId))),
            ("payload", .binary(0x00, Data(clientFinalMsg.utf8)))
        ]))

        if cont1["done"]?.boolValue != true {
            _ = try await runCommand(database: "admin", command: BSONDoc([
                ("saslContinue", .int32(1)),
                ("conversationId", .int32(Int32(convId))),
                ("payload", .binary(0x00, Data()))
            ]))
        }
    }

    // MARK: - SCRAM-SHA-256 Authentication (Fallback for Self-Hosted MongoDB)
    private func authenticateSCRAMSHA256(username: String, password: String) async throws {
        let cleanUser = username.replacingOccurrences(of: "=", with: "=3D").replacingOccurrences(of: ",", with: "=2C")
        let clientNonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let clientFirstBare = "n=\(cleanUser),r=\(clientNonce)"
        let clientFirstMsg = "n,,\(clientFirstBare)"

        let startRes = try await runCommand(database: "admin", command: BSONDoc([
            ("saslStart", .int32(1)),
            ("mechanism", .string("SCRAM-SHA-256")),
            ("payload", .binary(0x00, Data(clientFirstMsg.utf8))),
            ("autoAuthorize", .int32(1))
        ]))

        guard let convId = startRes["conversationId"]?.int64Value,
              let serverFirstData = startRes["payload"]?.binaryData,
              let serverFirstMsg = String(data: serverFirstData, encoding: .utf8) else {
            throw MongoError.authFailed("Invalid SCRAM-SHA-256 saslStart response.")
        }

        let kv = parseScramKV(serverFirstMsg)
        guard let serverNonce = kv["r"], serverNonce.hasPrefix(clientNonce),
              let saltB64 = kv["s"], let saltData = Data(base64Encoded: saltB64),
              let iterStr = kv["i"], let iterations = UInt32(iterStr), iterations >= 1 else {
            throw MongoError.authFailed("Invalid SCRAM-SHA-256 challenge from server.")
        }

        let saltedPassword = try pbkdf2(password: password, salt: saltData, iterations: iterations, algorithm: CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), keyLength: 32)
        let clientKey = hmacSHA256(key: saltedPassword, message: Data("Client Key".utf8))
        let storedKey = Data(SHA256.hash(data: clientKey))
        let clientFinalWithoutProof = "c=biws,r=\(serverNonce)"
        let authMessage = "\(clientFirstBare),\(serverFirstMsg),\(clientFinalWithoutProof)"
        let clientSignature = hmacSHA256(key: storedKey, message: Data(authMessage.utf8))
        let clientProof = Data(zip(clientKey, clientSignature).map { $0 ^ $1 })
        let clientFinalMsg = "\(clientFinalWithoutProof),p=\(clientProof.base64EncodedString())"

        let cont1 = try await runCommand(database: "admin", command: BSONDoc([
            ("saslContinue", .int32(1)),
            ("conversationId", .int32(Int32(convId))),
            ("payload", .binary(0x00, Data(clientFinalMsg.utf8)))
        ]))

        if cont1["done"]?.boolValue != true {
            _ = try await runCommand(database: "admin", command: BSONDoc([
                ("saslContinue", .int32(1)),
                ("conversationId", .int32(Int32(convId))),
                ("payload", .binary(0x00, Data()))
            ]))
        }
    }

    private func parseScramKV(_ s: String) -> [String: String] {
        var map: [String: String] = [:]
        for part in s.split(separator: ",") {
            if let eq = part.firstIndex(of: "=") {
                let k = String(part[..<eq])
                let v = String(part[part.index(after: eq)...])
                map[k] = v
            }
        }
        return map
    }

    private func hmacSHA1(key: Data, message: Data) -> Data {
        let symKey = SymmetricKey(data: key)
        return Data(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: symKey))
    }

    private func hmacSHA256(key: Data, message: Data) -> Data {
        let symKey = SymmetricKey(data: key)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: symKey))
    }

    private func pbkdf2(password: String, salt: Data, iterations: UInt32, algorithm: CCPseudoRandomAlgorithm, keyLength: Int) throws -> Data {
        let passData = Data(password.utf8)
        var derived = Data(count: keyLength)
        let status = derived.withUnsafeMutableBytes { derivedPtr in
            salt.withUnsafeBytes { saltPtr in
                passData.withUnsafeBytes { passPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passPtr.bindMemory(to: Int8.self).baseAddress,
                        passData.count,
                        saltPtr.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        algorithm,
                        iterations,
                        derivedPtr.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw MongoError.authFailed("PBKDF2 key derivation failed.") }
        return derived
    }

    // MARK: - DNS-over-HTTPS SRV Lookup
    private func resolveSRV(hostname: String) async throws -> [(String, UInt16)] {
        guard let url = URL(string: "https://dns.google/resolve?name=_mongodb._tcp.\(hostname)&type=SRV") else {
            throw MongoError.dnsFailed("Invalid SRV query URL")
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = json["Answer"] as? [[String: Any]] else {
            throw MongoError.dnsFailed("No SRV records found for \(hostname)")
        }
        var hosts: [(String, UInt16)] = []
        for ans in answers {
            guard let record = ans["data"] as? String else { continue }
            let parts = record.split(separator: " ")
            if parts.count >= 4, let port = UInt16(parts[2]) {
                let target = String(parts[3]).trimmingCharacters(in: CharacterSet(charactersIn: "."))
                hosts.append((target, port))
            }
        }
        return hosts
    }

    // MARK: - Native TLS Socket via Network.framework
    private func openTLSConnection(host: String, port: UInt16) async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw MongoError.connectionFailed("Invalid port \(port)")
        }
        let tlsOptions = NWProtocolTLS.Options()
        let params = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        self.connection = conn

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            conn.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    cont.resume()
                case .failed(let err):
                    resumed = true
                    cont.resume(throwing: MongoError.connectionFailed(err.localizedDescription))
                case .cancelled:
                    resumed = true
                    cont.resume(throwing: MongoError.connectionFailed("Connection cancelled"))
                default:
                    break
                }
            }
            conn.start(queue: queue)
        }
    }

    private func sendAll(_ data: Data) async throws {
        guard let conn = connection else { throw MongoError.connectionFailed("Socket closed") }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { err in
                if let err { cont.resume(throwing: MongoError.connectionFailed(err.localizedDescription)) }
                else { cont.resume() }
            })
        }
    }

    private func receiveExact(count: Int) async throws -> Data {
        guard let conn = connection else { throw MongoError.connectionFailed("Socket closed") }
        var buffer = Data()
        while buffer.count < count {
            let remaining = count - buffer.count
            let chunk: Data = try await withCheckedThrowingContinuation { cont in
                conn.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, isComplete, err in
                    if let err {
                        cont.resume(throwing: MongoError.connectionFailed(err.localizedDescription))
                    } else if let data, !data.isEmpty {
                        cont.resume(returning: data)
                    } else if isComplete {
                        cont.resume(throwing: MongoError.connectionFailed("Server closed connection"))
                    } else {
                        cont.resume(returning: Data())
                    }
                }
            }
            buffer.append(chunk)
        }
        return buffer
    }
}
