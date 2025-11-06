import Foundation

struct RandomHealthDataGenerator {
    static func generateSnapshot(referenceDate: Date = Date()) -> HealthSnapshot {
        let calendar = Calendar.current
        let date = referenceDate

        let sleep = HealthSnapshot.SleepMetrics(
            lastNightHours: Double.random(in: 5.0...9.5),
            average7Days: Double.random(in: 5.5...9.0),
            bedtime: Bool.random() ? calendar.date(byAdding: .hour, value: -Int.random(in: 7...10), to: date) : nil,
            wakeUp: Bool.random() ? calendar.date(byAdding: .hour, value: -Int.random(in: 0...2), to: date) : nil
        )

        let hrvToday = Double.random(in: 35...95)
        let hrvBaseline = hrvToday + Double.random(in: -8...8)
        let hrv = HealthSnapshot.HRVMetrics(
            today: hrvToday,
            baseline7Days: hrvBaseline,
            sampleCount: Bool.random() ? Int.random(in: 2...10) : nil,
            sampleTime: Bool.random() ? calendar.date(byAdding: .hour, value: -Int.random(in: 1...8), to: date) : nil,
            device: Bool.random() ? ["Apple Watch", "iPhone", "Oura Ring"].randomElement() : nil
        )

        let restingHR = HealthSnapshot.RestingHRMetrics(
            today: Double.random(in: 45...70),
            baseline7Days: Double.random(in: 45...75)
        )

        let activity = HealthSnapshot.ActivityMetrics(
            stepsToday: Double.random(in: 3_000...18_000),
            steps7DayAverage: Double.random(in: 4_000...15_000),
            activeEnergy: Double.random(in: 300...1_000),
            exerciseMinutes: Double.random(in: 10...90),
            standHours: Double.random(in: 6...16)
        )

        let workouts7 = Int.random(in: 0...8)
        let workouts14 = workouts7 + Int.random(in: 0...6)
        let workouts30 = workouts14 + Int.random(in: 0...10)
        let daysSinceWorkout = workouts7 == 0 ? Int.random(in: 5...10) : Int.random(in: 0...5)

        let workoutTypes = ["run", "strength", "cycling", "swim", "yoga", "hiit"]
        let lastWorkoutDetail: HealthSnapshot.WorkoutSummary.WorkoutDetail? = {
            guard workouts7 > 0 else { return nil }
            let lastWorkoutDate = calendar.date(byAdding: .day, value: -Int.random(in: 0...daysSinceWorkout), to: date)
            return .init(
                type: workoutTypes.randomElement(),
                minutes: Double.random(in: 25...90),
                date: lastWorkoutDate
            )
        }()

        let workouts = HealthSnapshot.WorkoutSummary(
            workouts7Days: workouts7,
            workouts14Days: workouts14,
            workouts30Days: workouts30,
            daysSinceLastWorkout: daysSinceWorkout,
            lastWorkout: lastWorkoutDetail
        )

        let weight = Double.random(in: 50...110)
        let weightAverage = weight + Double.random(in: -1.5...1.5)
        let body = HealthSnapshot.BodyMetrics(
            weight: weight,
            weight7DayAverage: weightAverage,
            bodyFatPercent: Bool.random() ? Double.random(in: 8...30) : nil
        )

        let oxygen = Bool.random() ? HealthSnapshot.OxygenMetrics(sleepAverage: Double.random(in: 94...99)) : nil
        let respiration = Bool.random()
            ? HealthSnapshot.RespirationMetrics(
                sleepRate: Double.random(in: 10...18),
                baseline7Day: Double.random(in: 10...18)
            )
            : nil

        let vo2Latest = Double.random(in: 32...65)
        let vo2Previous = max(28, vo2Latest + Double.random(in: -2.5...2.5))
        let vo2Norm = Double.random(in: 30...55)
        let vo2Date = Bool.random() ? calendar.date(byAdding: .day, value: -Int.random(in: 1...10), to: date) : nil
        let vo2Contexts = ["run", "bike", "hike", "row"]
        let vo2 = HealthSnapshot.VOMetrics(
            latest: vo2Latest,
            previous: vo2Previous,
            age: Int.random(in: 20...65),
            sex: Bool.random() ? "male" : "female",
            norm: vo2Norm,
            date: vo2Date,
            context: Bool.random() ? vo2Contexts.randomElement() : nil
        )

        return HealthSnapshot(
            date: date,
            sleep: sleep,
            hrv: Bool.random() ? hrv : nil,
            restingHR: Bool.random() ? restingHR : nil,
            activity: activity,
            workouts: workouts,
            body: Bool.random() ? body : nil,
            oxygen: oxygen,
            respiration: respiration,
            vo2max: vo2
        )
    }
}
