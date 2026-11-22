import SwiftUI
import BabyLogKit

/// The local label for one baby. Cancel closes without writing. This does not invite anyone.
struct CaregiverRelationSheet: View {
    let babyID: UUID
    let babyName: String

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.storedDefault.rawValue
    @State private var draft: CaregiverRelationDraft
    @State private var managerID: UUID

    init(babyID: UUID, babyName: String, store: CaregiverRelationStore = CaregiverRelationStore()) {
        self.babyID = babyID
        self.babyName = babyName
        let manager = store.managerID()
        _managerID = State(initialValue: manager)
        _draft = State(initialValue: CaregiverRelationDraft(store.relation(managerID: manager, babyID: babyID)))
    }

    private var language: ResolvedLanguage {
        (AppLanguage(rawValue: languageRaw) ?? .zhHans).resolved()
    }

    private var chinese: Bool { language == .zh }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(CaregiverRelationKind.allCases) { kind in
                        Button {
                            draft.kind = kind
                        } label: {
                            HStack {
                                Text(kind == .custom
                                     ? (chinese ? "自定义" : "Custom")
                                     : kind.title(custom: "", chinese: chinese))
                                Spacer()
                                if draft.kind == kind {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .accessibilityIdentifier("caregiver-relation-\(kind.rawValue)")
                    }
                } header: {
                    Text(chinese ? "与\(babyName)的关系" : "Relation to \(babyName)")
                } footer: {
                    Text(chinese
                         ? "只是这台手机上的称呼。不会变成管理员，也不会发出邀请。"
                         : "A label on this phone. It does not grant access or send an invite.")
                }
                if draft.kind == .custom {
                    Section {
                        TextField(chinese ? "称呼" : "Name", text: $draft.customTitle)
                            .accessibilityIdentifier("caregiver-relation-custom")
                    }
                }
            }
            .navigationTitle(chinese ? "关系" : "Relation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(chinese ? "取消" : "Cancel") { dismiss() }
                        .accessibilityIdentifier("caregiver-relation-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(chinese ? "保存" : "Save") { save() }
                        .disabled(draft.committed(managerID: managerID, babyID: babyID) == nil)
                        .accessibilityIdentifier("caregiver-relation-save")
                }
            }
        }
    }

    private func save() {
        guard let relation = draft.committed(managerID: managerID, babyID: babyID) else { return }
        CaregiverRelationStore().save(relation)
        dismiss()
    }
}
