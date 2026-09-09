//
//  DataItem.swift
//  iOSEngineerCodeCheck
//

import Foundation

struct DataItem: Hashable, Identifiable, Codable {

    var fullName: String
    var language: String?
    var stargazersCount: Int
    var watchersCount: Int
    var forksCount: Int
    var openIssuesCount: Int
    var owner: Owner
    var marked: Bool?
}

extension Identifiable where Self: Hashable {
    var id: Self {
        self
    }
}

extension DataItem {
    struct Owner: Hashable, Codable {
        var avatarUrl: String
    }
}
