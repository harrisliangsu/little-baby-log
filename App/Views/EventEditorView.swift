import SwiftUI
import CoreData
import BabyLogKit

enum EditorTarget: Identifiable {
    case new(EventKind)
    case edit(LogEvent)
    /// A widget tap. The draft is empty until Save. Home-card history uses a different screen.
    case card(HomeCard)
    /// An AI or import draft. Nothing is written until Save.
    case seeded(EventDraft)

    var id: String {
        switch self {
        case .new(let kind):
            return "new-" + kind.rawValue
        case .edit(let event):
            return "edit-" + event.objectID.uriRepresentation().absoluteString
        case .card(let card):
            return "card-" + card.rawValue
        case .seeded(let draft):
            return "seed-" + draft.kind.rawValue + "-" + String(draft.startDate.timeIntervalSince1970)
        }
    }

    var homeCard: HomeCard? {
        if case .card(let card) = self { return card }
        return nil
    }
}

/// Add or edit one log entry. Edits a value-type `EventDraft`, so Cancel discards everything.
struct EventEditorView: View {
    let baby: Baby
    let target: EditorTarget

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @Environment(\.appTheme) private var theme
    @Environment(\.uiLanguage) private var language
    @AppStorage(Prefs.volumeUnit) private var volumeUnit: VolumeUnit = Prefs.defaultVolumeUnit
    @AppStorage(Prefs.unitSystem) private var unitSystem: UnitSystem = Prefs.defaultUnitSystem

    @State private var draft: EventDraft
    @State private var confirmDelete = false
    @State private var attemptedSave = false
    @State private var seededFormula = false
    @State private var editingAmount = false

    init(baby: Baby, target: EditorTarget) {
        self.baby = baby
        self.target = target
        switch target {
        case .new(let kind):
            _draft = State(initialValue: EventDraft(kind: kind))
        case .edit(let event):
            _draft = State(initialValue: EventDraft(event: event))
        case .card(let card):
            _draft = State(initialValue: EventDraft(card: card))
        case .seeded(let draft):
            _draft = State(initialValue: draft)
        }
    }

    private var isEditing: Bool {
        if case .edit = target { return true }
        return false
    }

    private var screenTitle: String {
        let name = target.homeCard.map { Copy.card($0, language) }
            ?? UICopy.kind(draft.kind, language)
        return isEditing ? "\(UICopy.t(.editPrefix, language))\(name)" : "\(UICopy.t(.newPrefix, language))\(language == .zh ? "" : " ")\(name)"
    }

    var body: some View {
        NavigationStack {
            Form {
                kindFields
                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Text(UICopy.t(.deleteEntry, language)).themedDestructive()
                        }
                    }
                    .themedSection()
                }
            }
            .background(alignment: .topLeading) {
                VStack(alignment: .leading) {
                    Text(baby.displayName)
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("composer-baby")
                    if let card = target.homeCard {
                        Text(card.rawValue)
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("composer-card")
                    }
                }
                .opacity(0.01)
                .accessibilityElement(children: .contain)
            }
            .onAppear(perform: seedFormulaAmountIfNeeded)
            .themedList()
            .systemBarChrome()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(UICopy.t(.cancel, language)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(UICopy.t(.save, language)) { save() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("save-entry")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(UICopy.t(.done, language)) { UIApplication.endEditing() }
                }
            }
            .sheet(isPresented: $editingAmount) {
                AmountSheet(milliliters: $draft.amountML, unit: volumeUnit, language: language)
            }
            .confirmationDialog(UICopy.t(.deleteConfirm, language), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(UICopy.t(.delete, language), role: .destructive) { deleteEntry() }
                Button(UICopy.t(.cancel, language), role: .cancel) {}
            }
        }
    }

    // MARK: Fields by kind

    private var kindFields: some View {
        kindSection
            .themedSection()
    }

    @ViewBuilder
    private var kindSection: some View {
        switch draft.kind {
        case .sleep:
            sleepFields
        case .breastfeed:
            nursingFields
        case .bottle:
            bottleFields
        case .solids:
            solidsFields
        case .diaper:
            diaperFields
        case .pump:
            pumpFields
        case .growth:
            growthFields
        case .medicine:
            medicineFields
        }
    }

    private var sleepFields: some View {
        Section {
            TimeValueRow(title: UICopy.t(.start, language), date: $draft.startDate)
            Toggle(UICopy.t(.stillAsleep, language), isOn: stillAsleep)
            if draft.endDate != nil {
                TimeValueRow(title: UICopy.t(.end, language), date: endDateBinding)
                LabeledContent(UICopy.t(.duration, language), value: DurationFormat.short(sleepSeconds))
            }
            saveError
        }
    }

    private var nursingFields: some View {
        Section {
            TimeValueRow(title: UICopy.t(.start, language), date: $draft.startDate)
            if draft.isRunning {
                Text(UICopy.t(.timerRunning, language))
                    .font(.subheadline)
                    .foregroundStyle(theme.secondary)
            } else {
                NumberField(UICopy.t(.leftMinutes, language), value: minutesBinding(\.leftSeconds), unit: language == .zh ? "分钟" : "min", identifier: "breast-left-minutes")
                    .frame(minHeight: 56)
                NumberField(UICopy.t(.rightMinutes, language), value: minutesBinding(\.rightSeconds), unit: language == .zh ? "分钟" : "min")
                    .frame(minHeight: 56)
            }
            saveError
        }
    }

    private var bottleFields: some View {
        Section {
            Button { editingAmount = true } label: {
                HStack {
                    Text(UICopy.t(.amount, language))
                    Spacer(minLength: 12)
                    Text(draft.amountML > 0 ? Copy.amount(draft.amountML, unit: volumeUnit, language) : volumeUnit.symbol)
                        .font(.title2.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("amount-value")
            TimeValueRow(title: UICopy.t(.time, language), date: $draft.startDate)
            if target.homeCard != .formula {
                Picker(UICopy.t(.contents, language), selection: $draft.bottleContent) {
                    ForEach(BottleContent.allCases) { content in
                        Text(UICopy.bottle(content, language)).tag(content)
                    }
                }
                .pickerStyle(.segmented)
            }
            saveError
        }
    }

    private var solidsFields: some View {
        Section {
            TimeValueRow(title: UICopy.t(.time, language), date: $draft.startDate)
            TextField(UICopy.t(.food, language), text: $draft.foodName)
                .textInputAutocapitalization(.sentences)
                .frame(minHeight: 56)
            saveError
        }
    }

    private var diaperFields: some View {
        Section {
            TimeValueRow(title: UICopy.t(.time, language), date: $draft.startDate)
            if target.homeCard == nil {
                Picker(UICopy.kind(.diaper, language), selection: $draft.diaperKind) {
                    ForEach(DiaperKind.allCases) { kind in
                        Text(UICopy.diaper(kind, language)).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }
            saveError
        }
    }

    private var pumpFields: some View {
        Section {
            TimeValueRow(title: UICopy.t(.start, language), date: $draft.startDate)
            NumberField(UICopy.t(.pumpDuration, language), value: minutesBinding(\.pumpDuration), unit: language == .zh ? "分钟" : "min")
                .frame(minHeight: 56)
            NumberField(UICopy.t(.left, language), value: volumeBinding(\.leftML), unit: volumeUnit.symbol)
                .frame(minHeight: 56)
            NumberField(UICopy.t(.right, language), value: volumeBinding(\.rightML), unit: volumeUnit.symbol)
                .frame(minHeight: 56)
            saveError
        }
    }

    private var growthFields: some View {
        Section {
            TimeValueRow(title: UICopy.t(.time, language), date: $draft.startDate)
            if unitSystem == .metric {
                NumberField(UICopy.t(.weight, language), value: $draft.weightKg, unit: "kg", digits: 3)
            } else {
                NumberField(UICopy.t(.weight, language), value: poundsBinding, unit: "lb", digits: 0)
                NumberField(UICopy.t(.ounces, language), value: ouncesBinding, unit: "oz", digits: 1)
            }
            NumberField(UICopy.t(.length, language), value: lengthBinding(\.lengthCm), unit: unitSystem.lengthSymbol)
            NumberField(UICopy.t(.head, language), value: lengthBinding(\.headCm), unit: unitSystem.lengthSymbol)
                .frame(minHeight: 56)
            saveError
        }
    }

    private var medicineFields: some View {
        Section {
            TimeValueRow(title: UICopy.t(.time, language), date: $draft.startDate)
            TextField(UICopy.t(.medicine, language), text: $draft.medicineName)
                .textInputAutocapitalization(.words)
                .frame(minHeight: 56)
            TextField(UICopy.t(.dose, language), text: $draft.dose)
                .frame(minHeight: 56)
            saveError
        }
    }

    @ViewBuilder
    private var saveError: some View {
        if attemptedSave, let message = draft.validationMessage {
            Text(UICopy.validation(message, language))
                .font(.footnote)
                .foregroundStyle(theme.destructive)
        }
    }

    private func seedFormulaAmountIfNeeded() {
        guard !seededFormula else { return }
        seededFormula = true
        guard case .card(.formula) = target, draft.amountML <= 0 else { return }
        let request = LogEvent.requestAll(baby: baby, kinds: [.bottle], ascending: false)
        let events = (try? context.fetch(request)) ?? []
        if let amount = FormulaAmountSeed.milliliters(newestFirst: events) {
            draft.amountML = amount
        }
    }

    // MARK: Bindings

    private var sleepSeconds: TimeInterval {
        guard let end = draft.endDate else { return 0 }
        return max(0, end.timeIntervalSince(draft.startDate))
    }

    private var stillAsleep: Binding<Bool> {
        Binding(
            get: { draft.endDate == nil },
            set: { asleep in
                if asleep {
                    draft.endDate = nil
                } else {
                    draft.endDate = max(Date.now, draft.startDate.addingTimeInterval(60))
                }
            }
        )
    }

    private var endDateBinding: Binding<Date> {
        Binding(
            get: { draft.endDate ?? draft.startDate },
            set: { draft.endDate = $0 }
        )
    }

    private func minutesBinding(_ keyPath: WritableKeyPath<EventDraft, TimeInterval>) -> Binding<Double> {
        Binding(
            get: { draft[keyPath: keyPath] / 60 },
            set: { draft[keyPath: keyPath] = $0 * 60 }
        )
    }

    private func volumeBinding(_ keyPath: WritableKeyPath<EventDraft, Double>) -> Binding<Double> {
        Binding(
            get: { volumeUnit.value(fromMilliliters: draft[keyPath: keyPath]) },
            set: { draft[keyPath: keyPath] = volumeUnit.milliliters(from: $0) }
        )
    }

    private func lengthBinding(_ keyPath: WritableKeyPath<EventDraft, Double>) -> Binding<Double> {
        Binding(
            get: { unitSystem.lengthValue(fromCentimeters: draft[keyPath: keyPath]) },
            set: { draft[keyPath: keyPath] = unitSystem.centimeters(fromLength: $0) }
        )
    }

    private var poundsBinding: Binding<Double> {
        Binding(
            get: { Double(UnitSystem.poundsOunces(fromKilograms: draft.weightKg).pounds) },
            set: { pounds in
                let ounces = UnitSystem.poundsOunces(fromKilograms: draft.weightKg).ounces
                draft.weightKg = UnitSystem.kilograms(pounds: pounds, ounces: ounces)
            }
        )
    }

    private var ouncesBinding: Binding<Double> {
        Binding(
            get: { UnitSystem.poundsOunces(fromKilograms: draft.weightKg).ounces },
            set: { ounces in
                let pounds = Double(UnitSystem.poundsOunces(fromKilograms: draft.weightKg).pounds)
                draft.weightKg = UnitSystem.kilograms(pounds: pounds, ounces: ounces)
            }
        )
    }

    // MARK: Actions

    private func save() {
        if draft.validationMessage != nil {
            attemptedSave = true
            return
        }
        switch target {
        case .new, .card, .seeded:
            let event = LogEvent.create(kind: draft.kind, for: baby, start: draft.startDate, in: context)
            draft.apply(to: event)
        case .edit(let event):
            draft.apply(to: event)
        }
        context.saveIfNeeded()
        Haptics.success()
        dismiss()
    }

    private func deleteEntry() {
        if case .edit(let event) = target {
            context.delete(event)
            context.saveIfNeeded()
        }
        dismiss()
    }
}

#Preview("New bottle") {
    EventEditorView(baby: PreviewData.baby, target: .new(.bottle))
        .previewEnvironment()
}

#Preview("New growth") {
    EventEditorView(baby: PreviewData.baby, target: .new(.growth))
        .previewEnvironment()
}

/// A tall time row. Shortcuts are calculated from the moment they are tapped.
private struct TimeValueRow: View {
    let title: String
    @Binding var date: Date
    @Environment(\.uiLanguage) private var language
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                Text(date.formatted(date: .omitted, time: .shortened))
                    .font(.title3.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("time-value")
        .sheet(isPresented: $open) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    shortcut(.now, UICopy.t(.now, language), "time-now")
                    shortcut(.tenMinutes, language == .zh ? "10分钟前" : "10 min ago", "time-10")
                    shortcut(.twentyMinutes, language == .zh ? "20分钟前" : "20 min ago", "time-20")
                    DatePicker(title, selection: $date)
                        .datePickerStyle(.compact)
                        .frame(minHeight: 44)
                }
                .padding(20)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(UICopy.t(.done, language)) { open = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func shortcut(_ choice: LogTimeShortcut, _ title: String, _ identifier: String) -> some View {
        Button {
            date = choice.date(from: .now)
            open = false
        } label: {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(identifier)
    }
}

private struct AmountSheet: View {
    @Binding var milliliters: Double
    let unit: VolumeUnit
    let language: ResolvedLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    TextField("0", text: $text)
                        .keyboardType(.decimalPad)
                        .font(.largeTitle.weight(.semibold))
                        .accessibilityIdentifier("bottle-amount")
                    Text(unit.symbol)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 64)
                let shortcuts = AmountShortcuts.milliliters(around: milliliters > 0 ? milliliters : nil)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                    ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, value in
                        Button(Copy.amount(value, unit: unit, language)) {
                            milliliters = value
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 48)
                    }
                }
            }
            .padding(20)
            .navigationTitle(UICopy.t(.amount, language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(UICopy.t(.done, language)) {
                        applyTyped()
                        dismiss()
                    }
                    .accessibilityIdentifier("amount-done")
                }
            }
            .onAppear {
                text = milliliters > 0 ? NumberField.format(unit.value(fromMilliliters: milliliters), digits: 1) : ""
            }
        }
        .presentationDetents([.medium])
    }

    private func applyTyped() {
        guard let parsed = NumberField.parse(text) else { return }
        milliliters = unit.milliliters(from: parsed)
    }
}
