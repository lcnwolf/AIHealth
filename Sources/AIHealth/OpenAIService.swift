import Foundation

struct OpenAIService {
    enum ServiceError: LocalizedError {
        case invalidResponse
        case emptyMessage

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Не удалось разобрать ответ OpenAI"
            case .emptyMessage:
                return "Пустой ответ от модели"
            }
        }
    }

    func sendPrompt(_ prompt: String, apiKey: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                [
                    "role": "system",
                    "content": "Вы — дружественный помощник по здоровью."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let serverMessage = String(data: data, encoding: .utf8) ?? ""
            if let http = response as? HTTPURLResponse {
                throw NSError(domain: "OpenAI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: serverMessage])
            } else {
                throw ServiceError.invalidResponse
            }
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let message = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
            throw ServiceError.emptyMessage
        }
        return message
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}
