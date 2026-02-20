//
//  RequestInterceptor.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/2/25.
//

import Alamofire
import Network
import Foundation

final class RequestInterceptor: Alamofire.RequestInterceptor {

    let gigaKey: String
    let yaKey: String

    private let saveGigaTokenKey = "saveGigaTokenKey"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let userDefaults = UserDefaults.standard

    var getGigaToken: String? {
        guard let token: GigaToken = object(forKey: saveGigaTokenKey),
              token.expiresAt > Date()
        else { return nil }

        return token.accessToken
    }

    init(gigaKey: String,
         yaKey: String) {
        self.gigaKey = gigaKey
        self.yaKey = yaKey
    }

    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {

        var urlRequest = urlRequest

        /// Set the Authorization header value using the access token.
        if urlRequest.url?.host() == "llm.api.cloud.yandex.net" {
            urlRequest.headers.add(.authorization(bearerToken: yaKey))
        } else {
            if let token = getGigaToken {
                urlRequest.headers.add(.authorization(bearerToken: token))
            } else {
                let headers: HTTPHeaders = [
                    "Content-Type": "application/x-www-form-urlencoded",
                    "Accept": "application/json",
                    "RqUID": "\(UUID().uuidString.lowercased())",
                    "Authorization": "Basic \(gigaKey)"
                ]

                let parameters: Parameters = ["scope": "GIGACHAT_API_PERS"]
                AF.request("https://ngw.devices.sberbank.ru:9443/api/v2/oauth",
                                method: .post,
                                parameters: parameters,
                                encoding: URLEncoding.httpBody,
                                headers: headers)
                .validate()
                .responseDecodable(of: GigaToken.self) { [weak self] response in
                    print(dump(response.result))
                    guard let self else { return }
                    switch response.result {
                    case .success(let token):
                        save(token, forKey: saveGigaTokenKey)
                        urlRequest.headers.add(.authorization(bearerToken: token.accessToken))
                        completion(.success(urlRequest))
                        return
                    case .failure(_ ): break
                    }
                }
                return
            }
        }

        completion(.success(urlRequest))
    }

    private func save(_ object: Encodable, forKey: String) {
        do {
            let data = try encoder.encode(object)
            userDefaults.set(data, forKey: forKey)
        } catch {
            print("Ошибка сохранения: \(error)")
        }
    }

    private func object<T:Decodable>(forKey: String) -> T? {
        guard let savedData = userDefaults.data(forKey: forKey) else { return nil }
        do {
            let object = try decoder.decode(T.self, from: savedData)
            return object
        } catch {
            print("Ошибка сохранения: \(error)")
        }
        return nil
    }

}
