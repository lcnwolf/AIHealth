import Foundation

struct PromptBuilder {
    private let encoder: JSONEncoder
    private let template: String

    init(template: String = PromptTemplate.default) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.template = template
    }

    func prompt(from snapshot: HealthSnapshot) -> String {
        let data = (try? encoder.encode(snapshot)) ?? Data("{}".utf8)
        let json = String(decoding: data, as: UTF8.self)
        let combined = PromptTemplate.apply(template: template, json: json)
        if combined.hasSuffix("\n") {
            return combined
        }
        return combined + "\n"
    }
}
