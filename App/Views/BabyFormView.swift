import SwiftUI
import UIKit
import PhotosUI
import CoreData
import BabyLogKit

/// Add a baby (`baby == nil`) or edit one. Saves itself, then calls `onSave` with the saved baby.
struct BabyFormView: View {
    let baby: Baby?
    let onSave: (Baby) -> Void
    /// A sheet needs its own stack. A page already pushed on 宝宝 must not add a second one.
    var embedsNavigation = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @Environment(\.persistence) private var persistence
    @Environment(\.uiLanguage) private var language

    @State private var name: String
    @State private var birthDate: Date
    @State private var hasClock: Bool
    @State private var birthClock: Date
    @State private var timeZoneID: String
    @State private var gender: String
    @State private var photo: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var removePhoto = false
    @State private var confirmDelete = false

    init(baby: Baby?, embedsNavigation: Bool = true, onSave: @escaping (Baby) -> Void) {
        self.baby = baby
        self.embedsNavigation = embedsNavigation
        self.onSave = onSave
        _name = State(initialValue: baby?.name ?? "")
        _birthDate = State(initialValue: baby?.birthDate ?? Date.now)
        let clock = baby?.birthClock
        _hasClock = State(initialValue: clock?.isEmpty == false)
        _birthClock = State(initialValue: Self.clockDate(clock) ?? Date.now)
        _timeZoneID = State(initialValue: baby?.birthTimeZoneID ?? "Asia/Shanghai")
        _gender = State(initialValue: baby?.genderRaw ?? "")
    }

    private static func clockDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: .now)
    }

    private var latestBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canDelete: Bool {
        guard let baby else { return false }
        return !persistence.isInSharedStore(baby)
    }

    var body: some View {
        if embedsNavigation {
            NavigationStack { editor }
        } else {
            editor
        }
    }

    private var editor: some View {
        Form {
            Section {
                TextField(UICopy.t(.babyName, language), text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("baby-name")
                DatePicker(
                        UICopy.t(.birthday, language),
                        selection: $birthDate,
                        in: ...latestBirthDate,
                        displayedComponents: .date
                    )
                    Picker(language == .zh ? "性别" : "Sex", selection: $gender) {
                        Text(language == .zh ? "未设置" : "Not set").tag("")
                        Text(language == .zh ? "女" : "Female").tag("female")
                        Text(language == .zh ? "男" : "Male").tag("male")
                    }
                    Toggle(language == .zh ? "填写出生时刻" : "Add a birth time", isOn: $hasClock)
                    if hasClock {
                        DatePicker(language == .zh ? "时刻" : "Time", selection: $birthClock, displayedComponents: .hourAndMinute)
                        Picker(language == .zh ? "时区" : "Time zone", selection: $timeZoneID) {
                            Text("Asia/Shanghai").tag("Asia/Shanghai")
                            Text("Asia/Hong_Kong").tag("Asia/Hong_Kong")
                            Text("Asia/Taipei").tag("Asia/Taipei")
                            Text("UTC").tag("UTC")
                        }
                    }
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label(language == .zh ? "本地头像" : "Photo on this phone", systemImage: "person.crop.circle")
                    }
                    .onChange(of: photo) { _, item in
                        Task {
                            if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                                pendingImage = image
                                removePhoto = false
                            }
                        }
                    }
                    if pendingImage != nil || (baby?.uuid).flatMap(BabyAvatarStore.image(for:)) != nil {
                        Button(language == .zh ? "去掉头像" : "Remove photo") { pendingImage = nil; removePhoto = true }
                    }
                    cultureSection
                }
                .themedSection()

                if canDelete {
                    Section {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Text(UICopy.t(.deleteBaby, language)).themedDestructive()
                        }
                    }
                    .themedSection()
                }
            }
            .themedList()
            .navigationTitle(baby == nil
                ? (language == .zh ? "添加宝宝" : "Add a baby")
                : (language == .zh ? "编辑宝宝" : "Edit baby"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(UICopy.t(.cancel, language)) { dismiss() }
                        .accessibilityIdentifier("baby-form-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(UICopy.t(.save, language)) { save() }
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty)
                        .accessibilityIdentifier("baby-form-save")
                }
            }
            .confirmationDialog(
                language == .zh
                    ? "删除\(baby?.displayName ?? "这个宝宝")？"
                    : "Delete \(baby?.displayName ?? "this baby")?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button(language == .zh ? "删除全部" : "Delete everything", role: .destructive) { deleteBaby() }
                Button(UICopy.t(.cancel, language), role: .cancel) {}
            } message: {
                Text(UICopy.t(.deleteBabyBody, language))
            }
    }

    private func save() {
        let trimmed = trimmedName
        guard !trimmed.isEmpty else { return }
        let saved: Baby
        if let baby {
            baby.name = trimmed
            baby.birthDate = birthDate
            saved = baby
        } else {
            saved = Baby.create(name: trimmed, birthDate: birthDate, in: context)
        }
        saved.genderRaw = gender.isEmpty ? nil : gender
        saved.birthTimeZoneID = timeZoneID
        if hasClock {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: birthClock)
            saved.birthClock = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        } else {
            saved.birthClock = nil
        }
        if let uuid = saved.uuid {
            if removePhoto { BabyAvatarStore.remove(id: uuid) }
            if let pendingImage { BabyAvatarStore.save(pendingImage, for: uuid) }
        }
        context.saveIfNeeded()
        Haptics.success()
        onSave(saved)
        dismiss()
    }

    private var cultureSection: some View {
        let zone = TimeZone(identifier: timeZoneID) ?? TimeZone(identifier: "Asia/Shanghai")!
        let parts = BabyCulture.civil(date: birthDate, timeZoneID: zone.identifier)
        let clock = hasClock ? BabyCulture.civil(date: birthClock, timeZoneID: zone.identifier) : nil
        let profile = BabyCulture.profile(
            year: parts.year,
            month: parts.month,
            day: parts.day,
            hour: hasClock ? clock?.hour : nil,
            minute: hasClock ? clock?.minute : nil,
            timeZoneID: zone.identifier
        )
        return Group {
            Text(profile.lunar)
            Text(language == .zh ? "生肖 \(profile.zodiac) · 星座 \(profile.sign)" : "\(profile.zodiac) · \(profile.sign)")
            Text(language == .zh ? "八字 \(profile.year) \(profile.month) \(profile.day) \(profile.hour ?? "时柱未提供")" : "\(profile.year) \(profile.month) \(profile.day) \(profile.hour ?? "hour not provided")")
            Text(BabyCulture.algorithm)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(language == .zh ? "这是历法显示，不是运势或健康建议。不是真太阳时。" : "Calendar display only. Not fortune or health advice. Not true solar time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func deleteBaby() {
        if let baby {
            context.delete(baby)
            context.saveIfNeeded()
        }
        dismiss()
    }
}

#Preview("Add") {
    BabyFormView(baby: nil) { _ in }
        .previewEnvironment()
}

#Preview("Edit") {
    BabyFormView(baby: PreviewData.baby) { _ in }
        .previewEnvironment()
}
