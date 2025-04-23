import CryptoKit
import Foundation

private let timeFormatter = ISO8601DateFormatter()

func log(_ log: String, level: LogsLevel) -> LogOutput {
    return LogOutput(
        log: "\(level.emoji) MADNetworking [\(timeFormatter.string(from: Date()))]: \(log)",
        level: level
    )
}

extension Encodable {
    func asDictionary() throws -> [String: Any]? {
        let data = try JSONEncoder().encode(self)
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
        return jsonObject as? [String: Any]
    }
}

extension Data {
    mutating func append(
        _ string: String,
        encoding: String.Encoding = .utf8
    ) {
        guard let data = string.data(using: encoding) else {
            return
        }
        append(data)
    }

    var sha256: String {
        SHA256.hash(data: self).compactMap { String(format: "%02x", $0) }.joined()
    }
}

extension String {
    func hmacSHA256(secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(self.utf8), using: key)
        return Data(signature).map { String(format: "%02hhx", $0) }.joined()
    }
}
