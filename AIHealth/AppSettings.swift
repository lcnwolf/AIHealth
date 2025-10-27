import Foundation
import Combine

final class AppSettings: ObservableObject {
    private enum Keys {
        static let apiKey = "app.apiKey"
        static let promptTemplate = "app.promptTemplate"
        static let selectedModelID = "app.selectedModelID"
    }

    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: Keys.apiKey) }
    }

    @Published var promptTemplate: String {
        didSet { UserDefaults.standard.set(promptTemplate, forKey: Keys.promptTemplate) }
    }

    @Published var selectedModelID: String {
        didSet { UserDefaults.standard.set(selectedModelID, forKey: Keys.selectedModelID) }
    }

    let availableModels: [OpenAIModel]
    let estimatedCompletionTokens: Int = 450

    var selectedModel: OpenAIModel {
        availableModels.first { $0.id == selectedModelID } ?? availableModels[0]
    }

    init(userDefaults: UserDefaults = .standard, models: [OpenAIModel] = OpenAIModel.catalog) {
        self.availableModels = models
        self.apiKey = userDefaults.string(forKey: Keys.apiKey) ?? ""
        self.promptTemplate = userDefaults.string(forKey: Keys.promptTemplate) ?? PromptTemplate.default
        self.selectedModelID = userDefaults.string(forKey: Keys.selectedModelID) ?? models.first?.id ?? "gpt-4o-mini"

        if !models.contains(where: { $0.id == selectedModelID }) {
            self.selectedModelID = models.first?.id ?? "gpt-4o-mini"
        }
    }

    func resetPromptTemplate() {
        promptTemplate = PromptTemplate.default
    }
}
