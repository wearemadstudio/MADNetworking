import Foundation

private actor TokenState {
    var token: String?
    var refreshTask: Task<String?, Error>?
    
    func update(token: String?) {
        self.token = token
    }
    
    func update(refreshTask: Task<String?, Error>?) {
        self.refreshTask = refreshTask
    }
}

class TokenManager {
            
    // MARK: - Private properties
    
    private let storedToken: () -> String?
    private let authRequest: () -> (any Requestable & DecodableResponse)?
    private let tokenFromResponse: (Decodable) -> String?
    
    private var tokenState = TokenState()
    
    private weak var networkService: NetworkService?
    
    // MARK: - Lifecycle
    
    init(
        storedToken: @escaping () -> String?,
        authRequest: @escaping () -> (any Requestable & DecodableResponse)?,
        tokenFromResponse: @escaping (Decodable) -> String?
    ) {
        self.storedToken = storedToken
        self.authRequest = authRequest
        self.tokenFromResponse = tokenFromResponse
    }
    
    // MARK: - Methods
    
    func getToken() async throws -> String? {
        return try await fetchToken()
    }
    
    func setNetworkService(_ networkService: NetworkService) {
        self.networkService = networkService
    }
    
    private func fetchToken() async throws -> String? {
        if let token = await tokenState.token { // We already have a token
            return token
        }
        if let token = storedToken() { // We fetched a token from provider
            await tokenState.update(token: token)
            return token
        }
        if let task = await tokenState.refreshTask { // We already refreshing token
            return try await task.value
        }
        let refreshTask = Task<String?, Error> {
            var token: String?
            if let request = authRequest(), let response = try await networkService?.send(request: request, unauthorized: true) {
                token = tokenFromResponse(response)
            }
            await tokenState.update(token: token)
            return token
        }
        await tokenState.update(refreshTask: refreshTask)
        return try await refreshTask.value
    }
}
