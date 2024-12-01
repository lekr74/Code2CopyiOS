import Foundation

struct ScannedCode: Identifiable, Codable, Equatable {
    var id = UUID()
    var content: String
    var type: String // Propriété pour le type de code
    var timestamp: Date

    init(content: String, type: String) {
        self.content = content
        self.type = type
        self.timestamp = Date()
    }

    // Implémentation de Equatable pour comparer les objets
    static func ==(lhs: ScannedCode, rhs: ScannedCode) -> Bool {
        return lhs.content == rhs.content && lhs.type == rhs.type
    }
}
