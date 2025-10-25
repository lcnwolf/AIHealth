import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var healthManager: HealthKitManager
    @State private var apiKey: String = ""
    @State private var isRequesting: Bool = false
    @State private var resultText: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            content
                .navigationTitle("AI Health")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Обновить") {
                            healthManager.resetAuthorizationStatus()
                            healthManager.requestAuthorizationIfNeeded()
                        }
                    }
                }
        }
        .task {
            healthManager.requestAuthorizationIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch healthManager.authorizationState {
        case .notDetermined:
            ProgressView("Запрашиваем доступ к здоровью…")
                .padding()
        case .denied:
            VStack(spacing: 16) {
                Text("Нужен доступ к данным здоровья")
                    .font(.headline)
                Text("Мы не можем работать без разрешения. Откройте Настройки → Здоровье → Источники и включите доступ для приложения.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                Button("Открыть настройки") {
                    healthManager.openSettings()
                }
            }
            .padding()
        case .authorized:
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API-ключ OpenAI")
                        .font(.headline)
                    SecureField("sk-...", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }

                Button(action: checkHealth) {
                    if isRequesting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("Проверить здоровье")
                            .bold()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.isEmpty || isRequesting)

                if let resultText {
                    NavigationLink("Смотреть ответ", destination: ResultView(text: resultText))
                }

                Spacer()
            }
            .padding()
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
                let snapshot = try await healthManager.fetchSnapshot()
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
            .environmentObject(HealthKitManager.preview)
    }
}
