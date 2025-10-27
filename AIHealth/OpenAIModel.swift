import Foundation

struct OpenAIModel: Identifiable, Hashable {
    struct Pricing: Hashable {
        let inputPricePerThousandTokens: Double
        let outputPricePerThousandTokens: Double

        func cost(inputTokens: Int, outputTokens: Int) -> Double {
            let inputCost = Double(inputTokens) / 1000.0 * inputPricePerThousandTokens
            let outputCost = Double(outputTokens) / 1000.0 * outputPricePerThousandTokens
            return inputCost + outputCost
        }
    }

    let id: String
    let displayName: String
    let contextWindow: Int
    let pricing: Pricing
    let description: String

    func costForRequests(count: Int, inputTokens: Int, outputTokens: Int) -> Double {
        pricing.cost(inputTokens: inputTokens, outputTokens: outputTokens) * Double(count)
    }
}

extension OpenAIModel {
    static let catalog: [OpenAIModel] = [
        OpenAIModel(
            id: "gpt-4o-mini",
            displayName: "GPT-4o mini",
            contextWindow: 128_000,
            pricing: .init(inputPricePerThousandTokens: 0.00015, outputPricePerThousandTokens: 0.0006),
            description: "Быстрая и дешёвая модель, оптимальна для черновой отладки промптов."
        ),
        OpenAIModel(
            id: "gpt-4o",
            displayName: "GPT-4o",
            contextWindow: 128_000,
            pricing: .init(inputPricePerThousandTokens: 0.005, outputPricePerThousandTokens: 0.015),
            description: "Основная универсальная модель с хорошим качеством и скоростью."
        ),
        OpenAIModel(
            id: "gpt-4.1-mini",
            displayName: "GPT-4.1 Mini",
            contextWindow: 128_000,
            pricing: .init(inputPricePerThousandTokens: 0.003, outputPricePerThousandTokens: 0.015),
            description: "Баланс цены и качества в линейке GPT-4.1."
        ),
        OpenAIModel(
            id: "gpt-4.1",
            displayName: "GPT-4.1",
            contextWindow: 128_000,
            pricing: .init(inputPricePerThousandTokens: 0.015, outputPricePerThousandTokens: 0.06),
            description: "Флагман с расширенными возможностями рассуждений."
        ),
        OpenAIModel(
            id: "o1-mini",
            displayName: "o1 Mini",
            contextWindow: 128_000,
            pricing: .init(inputPricePerThousandTokens: 0.003, outputPricePerThousandTokens: 0.012),
            description: "Улучшенная reasoning-модель с умеренной ценой."
        ),
        OpenAIModel(
            id: "o1-preview",
            displayName: "o1 Preview",
            contextWindow: 128_000,
            pricing: .init(inputPricePerThousandTokens: 0.015, outputPricePerThousandTokens: 0.06),
            description: "Последнее поколение reasoning-моделей с максимальным качеством."
        ),
        OpenAIModel(
            id: "gpt-3.5-turbo-0125",
            displayName: "GPT-3.5 Turbo",
            contextWindow: 16_000,
            pricing: .init(inputPricePerThousandTokens: 0.0005, outputPricePerThousandTokens: 0.0015),
            description: "Проверенный бюджетный вариант для простых сценариев."
        )
    ]
}
