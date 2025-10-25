import Foundation

struct HealthSnapshot: Codable {
    struct SleepMetrics: Codable {
        let lastNightHours: Double?
        let average7Days: Double?
        let bedtime: Date?
        let wakeUp: Date?
    }

    struct HRVMetrics: Codable {
        let today: Double?
        let baseline7Days: Double?
        let sampleCount: Int
        let sampleTime: Date?
        let device: String?
    }

    struct RestingHRMetrics: Codable {
        let today: Double?
        let baseline7Days: Double?
    }

    struct ActivityMetrics: Codable {
        let stepsToday: Double?
        let steps7DayAverage: Double?
        let activeEnergy: Double?
        let exerciseMinutes: Double?
        let standHours: Double?
    }

    struct WorkoutSummary: Codable {
        struct WorkoutDetail: Codable {
            let type: String
            let minutes: Double
            let date: Date
        }

        let workouts7Days: Int
        let workouts14Days: Int
        let workouts30Days: Int
        let daysSinceLastWorkout: Int?
        let lastWorkout: WorkoutDetail?
    }

    struct BodyMetrics: Codable {
        let weight: Double?
        let weight7DayAverage: Double?
        let bodyFatPercent: Double?
    }

    struct OxygenMetrics: Codable {
        let sleepAverage: Double?
    }

    struct RespirationMetrics: Codable {
        let sleepRate: Double?
        let baseline7Day: Double?
    }

    struct VOMetrics: Codable {
        let latest: Double?
        let previous: Double?
        let age: Int?
        let sex: String?
        let norm: Double?
        let date: Date?
        let context: String?
    }

    let date: Date
    let sleep: SleepMetrics?
    let hrv: HRVMetrics?
    let restingHR: RestingHRMetrics?
    let activity: ActivityMetrics?
    let workouts: WorkoutSummary?
    let body: BodyMetrics?
    let oxygen: OxygenMetrics?
    let respiration: RespirationMetrics?
    let vo2max: VOMetrics?
}
