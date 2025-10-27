import Foundation

enum TokenEstimator {
    static func approximateTokenCount(for text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let characters = text.count
        let estimate = Double(characters) / 4.0
        return max(1, Int(ceil(estimate)))
    }
}
