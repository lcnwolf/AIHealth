import SwiftUI

struct ContentView: View {
    private let dataProvider = MockDataProvider()

    @State private var apiKey: String = ""
    @State private var isRequesting: Bool = false
    @State private var resultText: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("API-ключ OpenAI")) {
                    SecureField("sk-...", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }

                Section(footer: Text("Сейчас используются демо-данные вместо HealthKit.")) {
                    Button(action: checkHealth) {
                        HStack {
                            if isRequesting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            }
                            Text(isRequesting ? "Запрашиваем..." : "Проверить демо-данные")
                                .bold()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.isEmpty || isRequesting)

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }

                    if let resultText {
                        NavigationLink("Смотреть ответ", destination: ResultView(text: resultText))
                    }
                }

                Section(header: Text("Что включено в мок")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• Сон: 7.6 ч, базовый уровень 7.2 ч")
                        Text("• Пульс покоя: 52 против среднего 54")
                        Text("• Шаги: 12 480 против среднего 10 950")
                        Text("• VO₂max: 47.8 → 45.5")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AI Health")
        }
    }

    private func checkHealth() {
        guard !apiKey.isEmpty else {
            errorMessage = "Введите API-ключ"
            return
        }
        errorMessage = nil
        isRequesting = true

        Task {
            do {
                let snapshot = try await dataProvider.fetchSnapshot()
                let prompt = PromptBuilder().prompt(from: snapshot)
                let response = try await OpenAIService().sendPrompt(prompt, apiKey: apiKey)
                await MainActor.run {
                    resultText = response
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                isRequesting = false
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
