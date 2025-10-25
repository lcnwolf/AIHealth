import Foundation
import HealthKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class HealthKitManager: ObservableObject {
    enum AuthorizationState {
        case notDetermined
        case authorized
        case denied
    }

    enum HealthKitError: LocalizedError {
        case unavailable
        case unauthorized

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "HealthKit недоступен на этом устройстве"
            case .unauthorized:
                return "Нет доступа к данным HealthKit"
            }
        }
    }

    @Published private(set) var authorizationState: AuthorizationState = .notDetermined

    private let healthStore = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        if let resting = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { types.insert(resting) }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(hrv) }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        if let exercise = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) { types.insert(exercise) }
        if let stand = HKObjectType.quantityType(forIdentifier: .appleStandTime) { types.insert(stand) }
        if let vo2 = HKObjectType.quantityType(forIdentifier: .vo2Max) { types.insert(vo2) }
        if let oxygen = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) { types.insert(oxygen) }
        if let respiration = HKObjectType.quantityType(forIdentifier: .respiratoryRate) { types.insert(respiration) }
        if let weight = HKObjectType.quantityType(forIdentifier: .bodyMass) { types.insert(weight) }
        if let fat = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) { types.insert(fat) }
        types.insert(HKObjectType.workoutType())
        return types
    }

    func requestAuthorizationIfNeeded() {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .denied
            return
        }

        guard authorizationState == .notDetermined else { return }

        Task {
            do {
                try await requestAuthorization()
            } catch {
                authorizationState = .denied
            }
        }
    }

    func resetAuthorizationStatus() {
        authorizationState = .notDetermined
    }

    private func requestAuthorization() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: nil, read: readTypes) { success, error in
                Task { @MainActor in
                    self.authorizationState = success ? .authorized : .denied
                }
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: error ?? HealthKitError.unauthorized)
                }
            }
        }
    }

    func fetchSnapshot() async throws -> HealthSnapshot {
        guard authorizationState == .authorized else {
            throw HealthKitError.unauthorized
        }

        async let sleep = fetchSleepMetrics()
        async let hrv = fetchHRVMetrics()
        async let resting = fetchRestingHRMetrics()
        async let activity = fetchActivityMetrics()
        async let workouts = fetchWorkoutSummary()
        async let body = fetchBodyMetrics()
        async let oxygen = fetchOxygenMetrics()
        async let respiration = fetchRespirationMetrics()
        async let vo2 = fetchVOMetrics()

        return HealthSnapshot(
            date: Date(),
            sleep: try await sleep,
            hrv: try await hrv,
            restingHR: try await resting,
            activity: try await activity,
            workouts: try await workouts,
            body: try await body,
            oxygen: try await oxygen,
            respiration: try await respiration,
            vo2max: try await vo2
        )
    }

    func openSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}

// MARK: - Fetch helpers

private extension HealthKitManager {
    func fetchSleepMetrics() async throws -> HealthSnapshot.SleepMetrics? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let lastNightStart = calendar.date(byAdding: .day, value: -1, to: startOfToday),
              let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: sevenDaysAgo, end: Date(), options: .strictStartDate)
        let samples: [HKCategorySample] = try await fetchSamples(of: sleepType, predicate: predicate)
        let lastNightSamples = samples.filter { $0.startDate >= lastNightStart }
        let asleepSamples = samples.filter { sample in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return false }
            return value.isAsleep
        }

        let lastNightHours: Double? = lastNightSamples.isEmpty ? nil : lastNightSamples.reduce(0) { partial, sample in
            partial + sample.endDate.timeIntervalSince(sample.startDate)
        } / 3600

        let groupedByDay = Dictionary(grouping: asleepSamples) { sample in
            calendar.startOfDay(for: sample.startDate)
        }
        let nightlyDurations = groupedByDay.values.map { daySamples -> Double in
            daySamples.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 3600
        }
        let baselineHours = nightlyDurations.isEmpty ? nil : nightlyDurations.reduce(0, +) / Double(nightlyDurations.count)

        let bedtime = lastNightSamples.min(by: { $0.startDate < $1.startDate })?.startDate
        let wakeup = lastNightSamples.max(by: { $0.endDate < $1.endDate })?.endDate

        return HealthSnapshot.SleepMetrics(
            lastNightHours: lastNightHours,
            average7Days: baselineHours,
            bedtime: bedtime,
            wakeUp: wakeup
        )
    }

    func fetchHRVMetrics() async throws -> HealthSnapshot.HRVMetrics? {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }
        let latest = try await fetchLatestQuantitySample(for: type)
        let samples = try await fetchQuantitySamples(for: type, daysBack: 7)
        let baseline = averageQuantity(from: samples)
        return HealthSnapshot.HRVMetrics(
            today: latest?.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)),
            baseline7Days: baseline?.doubleValue(for: HKUnit.secondUnit(with: .milli)),
            sampleCount: samples.count,
            sampleTime: latest?.startDate,
            device: latest?.device?.name
        )
    }

    func fetchRestingHRMetrics() async throws -> HealthSnapshot.RestingHRMetrics? {
        guard let type = HKObjectType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        let latest = try await fetchLatestQuantitySample(for: type)
        let samples = try await fetchQuantitySamples(for: type, daysBack: 7)
        let baseline = averageQuantity(from: samples)
        let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
        return HealthSnapshot.RestingHRMetrics(
            today: latest?.quantity.doubleValue(for: unit),
            baseline7Days: baseline?.doubleValue(for: unit)
        )
    }

    func fetchActivityMetrics() async throws -> HealthSnapshot.ActivityMetrics? {
        guard let stepsType = HKObjectType.quantityType(forIdentifier: .stepCount) else { return nil }
        async let stepsToday = sumQuantity(for: stepsType, over: .day, value: 0)
        async let stepsAverage = averageQuantity(for: stepsType, days: 7)

        let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        let exerciseType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime)
        let standType = HKObjectType.quantityType(forIdentifier: .appleStandTime)

        let energy: Double?
        if let energyType {
            energy = try await sumQuantity(for: energyType, over: .day, value: 0)
        } else {
            energy = nil
        }

        let exercise: Double?
        if let exerciseType {
            exercise = try await sumQuantity(for: exerciseType, over: .day, value: 0)
        } else {
            exercise = nil
        }

        let stand: Double?
        if let standType {
            stand = try await sumQuantity(for: standType, over: .day, value: 0)
        } else {
            stand = nil
        }

        return HealthSnapshot.ActivityMetrics(
            stepsToday: try await stepsToday,
            steps7DayAverage: try await stepsAverage,
            activeEnergy: energy,
            exerciseMinutes: exercise,
            standHours: stand
        )
    }

    func fetchWorkoutSummary() async throws -> HealthSnapshot.WorkoutSummary? {
        let workoutType = HKObjectType.workoutType()
        let calendar = Calendar.current
        guard let start30 = calendar.date(byAdding: .day, value: -30, to: Date()) else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: start30, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let workouts: [HKWorkout] = try await fetchSamples(of: workoutType, predicate: predicate, sortDescriptors: [sort])

        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: Date()) ?? Date()

        let workouts7 = workouts.filter { $0.startDate >= sevenDaysAgo }
        let workouts14 = workouts.filter { $0.startDate >= fourteenDaysAgo }

        let lastWorkout = workouts.first
        let daysSinceLast = lastWorkout.flatMap { workout in
            calendar.dateComponents([.day], from: workout.endDate, to: Date()).day
        }

        let detail = lastWorkout.map { workout in
            HealthSnapshot.WorkoutSummary.WorkoutDetail(
                type: workout.workoutActivityType.simpleName,
                minutes: workout.duration / 60,
                date: workout.endDate
            )
        }

        return HealthSnapshot.WorkoutSummary(
            workouts7Days: workouts7.count,
            workouts14Days: workouts14.count,
            workouts30Days: workouts.count,
            daysSinceLastWorkout: daysSinceLast,
            lastWorkout: detail
        )
    }

    func fetchBodyMetrics() async throws -> HealthSnapshot.BodyMetrics? {
        guard let weightType = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return nil }
        let latestWeight = try await fetchLatestQuantitySample(for: weightType)
        let samples = try await fetchQuantitySamples(for: weightType, daysBack: 7)
        let average = averageQuantity(from: samples)

        let bodyFatType = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)
        let bodyFatSample: HKQuantitySample?
        if let bodyFatType {
            bodyFatSample = try await fetchLatestQuantitySample(for: bodyFatType)
        } else {
            bodyFatSample = nil
        }

        let bodyFatPercent: Double?
        if let bodyFatSample {
            bodyFatPercent = bodyFatSample.quantity.doubleValue(for: .percent()) * 100
        } else {
            bodyFatPercent = nil
        }

        return HealthSnapshot.BodyMetrics(
            weight: latestWeight?.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo)),
            weight7DayAverage: average?.doubleValue(for: HKUnit.gramUnit(with: .kilo)),
            bodyFatPercent: bodyFatPercent
        )
    }

    func fetchOxygenMetrics() async throws -> HealthSnapshot.OxygenMetrics? {
        guard let oxygenType = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) else { return nil }
        let samples = try await fetchQuantitySamples(for: oxygenType, daysBack: 7)
        let average = averageQuantity(from: samples)
        let sleepAveragePercent = average.map { $0.doubleValue(for: .percent()) * 100 }
        return HealthSnapshot.OxygenMetrics(
            sleepAverage: sleepAveragePercent
        )
    }

    func fetchRespirationMetrics() async throws -> HealthSnapshot.RespirationMetrics? {
        guard let type = HKObjectType.quantityType(forIdentifier: .respiratoryRate) else { return nil }
        let latest = try await fetchLatestQuantitySample(for: type)
        let samples = try await fetchQuantitySamples(for: type, daysBack: 7)
        let baseline = averageQuantity(from: samples)
        let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
        return HealthSnapshot.RespirationMetrics(
            sleepRate: latest?.quantity.doubleValue(for: unit),
            baseline7Day: baseline?.doubleValue(for: unit)
        )
    }

    func fetchVOMetrics() async throws -> HealthSnapshot.VOMetrics? {
        guard let type = HKObjectType.quantityType(forIdentifier: .vo2Max) else { return nil }
        let samples = try await fetchQuantitySamples(for: type, daysBack: 30)
        let sorted = samples.sorted(by: { $0.startDate > $1.startDate })
        guard let latest = sorted.first else { return nil }
        let previous = sorted.dropFirst().first
        let unit = HKUnit(from: "mL/(kg*min)")
        return HealthSnapshot.VOMetrics(
            latest: latest.quantity.doubleValue(for: unit),
            previous: previous?.quantity.doubleValue(for: unit),
            age: nil,
            sex: nil,
            norm: nil,
            date: latest.endDate,
            context: latest.metadata?[HKMetadataKeyWorkoutBrandName] as? String
        )
    }
}

// MARK: - Shared helpers

private extension HealthKitManager {
    func fetchSamples<T: HKSample>(of sampleType: HKSampleType, predicate: NSPredicate?, sortDescriptors: [NSSortDescriptor]? = nil) async throws -> [T] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[T], Error>) in
            let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sortDescriptors) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [T] ?? [])
            }
            healthStore.execute(query)
        }
    }

    func fetchLatestQuantitySample(for type: HKQuantityType) async throws -> HKQuantitySample? {
        try await fetchSamples(of: type, predicate: nil, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]).first
    }

    func fetchQuantitySamples(for type: HKQuantityType, daysBack: Int) async throws -> [HKQuantitySample] {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -daysBack, to: Date()) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return try await fetchSamples(of: type, predicate: predicate)
    }

    func averageQuantity(from samples: [HKQuantitySample]) -> HKQuantity? {
        guard !samples.isEmpty else { return nil }
        let unit = samples.first!.quantityType.defaultUnit
        let total = samples.reduce(0.0) { partial, sample in
            partial + sample.quantity.doubleValue(for: unit)
        }
        return HKQuantity(unit: unit, doubleValue: total / Double(samples.count))
    }

    func sumQuantity(for type: HKQuantityType, over component: Calendar.Component, value: Int) async throws -> Double? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: component, value: value, to: startOfDay) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let stats = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKStatistics?, Error>) in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: statistics)
            }
            healthStore.execute(query)
        }
        guard let quantity = stats?.sumQuantity() else { return nil }
        let unit: HKUnit
        switch type.identifier {
        case HKQuantityTypeIdentifier.stepCount.rawValue:
            unit = .count()
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
            unit = .kilocalorie()
        case HKQuantityTypeIdentifier.appleExerciseTime.rawValue,
             HKQuantityTypeIdentifier.appleStandTime.rawValue:
            unit = .minute()
        default:
            unit = type.defaultUnit
        }
        return quantity.doubleValue(for: unit)
    }

    func averageQuantity(for type: HKQuantityType, days: Int) async throws -> Double? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -days, to: startOfDay) else { return nil }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double?, Error>) in
            let interval = DateComponents(day: 1)
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate), options: .cumulativeSum, anchorDate: startOfDay, intervalComponents: interval)
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let collection else {
                    continuation.resume(returning: nil)
                    return
                }
                let unit: HKUnit = type.identifier == HKQuantityTypeIdentifier.stepCount.rawValue ? .count() : type.defaultUnit
                var total: Double = 0
                var daysCount: Int = 0
                collection.enumerateStatistics(from: start, to: Date()) { stats, _ in
                    if let quantity = stats.sumQuantity() {
                        total += quantity.doubleValue(for: unit)
                        daysCount += 1
                    }
                }
                guard daysCount > 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: total / Double(daysCount))
            }
            healthStore.execute(query)
        }
    }
}

// MARK: - Default units

private extension HKQuantityType {
    var defaultUnit: HKUnit {
        switch self.identifier {
        case HKQuantityTypeIdentifier.restingHeartRate.rawValue,
             HKQuantityTypeIdentifier.respiratoryRate.rawValue:
            return .count().unitDivided(by: .minute())
        case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue:
            return HKUnit.secondUnit(with: .milli)
        case HKQuantityTypeIdentifier.stepCount.rawValue:
            return .count()
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
            return .kilocalorie()
        case HKQuantityTypeIdentifier.appleExerciseTime.rawValue,
             HKQuantityTypeIdentifier.appleStandTime.rawValue:
            return .minute()
        case HKQuantityTypeIdentifier.bodyMass.rawValue:
            return .gramUnit(with: .kilo)
        case HKQuantityTypeIdentifier.bodyFatPercentage.rawValue,
             HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
            return .percent()
        case HKQuantityTypeIdentifier.vo2Max.rawValue:
            return HKUnit(from: "mL/(kg*min)")
        default:
            return .count()
        }
    }
}

// MARK: - Workout helpers

private extension HKWorkoutActivityType {
    var simpleName: String {
        switch self {
        case .running: return "run"
        case .walking: return "walk"
        case .cycling: return "bike"
        case .yoga: return "yoga"
        case .traditionalStrengthTraining: return "strength"
        case .highIntensityIntervalTraining: return "hiit"
        case .swimming: return "swim"
        default: return String(describing: self)
        }
    }
}

// MARK: - Preview helper

extension HealthKitManager {
    static var preview: HealthKitManager {
        let manager = HealthKitManager()
        manager.authorizationState = .authorized
        return manager
    }
}

// MARK: - Sleep helpers

private extension HKCategoryValueSleepAnalysis {
    var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
            return true
        default:
            return false
        }
    }
}
