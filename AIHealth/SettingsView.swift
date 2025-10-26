import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var apiKeyDraft: String = ""
    @State private var promptDraft: String = ""
    @State private var isSaved: Bool = false

    var body: some View {
        Form {
            Section {
                SecureField("sk-...", text: $apiKeyDraft)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            } header: {
                Text("API-ключ OpenAI")
            } footer: {
                Text("Ключ хранится локально и используется при отправке запросов.")
            }

            Section {
                TextEditor(text: $promptDraft)
                    .frame(minHeight: 260)
                    .font(.system(.body, design: .monospaced))
                Button("Сбросить промпт") {
                    promptDraft = PromptTemplate.default
                }
                .disabled(promptDraft == PromptTemplate.default)
            } header: {
                Text("Промпт")
            } footer: {
                Text("Шаблон должен содержать маркер \(PromptTemplate.placeholder), который будет заменён на JSON данных.")
            }

            Section {
                Button("Сохранить") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)

                if isSaved {
                    Text("Сохранено!")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Настройка запроса")
        .onAppear(perform: loadValues)
    }

    private func loadValues() {
        apiKeyDraft = settings.apiKey
        promptDraft = settings.promptTemplate
        isSaved = false
    }

    private func saveChanges() {
        settings.apiKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.promptTemplate = promptDraft
        isSaved = true
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
}
