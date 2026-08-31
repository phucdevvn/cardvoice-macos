import Foundation

struct KokoroVoice: Identifiable, Hashable {
    let id: Int
    let name: String
    let accent: String
    let gender: String

    var displayName: String { "\(name) · \(accent) \(gender)" }

    static let all: [KokoroVoice] = [
        .init(id: 0, name: "Default", accent: "American", gender: "female"),
        .init(id: 1, name: "Bella", accent: "American", gender: "female"),
        .init(id: 2, name: "Nicole", accent: "American", gender: "female"),
        .init(id: 3, name: "Sarah", accent: "American", gender: "female"),
        .init(id: 4, name: "Sky", accent: "American", gender: "female"),
        .init(id: 5, name: "Adam", accent: "American", gender: "male"),
        .init(id: 6, name: "Michael", accent: "American", gender: "male"),
        .init(id: 7, name: "Emma", accent: "British", gender: "female"),
        .init(id: 8, name: "Isabella", accent: "British", gender: "female"),
        .init(id: 9, name: "George", accent: "British", gender: "male"),
        .init(id: 10, name: "Lewis", accent: "British", gender: "male")
    ]
}
