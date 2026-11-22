import SwiftUI
import CoreData
import BabyLogKit

/// Add a baby (`baby == nil`) or edit one. Saves itself, then calls `onSave` with the saved baby.
struct BabyFormView: View {
    let baby: Baby?
    let onSave: (Baby) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @Environment(\.persistence) private var persistence
    @Environment(\.uiLanguage) private var language

    @State private var name: String
    @State private var birthDate: Date
    @State private var confirmDelete = false

    init(baby: Baby?, onSave: @escaping (Baby) -> Void) {
        self.baby = baby
        self.onSave = onSave
        _name = State(initialValue: baby?.name ?? "")
        _birthDate = State(initialValue: baby?.birthDate ?? Date.now)
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
        NavigationStack {
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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(UICopy.t(.save, language)) { save() }
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty)
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
        context.saveIfNeeded()
        Haptics.success()
        onSave(saved)
        dismiss()
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
