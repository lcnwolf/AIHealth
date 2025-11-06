import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var form = ManualHealthFormState()
    @State private var isRequesting: Bool = false
    @State private var resultText: String?
    @State private var errorMessage: String?
    @State private var lastRequestCost: RequestCostInfo?
    @State private var generatedSnapshot: HealthSnapshot?

    var body: some View {
        NavigationView {
            Form {
                modelSection
                dateSection
                ManualMetricsSections(form: $form)
                submissionSection
            }
            .navigationTitle("AI Health")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Настройки запроса")
                }
            }
        }
    }

    private var modelSection: some View {
        Section(header: Text("Модель OpenAI"),
                footer: Text("Расчёт для \(estimatedTokens.output) токенов ответа и текущего промпта.")) {
            Picker("Модель", selection: $settings.selectedModelID) {
                ForEach(settings.availableModels) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
            if let summary = estimatedCostSummary {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.singleRequest)
                    Text(summary.tenThousandRequests)
                    Text(summary.context)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            Text(settings.selectedModel.description)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var dateSection: some View {
        Section(header: Text("Дата среза")) {
            DatePicker("Дата", selection: $form.snapshotDate, displayedComponents: [.date, .hourAndMinute])
        }
    }

    private var submissionSection: some View {
        Section(header: EmptyView(),
                footer: VStack(alignment: .leading, spacing: 4) {
                    Text("Оставьте пустыми любые поля, которые сейчас нет смысла подтягивать — мы не будем отправлять их в промпт.")
                    if settings.apiKey.isEmpty {
                        Text("Добавьте API-ключ в настройках, чтобы разблокировать отправку.")
                    } else {
                        Text("API-ключ сохранён локально и будет использоваться для следующих запросов.")
                    }
                }) {
            Button(action: generateRandomMetrics) {
                Label("Сгенерировать показатели", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
            .disabled(isRequesting)

            if generatedSnapshot != nil {
                GeneratedSnapshotSummaryView(snapshot: form.makeSnapshot())
            }

            Button(action: checkHealth) {
                HStack {
                    if isRequesting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                    Text(isRequesting ? "Запрашиваем..." : "Отправить в OpenAI")
                        .bold()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(settings.apiKey.isEmpty || isRequesting)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            }

            if let resultText {
                NavigationLink("Смотреть ответ", destination: ResultView(text: resultText))
            }

            if let lastRequestCost {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Последний запрос: \(lastRequestCost.model.displayName)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Text(String(format: "Стоимость: $%.4f (вход: %d ток., выход: %d ток.)",
                                lastRequestCost.totalCost,
                                lastRequestCost.promptTokens,
                                lastRequestCost.completionTokens))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func generateRandomMetrics() {
        let snapshot = RandomHealthDataGenerator.generateSnapshot(referenceDate: form.snapshotDate)
        form.apply(snapshot: snapshot)
        generatedSnapshot = form.makeSnapshot()
        errorMessage = nil
        lastRequestCost = nil
    }

    private func checkHealth() {
        guard !settings.apiKey.isEmpty else {
            errorMessage = "Введите API-ключ"
            return
        }
        guard form.hasAnyMetrics else {
            errorMessage = "Введите хотя бы одно значение здоровья"
            return
        }

        errorMessage = nil
        isRequesting = true
        lastRequestCost = nil

        let snapshot = form.makeSnapshot()
        let promptTemplate = settings.promptTemplate
        let model = settings.selectedModel
        let prompt = PromptBuilder(template: promptTemplate).prompt(from: snapshot)

        Task {
            do {
                let response = try await OpenAIService().sendPrompt(prompt, apiKey: settings.apiKey, model: model)
                await MainActor.run {
                    resultText = response.message
                    if let usage = response.usage {
                        let cost = model.pricing.cost(inputTokens: usage.promptTokens, outputTokens: usage.completionTokens)
                        lastRequestCost = RequestCostInfo(model: model,
                                                          promptTokens: usage.promptTokens,
                                                          completionTokens: usage.completionTokens,
                                                          totalCost: cost)
                    }
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

private extension ContentView {
    struct CostSummary {
        let singleRequest: String
        let tenThousandRequests: String
        let context: String
    }

    struct RequestCostInfo {
        let model: OpenAIModel
        let promptTokens: Int
        let completionTokens: Int
        let totalCost: Double
    }

    var estimatedTokens: (input: Int, output: Int) {
        let promptBuilder = PromptBuilder(template: settings.promptTemplate)
        let prompt = promptBuilder.prompt(from: form.makeSnapshot())
        let systemTokens = TokenEstimator.approximateTokenCount(for: OpenAIService.systemMessage)
        let userTokens = TokenEstimator.approximateTokenCount(for: prompt)
        return (systemTokens + userTokens, settings.estimatedCompletionTokens)
    }

    var estimatedCostSummary: CostSummary? {
        let tokens = estimatedTokens
        guard tokens.input > 0 else { return nil }
        let model = settings.selectedModel
        let cost = model.pricing.cost(inputTokens: tokens.input, outputTokens: tokens.output)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 4
        formatter.maximumFractionDigits = 4

        let singleCostString = formatter.string(from: NSNumber(value: cost)) ?? String(format: "$%.4f", cost)
        let manyCost = model.costForRequests(count: 10_000, inputTokens: tokens.input, outputTokens: tokens.output)
        let manyCostString = formatter.string(from: NSNumber(value: manyCost)) ?? String(format: "$%.2f", manyCost)

        return CostSummary(
            singleRequest: "≈Стоимость 1 запроса: \(singleCostString)",
            tenThousandRequests: "≈Стоимость 10 000 запросов: \(manyCostString)",
            context: "Контекст \(model.contextWindow.formatted(.number)) токенов"
        )
    }
}

private struct ManualMetricsSections: View {
    @Binding var form: ManualHealthFormState

    @ViewBuilder
    var body: some View {
        sleepSection
        cardioSection
        activitySection
        workoutsSection
        bodySection
        breathingSection
        vo2Section
    }

    @ViewBuilder
    private var sleepSection: some View {
        Section(header: Text("Сон")) {
            TextField("Сон последняя ночь (часы)", text: $form.sleepLastNight)
                .keyboardType(.decimalPad)
            TextField("Среднее за 7 дней (часы)", text: $form.sleepAverage)
                .keyboardType(.decimalPad)
            Toggle("Указать время отбоя", isOn: $form.includeSleepBedtime)
            if form.includeSleepBedtime {
                DatePicker("Отбой", selection: $form.sleepBedtime, displayedComponents: [.date, .hourAndMinute])
            }
            Toggle("Указать время подъёма", isOn: $form.includeSleepWake)
            if form.includeSleepWake {
                DatePicker("Подъём", selection: $form.sleepWake, displayedComponents: [.date, .hourAndMinute])
            }
        }
    }

    @ViewBuilder
    private var cardioSection: some View {
        Section(header: Text("Сердечные показатели"), footer: Text("Поля повторяют реальный набор показателей")) {
            Text("HRV")
                .font(.headline)
            TextField("Сегодня", text: $form.hrvToday)
                .keyboardType(.decimalPad)
            TextField("Базовый уровень 7 дней", text: $form.hrvBaseline)
                .keyboardType(.decimalPad)
            TextField("Количество выборок", text: $form.hrvSampleCount)
                .keyboardType(.numberPad)
            Toggle("Указать время измерения", isOn: $form.includeHRVSampleTime)
            if form.includeHRVSampleTime {
                DatePicker("Время", selection: $form.hrvSampleTime, displayedComponents: [.date, .hourAndMinute])
            }
            TextField("Устройство", text: $form.hrvDevice)

            Divider()

            Text("Пульс покоя")
                .font(.headline)
            TextField("Сегодня", text: $form.restingHRToday)
                .keyboardType(.decimalPad)
            TextField("Базовый уровень 7 дней", text: $form.restingHRBaseline)
                .keyboardType(.decimalPad)
        }
    }

    @ViewBuilder
    private var activitySection: some View {
        Section(header: Text("Активность")) {
            TextField("Шаги сегодня", text: $form.stepsToday)
                .keyboardType(.decimalPad)
            TextField("Шаги среднее 7 дней", text: $form.stepsAverage)
                .keyboardType(.decimalPad)
            TextField("Активные калории", text: $form.activeEnergy)
                .keyboardType(.decimalPad)
            TextField("Минуты спорта", text: $form.exerciseMinutes)
                .keyboardType(.decimalPad)
            TextField("Стояние (часы)", text: $form.standHours)
                .keyboardType(.decimalPad)
        }
    }

    @ViewBuilder
    private var workoutsSection: some View {
        Section(header: Text("Тренировки")) {
            TextField("За 7 дней", text: $form.workouts7Days)
                .keyboardType(.numberPad)
            TextField("За 14 дней", text: $form.workouts14Days)
                .keyboardType(.numberPad)
            TextField("За 30 дней", text: $form.workouts30Days)
                .keyboardType(.numberPad)
            TextField("Дней без тренировки", text: $form.daysSinceLastWorkout)
                .keyboardType(.numberPad)
            TextField("Тип последней", text: $form.lastWorkoutType)
            TextField("Длительность последней (мин)", text: $form.lastWorkoutMinutes)
                .keyboardType(.decimalPad)
            Toggle("Указать дату последней", isOn: $form.includeLastWorkoutDate)
            if form.includeLastWorkoutDate {
                DatePicker("Дата", selection: $form.lastWorkoutDate, displayedComponents: [.date, .hourAndMinute])
            }
        }
    }

    @ViewBuilder
    private var bodySection: some View {
        Section(header: Text("Показатели тела")) {
            TextField("Вес", text: $form.weight)
                .keyboardType(.decimalPad)
            TextField("Средний вес 7 дней", text: $form.weightAverage)
                .keyboardType(.decimalPad)
            TextField("Процент жира", text: $form.bodyFat)
                .keyboardType(.decimalPad)
        }
    }

    @ViewBuilder
    private var breathingSection: some View {
        Section(header: Text("Дыхание и кислород")) {
            Text("Кислород во сне")
                .font(.headline)
            TextField("Среднее значение", text: $form.oxygenSleepAverage)
                .keyboardType(.decimalPad)

            Divider()

            Text("Дыхание")
                .font(.headline)
            TextField("Частота во сне", text: $form.respirationSleepRate)
                .keyboardType(.decimalPad)
            TextField("Базовое значение", text: $form.respirationBaseline)
                .keyboardType(.decimalPad)
        }
    }

    @ViewBuilder
    private var vo2Section: some View {
        Section(header: Text("VO₂max")) {
            TextField("Текущее", text: $form.vo2Latest)
                .keyboardType(.decimalPad)
            TextField("Предыдущее", text: $form.vo2Previous)
                .keyboardType(.decimalPad)
            TextField("Возраст", text: $form.vo2Age)
                .keyboardType(.numberPad)
            Picker("Пол", selection: $form.vo2Sex) {
                Text("Не указано").tag("")
                Text("Мужской").tag("male")
                Text("Женский").tag("female")
            }
            TextField("Норма", text: $form.vo2Norm)
                .keyboardType(.decimalPad)
            Toggle("Указать дату замера", isOn: $form.includeVo2Date)
            if form.includeVo2Date {
                DatePicker("Дата", selection: $form.vo2Date, displayedComponents: [.date, .hourAndMinute])
            }
            TextField("Контекст (например, бег)", text: $form.vo2Context)
        }
    }
}

private struct GeneratedSnapshotSummaryView: View {
    let snapshot: HealthSnapshot

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Сгенерированные показатели")
                .font(.headline)
            Text("Срез от \(Self.timestampFormatter.string(from: snapshot.date))")
                .font(.footnote)
                .foregroundColor(.secondary)
            ForEach(Array(summaryLines.enumerated()), id: \.offset) { _, line in
                Text("• \(line)")
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }

    private var summaryLines: [String] {
        var lines: [String] = []

        if let sleep = snapshot.sleep {
            var parts: [String] = []
            if let last = sleep.lastNightHours { parts.append("последняя ночь \(format(last)) ч") }
            if let average = sleep.average7Days { parts.append("среднее 7 дней \(format(average)) ч") }
            if !parts.isEmpty {
                lines.append("Сон: " + parts.joined(separator: ", "))
            }
        }

        if let hrv = snapshot.hrv {
            var parts: [String] = []
            if let today = hrv.today { parts.append("сегодня \(format(today, decimals: 0)) мс") }
            if let baseline = hrv.baseline7Days { parts.append("база \(format(baseline, decimals: 0)) мс") }
            if let count = hrv.sampleCount { parts.append("выборок \(count)") }
            if let device = hrv.device { parts.append("устройство \(device)") }
            if !parts.isEmpty {
                lines.append("HRV: " + parts.joined(separator: ", "))
            }
        }

        if let resting = snapshot.restingHR {
            var parts: [String] = []
            if let today = resting.today { parts.append("сегодня \(format(today, decimals: 0)) уд/мин") }
            if let baseline = resting.baseline7Days { parts.append("база \(format(baseline, decimals: 0))") }
            if !parts.isEmpty {
                lines.append("Пульс покоя: " + parts.joined(separator: ", "))
            }
        }

        if let activity = snapshot.activity {
            var parts: [String] = []
            if let steps = activity.stepsToday { parts.append("шаги сегодня \(format(steps, decimals: 0))") }
            if let avg = activity.steps7DayAverage { parts.append("среднее \(format(avg, decimals: 0))") }
            if let energy = activity.activeEnergy { parts.append("активные калории \(format(energy, decimals: 0))") }
            if let minutes = activity.exerciseMinutes { parts.append("минут спорта \(format(minutes, decimals: 0))") }
            if let stand = activity.standHours { parts.append("стояние \(format(stand, decimals: 0)) ч") }
            if !parts.isEmpty {
                lines.append("Активность: " + parts.joined(separator: ", "))
            }
        }

            if let workouts = snapshot.workouts {
                var parts: [String] = []
                if let w7 = workouts.workouts7Days { parts.append("за 7 дней \(w7)") }
                if let w14 = workouts.workouts14Days { parts.append("за 14 дней \(w14)") }
                if let w30 = workouts.workouts30Days { parts.append("за 30 дней \(w30)") }
                if let days = workouts.daysSinceLastWorkout { parts.append("дней без тренировки \(days)") }
                if let last = workouts.lastWorkout {
                    var lastParts: [String] = []
                    if let type = last.type { lastParts.append(localizedWorkout(type)) }
                    if let minutes = last.minutes { lastParts.append("\(format(minutes, decimals: 0)) мин") }
                    if let date = last.date { lastParts.append(Self.timestampFormatter.string(from: date)) }
                    if !lastParts.isEmpty { parts.append("последняя: " + lastParts.joined(separator: ", ")) }
                }
                if !parts.isEmpty {
                lines.append("Тренировки: " + parts.joined(separator: ", "))
            }
        }

        if let body = snapshot.body {
            var parts: [String] = []
            if let weight = body.weight { parts.append("вес \(format(weight)) кг") }
            if let average = body.weight7DayAverage { parts.append("среднее \(format(average)) кг") }
            if let fat = body.bodyFatPercent { parts.append("жир \(format(fat)) %") }
            if !parts.isEmpty {
                lines.append("Тело: " + parts.joined(separator: ", "))
            }
        }

        if let oxygen = snapshot.oxygen, let value = oxygen.sleepAverage {
            lines.append("Кислород во сне: \(format(value)) %")
        }

        if let respiration = snapshot.respiration {
            var parts: [String] = []
            if let rate = respiration.sleepRate { parts.append("во сне \(format(rate)) вдохов/мин") }
            if let base = respiration.baseline7Day { parts.append("база \(format(base))") }
            if !parts.isEmpty {
                lines.append("Дыхание: " + parts.joined(separator: ", "))
            }
        }

        if let vo2 = snapshot.vo2max {
            var parts: [String] = []
            if let latest = vo2.latest { parts.append("текущий \(format(latest)) мл/кг/мин") }
            if let norm = vo2.norm { parts.append("норма \(format(norm))") }
            if let previous = vo2.previous { parts.append("предыдущий \(format(previous))") }
            if let latest = vo2.latest, let norm = vo2.norm, norm > 0 {
                let ratio = latest / norm
                let level: String
                switch ratio {
                case ..<0.9:
                    level = "ниже нормы"
                case ..<1.05:
                    level = "в пределах нормы"
                case ..<1.15:
                    level = "выше нормы"
                default:
                    level = "сильно выше нормы"
                }
                parts.append("уровень \(level)")
            }
            if let age = vo2.age { parts.append("возраст \(age)") }
            if let sex = vo2.sex { parts.append("пол \(sexLabel(sex))") }
            if let date = vo2.date { parts.append("дата \(Self.timestampFormatter.string(from: date))") }
            if let context = vo2.context { parts.append("контекст \(localizedWorkout(context))") }
            if !parts.isEmpty {
                lines.append("МПК (VO₂max): " + parts.joined(separator: ", "))
            }
        }

        return lines
    }

    private func format(_ value: Double, decimals: Int = 1) -> String {
        String(format: "%.*f", decimals, value)
    }

    private func sexLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "male":
            return "мужской"
        case "female":
            return "женский"
        default:
            return value
        }
    }

    private func localizedWorkout(_ value: String) -> String {
        switch value.lowercased() {
        case "run":
            return "бег"
        case "strength":
            return "силовая"
        case "cycling", "bike":
            return "велосипед"
        case "swim":
            return "плавание"
        case "yoga":
            return "йога"
        case "hiit":
            return "HIIT"
        case "hike":
            return "поход"
        case "row":
            return "гребля"
        default:
            return value
        }
    }
}

private struct ManualHealthFormState {
    var snapshotDate = Date()

    var sleepLastNight = ""
    var sleepAverage = ""
    var includeSleepBedtime = false
    var sleepBedtime = Date()
    var includeSleepWake = false
    var sleepWake = Date()

    var hrvToday = ""
    var hrvBaseline = ""
    var hrvSampleCount = ""
    var includeHRVSampleTime = false
    var hrvSampleTime = Date()
    var hrvDevice = ""

    var restingHRToday = ""
    var restingHRBaseline = ""

    var stepsToday = ""
    var stepsAverage = ""
    var activeEnergy = ""
    var exerciseMinutes = ""
    var standHours = ""

    var workouts7Days = ""
    var workouts14Days = ""
    var workouts30Days = ""
    var daysSinceLastWorkout = ""
    var lastWorkoutType = ""
    var lastWorkoutMinutes = ""
    var includeLastWorkoutDate = false
    var lastWorkoutDate = Date()

    var weight = ""
    var weightAverage = ""
    var bodyFat = ""

    var oxygenSleepAverage = ""

    var respirationSleepRate = ""
    var respirationBaseline = ""

    var vo2Latest = ""
    var vo2Previous = ""
    var vo2Age = ""
    var vo2Sex = ""
    var vo2Norm = ""
    var includeVo2Date = false
    var vo2Date = Date()
    var vo2Context = ""

    var hasAnyMetrics: Bool {
        makeSleep() != nil ||
        makeHRV() != nil ||
        makeRestingHR() != nil ||
        makeActivity() != nil ||
        makeWorkouts() != nil ||
        makeBody() != nil ||
        makeOxygen() != nil ||
        makeRespiration() != nil ||
        makeVO2() != nil
    }

    func makeSnapshot() -> HealthSnapshot {
        HealthSnapshot(
            date: snapshotDate,
            sleep: makeSleep(),
            hrv: makeHRV(),
            restingHR: makeRestingHR(),
            activity: makeActivity(),
            workouts: makeWorkouts(),
            body: makeBody(),
            oxygen: makeOxygen(),
            respiration: makeRespiration(),
            vo2max: makeVO2()
        )
    }

    private func makeSleep() -> HealthSnapshot.SleepMetrics? {
        let lastNight = double(from: sleepLastNight)
        let average = double(from: sleepAverage)
        let bedtime = includeSleepBedtime ? sleepBedtime : nil
        let wake = includeSleepWake ? sleepWake : nil

        guard lastNight != nil || average != nil || bedtime != nil || wake != nil else {
            return nil
        }

        return .init(
            lastNightHours: lastNight,
            average7Days: average,
            bedtime: bedtime,
            wakeUp: wake
        )
    }

    private func makeHRV() -> HealthSnapshot.HRVMetrics? {
        let today = double(from: hrvToday)
        let baseline = double(from: hrvBaseline)
        let count = int(from: hrvSampleCount)
        let time = includeHRVSampleTime ? hrvSampleTime : nil
        let device = trimmedOrNil(hrvDevice)

        guard today != nil || baseline != nil || count != nil || time != nil || device != nil else {
            return nil
        }

        return .init(
            today: today,
            baseline7Days: baseline,
            sampleCount: count,
            sampleTime: time,
            device: device
        )
    }

    private func makeRestingHR() -> HealthSnapshot.RestingHRMetrics? {
        let today = double(from: restingHRToday)
        let baseline = double(from: restingHRBaseline)

        guard today != nil || baseline != nil else {
            return nil
        }

        return .init(
            today: today,
            baseline7Days: baseline
        )
    }

    private func makeActivity() -> HealthSnapshot.ActivityMetrics? {
        let stepsTodayValue = double(from: stepsToday)
        let stepsAverageValue = double(from: stepsAverage)
        let energyValue = double(from: activeEnergy)
        let exerciseValue = double(from: exerciseMinutes)
        let standValue = double(from: standHours)

        guard stepsTodayValue != nil || stepsAverageValue != nil || energyValue != nil || exerciseValue != nil || standValue != nil else {
            return nil
        }

        return .init(
            stepsToday: stepsTodayValue,
            steps7DayAverage: stepsAverageValue,
            activeEnergy: energyValue,
            exerciseMinutes: exerciseValue,
            standHours: standValue
        )
    }

    private func makeWorkouts() -> HealthSnapshot.WorkoutSummary? {
        let w7 = int(from: workouts7Days)
        let w14 = int(from: workouts14Days)
        let w30 = int(from: workouts30Days)
        let days = int(from: daysSinceLastWorkout)

        let lastType = trimmedOrNil(lastWorkoutType)
        let lastMinutes = double(from: lastWorkoutMinutes)
        let lastDate = includeLastWorkoutDate ? lastWorkoutDate : nil

        let lastWorkout: HealthSnapshot.WorkoutSummary.WorkoutDetail? = {
            guard lastType != nil || lastMinutes != nil || lastDate != nil else {
                return nil
            }
            return .init(
                type: lastType,
                minutes: lastMinutes,
                date: lastDate
            )
        }()

        guard w7 != nil || w14 != nil || w30 != nil || days != nil || lastWorkout != nil else {
            return nil
        }

        return .init(
            workouts7Days: w7,
            workouts14Days: w14,
            workouts30Days: w30,
            daysSinceLastWorkout: days,
            lastWorkout: lastWorkout
        )
    }

    private func makeBody() -> HealthSnapshot.BodyMetrics? {
        let weightValue = double(from: weight)
        let averageValue = double(from: weightAverage)
        let fatValue = double(from: bodyFat)

        guard weightValue != nil || averageValue != nil || fatValue != nil else {
            return nil
        }

        return .init(
            weight: weightValue,
            weight7DayAverage: averageValue,
            bodyFatPercent: fatValue
        )
    }

    private func makeOxygen() -> HealthSnapshot.OxygenMetrics? {
        let oxygenValue = double(from: oxygenSleepAverage)
        guard oxygenValue != nil else { return nil }
        return .init(sleepAverage: oxygenValue)
    }

    private func makeRespiration() -> HealthSnapshot.RespirationMetrics? {
        let rateValue = double(from: respirationSleepRate)
        let baselineValue = double(from: respirationBaseline)

        guard rateValue != nil || baselineValue != nil else { return nil }

        return .init(
            sleepRate: rateValue,
            baseline7Day: baselineValue
        )
    }

    private func makeVO2() -> HealthSnapshot.VOMetrics? {
        let latestValue = double(from: vo2Latest)
        let previousValue = double(from: vo2Previous)
        let ageValue = int(from: vo2Age)
        let normValue = double(from: vo2Norm)
        let sexValue = trimmedOrNil(vo2Sex)
        let contextValue = trimmedOrNil(vo2Context)
        let dateValue = includeVo2Date ? vo2Date : nil

        guard latestValue != nil || previousValue != nil || ageValue != nil || normValue != nil || sexValue != nil || contextValue != nil || dateValue != nil else {
            return nil
        }

        return .init(
            latest: latestValue,
            previous: previousValue,
            age: ageValue,
            sex: sexValue,
            norm: normValue,
            date: dateValue,
            context: contextValue
        )
    }

    private func double(from text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, let value = Double(normalized) else { return nil }
        return value
    }

    private func int(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed) else { return nil }
        return value
    }

    private func trimmedOrNil(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension ManualHealthFormState {
    mutating func apply(snapshot: HealthSnapshot) {
        snapshotDate = snapshot.date
        let fallbackDate = snapshot.date

        func setDouble(_ value: Double?, decimals: Int, field: inout String) {
            if let value {
                field = String(format: "%.*f", decimals, value)
            } else {
                field = ""
            }
        }

        func setInt(_ value: Int?, field: inout String) {
            if let value {
                field = String(value)
            } else {
                field = ""
            }
        }

        func setString(_ value: String?, field: inout String) {
            field = value ?? ""
        }

        if let sleep = snapshot.sleep {
            setDouble(sleep.lastNightHours, decimals: 1, field: &sleepLastNight)
            setDouble(sleep.average7Days, decimals: 1, field: &sleepAverage)
            includeSleepBedtime = sleep.bedtime != nil
            sleepBedtime = sleep.bedtime ?? fallbackDate
            includeSleepWake = sleep.wakeUp != nil
            sleepWake = sleep.wakeUp ?? fallbackDate
        } else {
            sleepLastNight = ""
            sleepAverage = ""
            includeSleepBedtime = false
            sleepBedtime = fallbackDate
            includeSleepWake = false
            sleepWake = fallbackDate
        }

        if let hrv = snapshot.hrv {
            setDouble(hrv.today, decimals: 1, field: &hrvToday)
            setDouble(hrv.baseline7Days, decimals: 1, field: &hrvBaseline)
            setInt(hrv.sampleCount, field: &hrvSampleCount)
            includeHRVSampleTime = hrv.sampleTime != nil
            hrvSampleTime = hrv.sampleTime ?? fallbackDate
            setString(hrv.device, field: &hrvDevice)
        } else {
            hrvToday = ""
            hrvBaseline = ""
            hrvSampleCount = ""
            includeHRVSampleTime = false
            hrvSampleTime = fallbackDate
            hrvDevice = ""
        }

        if let resting = snapshot.restingHR {
            setDouble(resting.today, decimals: 1, field: &restingHRToday)
            setDouble(resting.baseline7Days, decimals: 1, field: &restingHRBaseline)
        } else {
            restingHRToday = ""
            restingHRBaseline = ""
        }

        if let activity = snapshot.activity {
            setDouble(activity.stepsToday, decimals: 0, field: &stepsToday)
            setDouble(activity.steps7DayAverage, decimals: 0, field: &stepsAverage)
            setDouble(activity.activeEnergy, decimals: 0, field: &activeEnergy)
            setDouble(activity.exerciseMinutes, decimals: 0, field: &exerciseMinutes)
            setDouble(activity.standHours, decimals: 0, field: &standHours)
        } else {
            stepsToday = ""
            stepsAverage = ""
            activeEnergy = ""
            exerciseMinutes = ""
            standHours = ""
        }

        if let workouts = snapshot.workouts {
            setInt(workouts.workouts7Days, field: &workouts7Days)
            setInt(workouts.workouts14Days, field: &workouts14Days)
            setInt(workouts.workouts30Days, field: &workouts30Days)
            setInt(workouts.daysSinceLastWorkout, field: &daysSinceLastWorkout)
            if let last = workouts.lastWorkout {
                setString(last.type, field: &lastWorkoutType)
                setDouble(last.minutes, decimals: 0, field: &lastWorkoutMinutes)
                includeLastWorkoutDate = last.date != nil
                lastWorkoutDate = last.date ?? fallbackDate
            } else {
                lastWorkoutType = ""
                lastWorkoutMinutes = ""
                includeLastWorkoutDate = false
                lastWorkoutDate = fallbackDate
            }
        } else {
            workouts7Days = ""
            workouts14Days = ""
            workouts30Days = ""
            daysSinceLastWorkout = ""
            lastWorkoutType = ""
            lastWorkoutMinutes = ""
            includeLastWorkoutDate = false
            lastWorkoutDate = fallbackDate
        }

        if let body = snapshot.body {
            setDouble(body.weight, decimals: 1, field: &weight)
            setDouble(body.weight7DayAverage, decimals: 1, field: &weightAverage)
            setDouble(body.bodyFatPercent, decimals: 1, field: &bodyFat)
        } else {
            weight = ""
            weightAverage = ""
            bodyFat = ""
        }

        if let oxygen = snapshot.oxygen {
            setDouble(oxygen.sleepAverage, decimals: 1, field: &oxygenSleepAverage)
        } else {
            oxygenSleepAverage = ""
        }

        if let respiration = snapshot.respiration {
            setDouble(respiration.sleepRate, decimals: 1, field: &respirationSleepRate)
            setDouble(respiration.baseline7Day, decimals: 1, field: &respirationBaseline)
        } else {
            respirationSleepRate = ""
            respirationBaseline = ""
        }

        if let vo2 = snapshot.vo2max {
            setDouble(vo2.latest, decimals: 1, field: &vo2Latest)
            setDouble(vo2.previous, decimals: 1, field: &vo2Previous)
            setInt(vo2.age, field: &vo2Age)
            setString(vo2.sex, field: &vo2Sex)
            setDouble(vo2.norm, decimals: 1, field: &vo2Norm)
            includeVo2Date = vo2.date != nil
            vo2Date = vo2.date ?? fallbackDate
            setString(vo2.context, field: &vo2Context)
        } else {
            vo2Latest = ""
            vo2Previous = ""
            vo2Age = ""
            vo2Sex = ""
            vo2Norm = ""
            includeVo2Date = false
            vo2Date = fallbackDate
            vo2Context = ""
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
