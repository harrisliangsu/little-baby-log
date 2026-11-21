import SwiftUI
import CoreData
import BabyLogKit

enum EditorTarget: Identifiable {
    case new(EventKind)
    case edit(LogEvent)
    /// A widget tap. The draft is empty until Save. Home-card history uses a different screen.
    case card(HomeCard)

    var id: String {
        switch self {
        case .new(let kind):
            return "new-" + kind.rawValue
        case .edit(let event):
            return "edit-" + event.objectID.uriRepresentation().absoluteString
        case .card(let card):
            return "card-" + card.rawValue
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
        }
    }

    private var isEditing: Bool {
        if case .edit = target { return true }
        return false
    }

    private var screenTitle: String {
        let name = UICopy.kind(draft.kind == .bottle ? .bottle : draft.kind, language)
        return isEditing ? "\(UICopy.t(.editPrefix, language))\(name)" : "\(UICopy.t(.newPrefix, language))\(language == .zh ? "" : " ")\(name)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(Copy.forBaby(baby.displayName, language))
                        .accessibilityIdentifier("composer-baby")
                    if let card = target.homeCard {
                        Text(card.rawValue)
                            .font(.system(size: 1))
                            .foregroundStyle(.clear)
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("composer-card")
                            .accessibilityLabel(card.rawValue)
                    }
                }
                kindFields

                Section {
                    TextField(UICopy.t(.notes, language), text: $draft.notes, axis: .vertical)
                        .lineLimit(1...5)
                } header: {
                    Text(UICopy.t(.notes, language))
                } footer: {
                    if let message = draft.validationMessage {
                        Text(UICopy.validation(message, language))
                            .foregroundStyle(theme.destructive)
                    }
                }
                .themedSection()

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
                        .disabled(draft.validationMessage != nil)
                        .accessibilityIdentifier("save-entry")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(UICopy.t(.done, language)) { UIApplication.endEditing() }
                }
            }
            .confirmationDialog(UICopy.t(.deleteConfirm, language), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(UICopy.t(.delete, language), role: .destructive) { deleteEntry() }
                Button(UICopy.t(.cancel, language), role: .cancel) {}
            }
        }
    }

    // MARK: Fields by kind

    private var kindFields: some View {
        kindSection.themedSection()
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
            DatePicker(UICopy.t(.start, language), selection: $draft.startDate)
            Toggle(UICopy.t(.stillAsleep, language), isOn: stillAsleep)
            if draft.endDate != nil {
                DatePicker(UICopy.t(.end, language), selection: endDateBinding)
                LabeledContent(UICopy.t(.duration, language), value: DurationFormat.short(sleepSeconds))
            }
        }
    }

    private var nursingFields: some View {
        Section {
            DatePicker(UICopy.t(.start, language), selection: $draft.startDate)
            if draft.isRunning {
                Text(UICopy.t(.timerRunning, language))
                    .font(.subheadline)
                    .foregroundStyle(theme.secondary)
            } else {
                NumberField(UICopy.t(.leftMinutes, language), value: minutesBinding(\.leftSeconds), unit: language == .zh ? "分钟" : "min")
                NumberField(UICopy.t(.rightMinutes, language), value: minutesBinding(\.rightSeconds), unit: language == .zh ? "分钟" : "min")
                Picker(UICopy.t(.lastSide, language), selection: $draft.lastSide) {
                    Text(UICopy.t(.none, language)).tag(BreastSide?.none)
                    ForEach(BreastSide.allCases) { side in
                        Text(UICopy.side(side, language)).tag(Optional(side))
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var bottleFields: some View {
        Section {
            DatePicker(UICopy.t(.time, language), selection: $draft.startDate)
            NumberField(UICopy.t(.amount, language), value: volumeBinding(\.amountML), unit: volumeUnit.symbol, identifier: "bottle-amount")
            Picker(UICopy.t(.contents, language), selection: $draft.bottleContent) {
                ForEach(BottleContent.allCases) { content in
                    Text(UICopy.bottle(content, language)).tag(content)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var solidsFields: some View {
        Section {
            DatePicker(UICopy.t(.time, language), selection: $draft.startDate)
            TextField(UICopy.t(.food, language), text: $draft.foodName)
                .textInputAutocapitalization(.sentences)
        }
    }

    private var diaperFields: some View {
        Section {
            DatePicker(UICopy.t(.time, language), selection: $draft.startDate)
            Picker(UICopy.kind(.diaper, language), selection: $draft.diaperKind) {
                ForEach(DiaperKind.allCases) { kind in
                    Text(UICopy.diaper(kind, language)).tag(kind)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var pumpFields: some View {
        Section {
            DatePicker(UICopy.t(.start, language), selection: $draft.startDate)
            NumberField(UICopy.t(.pumpDuration, language), value: minutesBinding(\.pumpDuration), unit: language == .zh ? "分钟" : "min")
            NumberField(UICopy.t(.left, language), value: volumeBinding(\.leftML), unit: volumeUnit.symbol)
            NumberField(UICopy.t(.right, language), value: volumeBinding(\.rightML), unit: volumeUnit.symbol)
        }
    }

    private var growthFields: some View {
        Section {
            DatePicker(UICopy.t(.time, language), selection: $draft.startDate)
            if unitSystem == .metric {
                NumberField(UICopy.t(.weight, language), value: $draft.weightKg, unit: "kg", digits: 3)
            } else {
                NumberField(UICopy.t(.weight, language), value: poundsBinding, unit: "lb", digits: 0)
                NumberField(UICopy.t(.ounces, language), value: ouncesBinding, unit: "oz", digits: 1)
            }
            NumberField(UICopy.t(.length, language), value: lengthBinding(\.lengthCm), unit: unitSystem.lengthSymbol)
            NumberField(UICopy.t(.head, language), value: lengthBinding(\.headCm), unit: unitSystem.lengthSymbol)
        }
    }

    private var medicineFields: some View {
        Section {
            DatePicker(UICopy.t(.time, language), selection: $draft.startDate)
            TextField(UICopy.t(.medicine, language), text: $draft.medicineName)
                .textInputAutocapitalization(.words)
            TextField(UICopy.t(.dose, language), text: $draft.dose)
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
        switch target {
        case .new(let kind):
            let event = LogEvent.create(kind: kind, for: baby, start: draft.startDate, in: context)
            draft.apply(to: event)
        case .card:
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
