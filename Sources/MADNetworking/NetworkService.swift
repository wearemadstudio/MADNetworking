import Foundation
import Pulse

public enum HttpMethod: String {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
    case put = "PUT"
    case patch = "PATCH"
}

public enum RequestSignType {
    case none
    case hmacSHA256(secret: String)
}

public protocol Requestable {
    var url: URL { get }
    var method: HttpMethod { get }
    var headers: [String: String]? { get }
    var parameters: Encodable? { get }
    var multipart: MultipartRequest? { get }
    var signType: RequestSignType { get }
}

public extension Requestable {
    var multipart: MultipartRequest? { nil }
}

public protocol DecodableResponse {
    associatedtype ResponseType: Decodable
}

public enum LogsLevel {
    case error
    
    var emoji: String {
        switch self {
        case .error:
            return "🛑"
        }
    }
}

public struct LogOutput {
    public let log: String
    public let level: LogsLevel
}

public enum NetworkError: Error, Equatable {
    case tokenNotFound // Request marked as required for auth, but no auth token was provided
    case invalidResponse // No URL Response
    case networkingError // Connection issue (no network, etc)
    case clientError(Int) // 400...499
    case serverError(Int) // 500...599
    case unexpectedStatusCode(Int)
    case cancelled // Request was cancelled. In many cases this should be ignored
}

public class NetworkService {
    
    private let tokenManager: TokenManager
    private let configuration: NetworkServiceConfiguration
    private let urlSession: URLSessionProxy
    private let decoder: JSONDecoder
    private let log: (LogOutput) -> Void
    
    public init(
        configuration: NetworkServiceConfiguration
    ) {
        self.configuration = configuration
        self.tokenManager = TokenManager(
            storedToken: configuration.storedToken,
            authRequest: configuration.authRequest,
            tokenFromResponse: configuration.tokenFromResponse,
            ignoreTokenFromState: configuration.ignoreTokenFromTokenManagerState
        )
        self.urlSession = URLSessionProxy(configuration: configuration.urlSessionConfiguration)
        self.decoder = configuration.decoder
        self.log = configuration.log
        
        self.tokenManager.setNetworkService(self)
    }

    public func forceUpdateToken() async {
        await tokenManager.forceUpdateToken()
    }

    public func send<T: Requestable & DecodableResponse>(request: T, unauthorized: Bool = false) async throws -> T.ResponseType {
        var token: String?
        if unauthorized == false {
            guard let savedToken = try await tokenManager.getToken() else {
                throw NetworkError.tokenNotFound
            }
            token = savedToken
        }

        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        if let token {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let multipart = request.multipart {
            urlRequest.setValue(multipart.httpContentTypeHeaderValue, forHTTPHeaderField: "Content-Type")
        }

        prepare(&urlRequest, with: request)
        
        do {
            let (data, response) = try await urlSession.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200..<400:
                break
            case 400..<500:
                throw NetworkError.clientError(httpResponse.statusCode)
            case 500..<600:
                throw NetworkError.serverError(httpResponse.statusCode)
            default:
                throw NetworkError.unexpectedStatusCode(httpResponse.statusCode)
            }
            
            let decodedResponse = try await Task {
                return try decoder.decode(T.ResponseType.self, from: data)
            }.value
            return decodedResponse
        } catch let error as URLError where
                    error.code == .notConnectedToInternet ||
                    error.code == .cannotFindHost ||
                    error.code == .cannotConnectToHost ||
                    error.code == .timedOut ||
                    error.code == .networkConnectionLost ||
                    error.code == .dnsLookupFailed ||
                    error.code == .httpTooManyRedirects ||
                    error.code == .resourceUnavailable ||
                    error.code == .dataNotAllowed
        {
            throw NetworkError.networkingError
        } catch let error as URLError where
                    error.code == .cancelled
        {
            throw NetworkError.cancelled
        }
        catch { throw error }
    }

    private func prepare<T: Requestable>(_ urlRequest: inout URLRequest, with request: T) {
        switch request.method {
        case .get:
            if let parameters = request.parameters {
                do {
                    if let dictionary = try parameters.asDictionary() {
                        var urlComponents = URLComponents(url: request.url, resolvingAgainstBaseURL: false)!
                        urlComponents.queryItems = dictionary.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
                        if !(urlComponents.queryItems?.isEmpty ?? true) {
                            urlRequest.url = urlComponents.url
                        }
                    }
                } catch {
                    let logMessage = MADNetworking.log("Params encode error: \(error.localizedDescription)", level: .error)
                    log(logMessage)
                }
            }
        default:
            if let parameters = request.parameters {
                do {
                    let jsonData = try JSONEncoder().encode(parameters)
                    urlRequest.httpBody = jsonData
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                } catch {
                    let logMessage = MADNetworking.log("Params encode error: \(error.localizedDescription)", level: .error)
                    log(logMessage)
                }
            } else if let multipart = request.multipart?.httpBody {
                urlRequest.httpBody = multipart
            }
        }
        request.headers?.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        switch request.signType {
        case .none:
            break
        case let .hmacSHA256(secret):
            let timestamp = Int(Date().timeIntervalSince1970)
            let urlString = urlRequest.url?.absoluteString
            let body = urlRequest.httpBody?.sha256
            let canonicalString = [urlString, timestamp.description, body].compactMap { $0 }.joined(separator: "|")
            let hmac = canonicalString.hmacSHA256(secret: secret)
            let additionalHeaders: [String: String] = [
                "X-Signature": hmac,
                "X-Timestamp": timestamp.description
            ]
            additionalHeaders.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        }
    }
}
