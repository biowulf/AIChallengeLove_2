//
//  AIChallengeLove_2App.swift
//  AIChallengeLove_2
//
//  Created by Bolyachev Rostislav on 2/16/26.
//

import SwiftUI
import Alamofire

@main
struct AIChallengeLove_2App: App {
    private var network: NetworkService

    init() {
        let configuration = URLSessionConfiguration.af.default
        let interceptor = RequestInterceptor(
            gigaKey: "",
            yaKey: "")
        network = NetworkService(session: Session(configuration: configuration, interceptor: interceptor))
    }

    var body: some Scene {
        WindowGroup {
            ChatDetailView(viewModel: ChatDetailViewModel(network: network))
        }
    }
}
