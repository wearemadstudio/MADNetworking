import XCTest
@testable import MADNetworking

struct EmptyData: Codable { }

struct BaseResponseModel<T: Decodable>: Decodable {
    var status: String?
    var payload: T?
    var text: String?
}

struct AuthRequest: Requestable & DecodableResponse {
    struct Parameters: Encodable {
        var deviceId: String { UUID().uuidString }
    }
    
    struct Response: Decodable {
        var authToken: String?
    }
    
    var url: URL { URL(string: "https://api.byairapp.com/auth/anon")! }
    var method: MADNetworking.HttpMethod { .post }
    var headers: [String : String]? { [:] }
    var parameters: Encodable? { Parameters() }
    var multipart: MultipartRequest? { nil }

    typealias ResponseType = BaseResponseModel<Response>
    
}

struct AirportsDetailsRequest: Requestable & DecodableResponse {
    struct Response: Decodable {
        var id: Int?
        var name: String?
    }
    
    var url: URL { URL(string: "https://api.byairapp.com/airport/1")! }
    var method: MADNetworking.HttpMethod { .get }
    var headers: [String : String]? { [:] }
    var parameters: Encodable? { EmptyData() }
    var multipart: MultipartRequest? { nil }

    typealias ResponseType = BaseResponseModel<Response>
}

final class MADNetworkingTests: XCTestCase {
    func simpleTest() async throws {
        let storedToken: () -> String? = {
            return nil
        }
        let authRequest: () -> (any DecodableResponse & Requestable) = {
            return AuthRequest()
        }
        let service = NetworkService(
            configuration: NetworkServiceConfiguration(
                storedToken: { nil },
                authRequest: authRequest,
                tokenFromResponse: {
                    guard let response = $0 as? AuthRequest.Response else { return nil }
                    return response.authToken
                },
                decoder: JSONDecoder(),
                urlSessionConfiguration: .default,
                log: { output in
                    print(output.log)
                }
            )
        )
        do {
            let result = try await service.send(request: AirportsDetailsRequest())
            print(result)
        } catch let error {
            print(error)
        }
    }
}
