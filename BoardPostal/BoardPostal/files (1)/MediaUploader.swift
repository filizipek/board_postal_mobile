import Foundation
import UIKit

// MARK: - MediaUploader
// One implementation of "upload a UIImage to /api/media/upload".
//
// Posts a multipart/form-data body with a UUID boundary, attaches the
// access token from KeychainService, and returns the MediaAsset shape
// the backend ships back. On HTTP 401 it triggers a token refresh via
// APIClient's interceptor (by sending any authenticated request — we
// use .myProfile as the cheap probe), re-reads the keychain, and
// retries the upload exactly once.
//
// Linking the returned MediaAsset to a trip (POST /api/trips/{id}/media)
// is the CALLER's job — this class only handles the upload side.

final class MediaUploader {
    static let shared = MediaUploader()
    private init() {}

    enum UploadError: LocalizedError {
        case imageEncodingFailed
        case missingToken
        case server(statusCode: Int)
        case decoding(String)

        var errorDescription: String? {
            switch self {
            case .imageEncodingFailed: return "Couldn't prepare the image for upload."
            case .missingToken:        return "Your session has expired. Please log in again."
            case .server(let code):    return "Upload failed (\(code)). Please try again."
            case .decoding(let msg):   return "Couldn't read server response: \(msg)"
            }
        }
    }

    /// Uploads a JPEG-encoded image to /api/media/upload.
    /// - Parameters:
    ///   - image: The image to upload.
    ///   - quality: JPEG compression quality (0.0–1.0). Default 0.82.
    /// - Returns: The decoded `MediaAsset` from the server.
    /// - Throws: `UploadError` on encoding failure, missing token,
    ///   non-200 status, or response-decoding failure.
    func upload(_ image: UIImage, quality: CGFloat = 0.82) async throws -> MediaAsset {
        guard let data = image.jpegData(compressionQuality: quality) else {
            throw UploadError.imageEncodingFailed
        }
        guard let token = KeychainService.shared.accessToken else {
            throw UploadError.missingToken
        }

        do {
            return try await performUpload(data: data, token: token)
        } catch UploadError.server(let code) where code == 401 {
            // Trigger APIClient's refresh-token interceptor by sending any
            // authenticated request. The body decode failing is fine — we
            // only need the side effect of a refreshed access token.
            _ = try? await APIClient.shared.requestVoid(.myProfile, method: .get)
            guard let freshToken = KeychainService.shared.accessToken else {
                throw UploadError.missingToken
            }
            return try await performUpload(data: data, token: freshToken)
        }
    }

    // MARK: - Private

    private func performUpload(data: Data, token: String) async throws -> MediaAsset {
        let boundary = UUID().uuidString
        var request = URLRequest(url: APIEndpoint.mediaUpload.url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var body = Data()
        let filename = "\(UUID().uuidString).jpg"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw UploadError.server(statusCode: code)
        }

        do {
            return try JSONDecoder.bpDecoder.decode(MediaAsset.self, from: responseData)
        } catch {
            throw UploadError.decoding(error.localizedDescription)
        }
    }
}
