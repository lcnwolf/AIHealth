import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var form = ManualHealthFormState()
    @State private var isRequesting: Bool = false
    @State private var resultText: String?
    @State private var errorMessage: String?
    @State private var lastRequestCost: RequestCostInfo?

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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
