import Foundation

public struct NetworkServiceConfiguration {
    
    public let storedToken: () -> String?
    public let authRequest: () async -> (any DecodableResponse & Requestable)?
    public let tokenFromResponse: (Decodable) -> String?
    
    public let decoder: JSONDecoder
    
    public let urlSessionConfiguration: URLSessionConfiguration

    public let ignoreTokenFromTokenManagerState: Bool

    public let log: (LogOutput) -> Void
    
    public init(
        storedToken: @escaping () -> String?,
        authRequest: @escaping () async -> (any Requestable & DecodableResponse)?,
        tokenFromResponse: @escaping (Decodable) -> String?,
        decoder: JSONDecoder,
        urlSessionConfiguration: URLSessionConfiguration,
        ignoreTokenFromTokenManagerState: Bool,
        log: @escaping (LogOutput) -> Void
    ) {
        self.storedToken = storedToken
        self.authRequest = authRequest
        self.tokenFromResponse = tokenFromResponse
        self.decoder = decoder
        self.urlSessionConfiguration = urlSessionConfiguration
        self.ignoreTokenFromTokenManagerState = ignoreTokenFromTokenManagerState
        self.log = log
    }
}

