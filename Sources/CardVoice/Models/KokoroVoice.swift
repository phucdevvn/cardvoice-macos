import Foundation

struct KokoroVoice: Identifiable, Hashable {
    let id: Int
    let name: String
    let accent: String
    let gender: String

    var roleLabel: String { "\(accent == "American" ? "US" : "UK") \(gender)" }
    var displayName: String { "\(name) — \(roleLabel)" }

    static let all: [KokoroVoice] = [
        .init(id: 4, name: "Sky", accent: "American", gender: "female"),
        .init(id: 6, name: "Michael", accent: "American", gender: "male"),
        .init(id: 7, name: "Emma", accent: "British", gender: "female"),
        .init(id: 9, name: "George", accent: "British", gender: "male")
    ]
}
