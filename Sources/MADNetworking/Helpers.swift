import Foundation

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
}

func log(_ log: String, level: LogsLevel) -> LogOutput {
    return LogOutput(
        log: "\(level.emoji) MADNetworking [\(timeFormatter.string(from: Date()))]: \(log)",
        level: level
    )
}

private let timeFormatter = ISO8601DateFormatter()
