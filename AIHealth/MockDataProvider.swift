import Foundation

/// Упрощённый источник мок-данных, имитирующий HealthKit.
struct MockDataProvider {
    func fetchSnapshot() async throws -> HealthSnapshot {
        try await Task.sleep(nanoseconds: 150_000_000) // лёгкая задержка, чтобы UI показывал спиннер
        return .mock
    }
}

extension HealthSnapshot {
    static var mock: HealthSnapshot {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let date = isoFormatter.date(from: "2025-10-25T09:42:00+02:00") ?? Date()
        let lastWorkoutDate = isoFormatter.date(from: "2025-10-24T18:10:00+02:00") ?? date.addingTimeInterval(-24 * 60 * 60)

        return HealthSnapshot(
            date: date,
            sleep: .init(
                lastNightHours: 7.6,
                average7Days: 7.2,
                bedtime: isoFormatter.date(from: "2025-10-24T23:45:00+02:00"),
                wakeUp: isoFormatter.date(from: "2025-10-25T07:20:00+02:00")
            ),
            hrv: .init(
                today: 61,
                baseline7Days: 54,
                sampleCount: 4,
                sampleTime: date,
                device: "Apple Watch"
            ),
            restingHR: .init(
                today: 52,
                baseline7Days: 54
            ),
            activity: .init(
                stepsToday: 12_480,
                steps7DayAverage: 10_950,
                activeEnergy: 720,
                exerciseMinutes: 44,
                standHours: 13
            ),
            workouts: .init(
                workouts7Days: 6,
                workouts14Days: 11,
                workouts30Days: 22,
                daysSinceLastWorkout: 1,
                lastWorkout: .init(
                    type: "run",
                    minutes: 45,
                    date: lastWorkoutDate
                )
            ),
            body: .init(
                weight: 78.0,
                weight7DayAverage: 78.2,
                bodyFatPercent: 16.2
            ),
            oxygen: .init(
                sleepAverage: 97
            ),
            respiration: .init(
                sleepRate: 13.4,
                baseline7Day: 13.8
            ),
            vo2max: .init(
                latest: 47.8,
                previous: 45.5,
                age: 26,
                sex: "male",
                norm: 43.0,
                date: lastWorkoutDate,
                context: "run"
            )
        )
    }
}
