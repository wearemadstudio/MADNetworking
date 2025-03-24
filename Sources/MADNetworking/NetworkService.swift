import Foundation
import Pulse

/// Represents HTTP methods supported by the networking library
public enum HttpMethod: String {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
    case put = "PUT"
    case patch = "PATCH"
}

/// Protocol that defines the requirements for making network requests
///
/// Use this protocol to create request types that can be sent using `NetworkService`.
/// The protocol provides default implementations for optional properties.
///
/// Example:
/// ```swift
/// struct LoginRequest: Requestable & DecodableResponse {
///     // Define custom error payload for authentication errors
///     struct ErrorPayload: Decodable, Equatable {
///         let message: String
///         let code: String
///     }
///
///     // Response type for successful login
///     struct Response: Decodable {
///         let token: String
///     }
///
///     typealias ResponseType = Response
///
///     var url: URL { URL(string: "https://api.example.com/login")! }
///     var method: HttpMethod { .post }
///     var parameters: Encodable? { LoginParameters() }
/// }
/// ```
public protocol Requestable {
    /// The type of error payload that can be returned for this request
    /// Defaults to `EmptyErrorPayload` if not specified
    associatedtype ErrorPayload: Decodable & Equatable = EmptyErrorPayload
    
    /// The URL for the request
    var url: URL { get }
    
    /// The HTTP method to use for the request
    var method: HttpMethod { get }
    
    /// Optional headers to include in the request
    var headers: [String: String]? { get }
    
    /// Optional parameters to include in the request body or query string
    var parameters: Encodable? { get }
    
    /// Optional multipart form data for file uploads
    var multipart: MultipartRequest? { get }
}

/// A default empty error payload type used when no specific error payload is needed
public struct EmptyErrorPayload: Decodable, Equatable {}

public extension Requestable {
    /// Default implementation for multipart request
    var multipart: MultipartRequest? { nil }
    
    /// Default type alias for error payload
    typealias ErrorPayload = EmptyErrorPayload
}

/// Protocol that defines the response type for a request
///
/// Use this protocol along with `Requestable` to specify the expected response type
/// for your network requests.
///
/// Example:
/// ```swift
/// struct UserProfileRequest: Requestable & DecodableResponse {
///     struct Response: Decodable {
///         let id: String
///         let name: String
///     }
///
///     typealias ResponseType = Response
///     // ... other request properties
/// }
/// ```
public protocol DecodableResponse {
    /// The type that the response will be decoded into
    associatedtype ResponseType: Decodable
}

/// Defines the level of logging for network operations
public enum LogsLevel {
    case error
    
    var emoji: String {
        switch self {
        case .error:
            return "🛑"
        }
    }
}

/// Represents a log output with its level and message
public struct LogOutput {
    public let log: String
    public let level: LogsLevel
}

/// Represents various network-related errors that can occur during requests
///
/// This error type is generic over the error payload type, allowing for type-safe
/// error handling specific to each request.
///
/// Example:
/// ```swift
/// do {
///     let result = try await networkService.send(request: loginRequest)
/// } catch let error as NetworkError<LoginRequest.ErrorPayload> {
///     switch error {
///     case .clientError(let statusCode, let errorPayload):
///         if let errorPayload = errorPayload {
///             print("Login failed: \(errorPayload.message)")
///         }
///     default:
///         print("Other error occurred")
///     }
/// }
/// ```
public enum NetworkError<ErrorPayload: Decodable & Equatable>: Error, Equatable {
    /// Request marked as required for auth, but no auth token was provided
    case tokenNotFound
    
    /// No URL Response was received
    case invalidResponse
    
    /// Connection issue (no network, etc)
    case networkingError
    
    /// Client error (400...499) with optional error payload
    case clientError(Int, ErrorPayload?)
    
    /// Server error (500...599)
    case serverError(Int)
    
    /// Received an unexpected status code
    case unexpectedStatusCode(Int)
    
    /// Request was cancelled
    case cancelled
}

/// A service class that handles network requests
///
/// This class provides a type-safe way to make network requests with proper error handling
/// and authentication support.
///
/// Example:
/// ```swift
/// let configuration = NetworkServiceConfiguration(
///     storedToken: { UserDefaults.standard.string(forKey: "authToken") },
///     authRequest: { LoginRequest() },
///     tokenFromResponse: { response in
///         guard let response = response as? LoginRequest.Response else { return nil }
///         return response.token
///     },
///     decoder: JSONDecoder(),
///     urlSessionConfiguration: .default,
///     log: { print($0.log) }
/// )
///
/// let networkService = NetworkService(configuration: configuration)
/// ```
public class NetworkService {
    private let tokenManager: TokenManager
    private let configuration: NetworkServiceConfiguration
    private let urlSession: URLSessionProxy
    private let decoder: JSONDecoder
    private let log: (LogOutput) -> Void
    
    /// Initialize a new network service with the provided configuration
    ///
    /// - Parameter configuration: The configuration to use for the network service
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

    /// Forces an update of the authentication token
    public func forceUpdateToken() async {
        await tokenManager.forceUpdateToken()
    }

    /// Sends a network request and returns the decoded response
    ///
    /// - Parameters:
    ///   - request: The request to send
    ///   - unauthorized: Whether to skip authentication for this request
    /// - Returns: The decoded response of type `T.ResponseType`
    /// - Throws: `NetworkError` if the request fails
    ///
    /// Example:
    /// ```swift
    /// let request = UserProfileRequest()
    /// do {
    ///     let profile = try await networkService.send(request: request)
    ///     print("Profile loaded: \(profile.name)")
    /// } catch {
    ///     print("Failed to load profile: \(error)")
    /// }
    /// ```
    public func send<T: Requestable & DecodableResponse>(request: T, unauthorized: Bool = false) async throws -> T.ResponseType {
        var token: String?
        if unauthorized == false {
            guard let savedToken = try await tokenManager.getToken() else {
                throw NetworkError<T.ErrorPayload>.tokenNotFound
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
                throw NetworkError<T.ErrorPayload>.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200..<400:
                break
            case 400..<500:
                let errorPayload: T.ErrorPayload?
                if T.ErrorPayload.self == EmptyErrorPayload.self {
                    errorPayload = EmptyErrorPayload() as? T.ErrorPayload
                } else {
                    errorPayload = try? decoder.decode(T.ErrorPayload.self, from: data)
                }
                throw NetworkError<T.ErrorPayload>.clientError(httpResponse.statusCode, errorPayload)
            case 500..<600:
                throw NetworkError<T.ErrorPayload>.serverError(httpResponse.statusCode)
            default:
                throw NetworkError<T.ErrorPayload>.unexpectedStatusCode(httpResponse.statusCode)
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
            throw NetworkError<T.ErrorPayload>.networkingError
        } catch let error as URLError where
                    error.code == .cancelled
        {
            throw NetworkError<T.ErrorPayload>.cancelled
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
    }
}
