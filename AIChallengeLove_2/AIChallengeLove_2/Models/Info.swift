//
//  Info.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/11/25.
//

struct Info: Codable {
    var appSession: [GPTAPI : SessionGPT] = [:]
    var session: [GPTAPI : SessionGPT] = [:]
    var request: [GPTAPI : SessionGPT] = [:]
}

struct SessionGPT: Codable {
    var input: Int
    var output: Int
    var total: Int
}
