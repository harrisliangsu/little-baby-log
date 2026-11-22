import SwiftUI
import UIKit
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
    var onFinish: ((Bool) -> Void)? = nil

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
            .safeAreaInset(edge: .bottom, spacing: 8) {
                Button { save() } label: {
                    Text(UICopy.t(.save, language))
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("save-entry")
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(UICopy.t(.cancel, language)) {
                        onFinish?(false)
                        dismiss()
                    }
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
            if draft.bottleContent == .formula || target.homeCard == .formula {
                FormulaAmountShortcuts(
                    milliliters: $draft.amountML,
                    language: language,
                    last: lastFormulaAmount,
                    pinned: pinnedFormulaAmount,
                    onPin: { pinFormulaAmount($0) },
                    onClearPin: { pinFormulaAmount(nil) }
                )
            } else {
                InlineAmountEditor(milliliters: $draft.amountML, unit: volumeUnit, language: language)
            }
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
            if draft.solids.items.isEmpty {
                TextField(UICopy.t(.food, language), text: $draft.foodName)
                    .accessibilityIdentifier("solids-name")
            }
            ForEach(draft.solids.items.indices, id: \.self) { index in
                TextField(language == .zh ? "食物" : "Food", text: $draft.solids.items[index].name)
                    .accessibilityIdentifier("solids-name-\(index)")
                TextField(language == .zh ? "勺" : "Spoons", value: spoonBinding(index), format: .number)
                    .accessibilityIdentifier("solids-spoons-\(index)")
                Button(language == .zh ? "移除" : "Remove") {
                    draft.solids.items.remove(at: index)
                }
            }
            Button(language == .zh ? "添加食物" : "Add a food") {
                draft.solids.items.append(SolidsFood(name: ""))
            }
            .accessibilityIdentifier("solids-add")
            TextField(language == .zh ? "水（毫升）" : "Water (ml)", value: $draft.solids.waterML, format: .number)
                .accessibilityIdentifier("solids-water")
            Text(language == .zh
                 ? "勺数和毫升是这次的记录。水是这一顿共用的，不按每种食物再计一次，也不是冲调建议。"
                 : "Spoons and millilitres are a record of this meal. The water is shared, not counted again for each food, and it is not a mixing recommendation.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            saveError
        }
    }

    private func spoonBinding(_ index: Int) -> Binding<Double?> {
        Binding(
            get: { draft.solids.items.indices.contains(index) ? draft.solids.items[index].spoons : nil },
            set: { draft.solids.items[index].spoons = $0 }
        )
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

    private var formulaPinKey: String { "lbl-formula-pin-\(baby.uuid?.uuidString ?? "")" }

    private var lastFormulaAmount: Double? {
        let request = LogEvent.requestAll(baby: baby, kinds: [.bottle], ascending: false)
        let events = (try? context.fetch(request)) ?? []
        return FormulaAmountSeed.milliliters(newestFirst: events)
    }

    private var pinnedFormulaAmount: Double? {
        let stored = UserDefaults.standard.object(forKey: formulaPinKey) as? Double
        guard let stored, stored > 0 else { return nil }
        return stored
    }

    private func pinFormulaAmount(_ amount: Double?) {
        if let amount, amount > 0 {
            UserDefaults.standard.set(amount, forKey: formulaPinKey)
        } else {
            UserDefaults.standard.removeObject(forKey: formulaPinKey)
        }
    }

    private func seedFormulaAmountIfNeeded() {
        guard !seededFormula else { return }
        seededFormula = true
        guard case .card(.formula) = target, draft.amountML <= 0 else { return }
        if let amount = FormulaPreparedTable.prefill(last: lastFormulaAmount, pinned: pinnedFormulaAmount) {
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
            WetDiaperLink.sync(event: event, isNew: true, in: context)
        case .edit(let event):
            draft.apply(to: event)
            WetDiaperLink.sync(event: event, isNew: false, in: context)
        }
        context.saveIfNeeded()
        Haptics.success()
        onFinish?(true)
        dismiss()
    }

    private func deleteEntry() {
        if case .edit(let event) = target {
            WetDiaperLink.deleteLinked(to: event, in: context)
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

/// Time shortcuts and the date control sit on the form. Nothing opens a second sheet.
private struct TimeValueRow: View {
    let title: String
    @Binding var date: Date
    @Environment(\.uiLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                shortcut(.now, UICopy.t(.now, language), "time-now")
                shortcut(.tenMinutes, language == .zh ? "10分钟前" : "10 min ago", "time-10")
                shortcut(.twentyMinutes, language == .zh ? "20分钟前" : "20 min ago", "time-20")
            }
            DatePicker(title, selection: $date)
                .datePickerStyle(.compact)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("time-value")
        }
        .padding(.vertical, 4)
    }

    private func shortcut(_ choice: LogTimeShortcut, _ title: String, _ identifier: String) -> some View {
        Button {
            date = choice.date(from: .now)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(identifier)
    }
}

/// Prepared totals from the tin. Water amounts are not offered. Off-table history stays editable.
private struct FormulaAmountShortcuts: View {
    @Binding var milliliters: Double
    let language: ResolvedLanguage
    let last: Double?
    let pinned: Double?
    let onPin: (Double) -> Void
    let onClearPin: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            numberField
            Text(language == .zh ? "冲好总奶量" : "Prepared total")
                .font(.subheadline.weight(.semibold))
            Text(language == .zh
                 ? "罐上的成品量，用来快捷填写，不是喂养建议。"
                 : "Prepared amounts from the tin. A shortcut, not feeding advice.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                ForEach(Array(FormulaPreparedTable.milliliters.enumerated()), id: \.offset) { index, amount in
                    Button(label(amount, scoops: FormulaPreparedTable.scoops[index])) {
                        apply(amount)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("amount-prepared-\(Int(amount))")
                }
            }
            if let last, last > 0, !FormulaPreparedTable.matches(last), pinned == nil {
                Text(language == .zh
                     ? "上次记下 \(shown(last))。它不在冲好总奶量里，所以没有当成默认。历史还在，少量也可以手改保存。"
                     : "Last saved \(shown(last)). It is not a prepared total, so it is not the default. History stays, and a small amount can still be typed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(language == .zh ? "填入上次" : "Use last") { apply(last) }
                        .frame(minHeight: 44)
                    Button(language == .zh ? "以后沿用" : "Keep using it") { onPin(last) }
                        .frame(minHeight: 44)
                }
            } else if pinned != nil {
                Button(language == .zh ? "不再沿用指定用量" : "Stop using the pinned amount") { onClearPin() }
                    .font(.footnote)
                    .frame(minHeight: 44)
            }
        }
        .onAppear { text = milliliters > 0 ? NumberField.format(milliliters, digits: 1) : "" }
    }

    private var numberField: some View {
        HStack(spacing: 4) {
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .font(.system(size: 40, weight: .semibold))
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .frame(minWidth: 56, minHeight: 56)
                .accessibilityIdentifier("bottle-amount")
            Text("ml")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .onChange(of: text) { _, newText in
            guard focused, let parsed = NumberField.parse(newText) else { return }
            milliliters = parsed
        }
    }

    private func label(_ amount: Double, scoops: Int) -> String {
        language == .zh ? "\(Int(amount)) ml · \(scoops)勺" : "\(Int(amount)) ml · \(scoops)"
    }

    private func shown(_ amount: Double) -> String {
        "\(Int(amount.rounded())) ml"
    }

    private func apply(_ amount: Double) {
        milliliters = amount
        text = NumberField.format(amount, digits: 1)
        focused = false
    }
}

/// Amount field for bottle contents other than formula. No invented nearby sizes.
private struct InlineAmountEditor: View {
    @Binding var milliliters: Double
    let unit: VolumeUnit
    let language: ResolvedLanguage
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let shown = unit.value(fromMilliliters: milliliters)
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 40, weight: .semibold))
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
                    .frame(minWidth: 56, minHeight: 56)
                    .accessibilityIdentifier("bottle-amount")
                Text(unit.symbol)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .padding(.vertical, 4)
        .onAppear {
            text = milliliters > 0 ? NumberField.format(shown, digits: 1) : ""
        }
        .onChange(of: text) { _, newText in
            guard focused, let parsed = NumberField.parse(newText) else { return }
            milliliters = unit.milliliters(from: parsed)
        }
    }
}
