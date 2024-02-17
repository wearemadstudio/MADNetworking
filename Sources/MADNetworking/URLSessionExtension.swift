// A little hack so https://github.com/kean/Pulse/issues/113 will be resolved

import Foundation

class DummyURLSessionDataDelegate: NSObject, URLSessionDataDelegate { }

extension URLSession {
    /// Allows to track `URLSessionDataDelegate` using closure based call.
    /// By default if you use async interface or `completionHandler` based interface,
    /// URLSession won't notify `URLSessionDataDelegate`.
    public func dataTask(for request: URLRequest) async throws -> (Data, URLResponse) {
        var dataTask: URLSessionDataTask?

        let onSuccess: (Data, URLResponse) -> Void = { (data, response) in
            guard let dataTask, let dataDelegate = self.delegate as? URLSessionDataDelegate else {
                return
            }
            dataDelegate.urlSession?(self, dataTask: dataTask, didReceive: data)
            dataDelegate.urlSession?(self, task: dataTask, didCompleteWithError: nil)
        }
        let onError: (Error) -> Void = { error in
            guard let dataTask, let dataDelegate = self.delegate as? URLSessionDataDelegate else {
                return
            }
            dataDelegate.urlSession?(self, task: dataTask, didCompleteWithError: error)

        }
        let onCancel = {
            dataTask?.cancel()
        }

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                dataTask = self.dataTask(with: request) { data, response, error in
                    guard let data = data, let response = response else {
                        let error = error ?? URLError(.badServerResponse)
                        onError(error)
                        return continuation.resume(throwing: error)
                    }
                    onSuccess(data, response)
                    continuation.resume(returning: (data, response))
                }
                dataTask?.resume()
            }
        }, onCancel: {
            onCancel()
        })
    }
}
