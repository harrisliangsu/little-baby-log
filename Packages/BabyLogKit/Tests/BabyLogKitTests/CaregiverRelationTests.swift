import Foundation
import Testing
@testable import BabyLogKit

struct CaregiverRelationTests {
    private let ada = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAA01")!
    private let bo = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBB02")!

    private func store() -> (UserDefaults, CaregiverRelationStore) {
        let defaults = UserDefaults(suiteName: "caregiver-relation-tests-\(UUID().uuidString)")!
        return (defaults, CaregiverRelationStore(defaults: defaults))
    }

    @Test func unsetStaysUnsetAndBabiesStaySeparate() {
        let (_, relations) = store()
        let manager = relations.managerID()
        #expect(relations.managerID() == manager)
        #expect(relations.relation(managerID: manager, babyID: ada) == nil)
        relations.save(CaregiverRelation(managerID: manager, babyID: ada, kind: .father))
        #expect(relations.relation(managerID: manager, babyID: ada)?.kind == .father)
        #expect(relations.relation(managerID: manager, babyID: bo) == nil)
        relations.save(CaregiverRelation(managerID: manager, babyID: bo, kind: .maternalGrandmother))
        #expect(relations.relation(managerID: manager, babyID: ada)?.kind == .father)
        #expect(relations.relation(managerID: manager, babyID: bo)?.kind == .maternalGrandmother)
    }

    @Test func customCancelDoesNotReplaceTheSavedTitle() {
        let (_, relations) = store()
        let manager = relations.managerID()
        let saved = CaregiverRelation(managerID: manager, babyID: ada, kind: .mother)
        relations.save(saved)
        var draft = CaregiverRelationDraft(saved)
        draft.kind = .custom
        draft.customTitle = "叔叔"
        let pending = draft.committed(managerID: manager, babyID: ada)
        #expect(pending?.customTitle == "叔叔")
        #expect(relations.relation(managerID: manager, babyID: ada) == saved)
        draft.customTitle = "  "
        #expect(draft.committed(managerID: manager, babyID: ada) == nil)
    }

    @Test func relaunchKeepsTheRelationAndDoesNotStoreARole() throws {
        let (defaults, relations) = store()
        let manager = relations.managerID()
        relations.save(CaregiverRelation(managerID: manager, babyID: ada, kind: .custom, customTitle: "干妈"))
        let again = CaregiverRelationStore(defaults: defaults)
        let loaded = again.relation(managerID: manager, babyID: ada)
        #expect(loaded?.title(chinese: true) == "干妈")
        let data = try #require(defaults.data(forKey: CaregiverRelationStore.relationsKey))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("role"))
        #expect(!text.contains("permission"))
        #expect(!text.contains("CKShare"))
        #expect(defaults.object(forKey: "cloudSyncEnabled") == nil)
        #expect(defaults.string(forKey: CaregiverRelationStore.managerKey) == manager.uuidString)
    }

    @Test func missingStoreIsUnsetRatherThanADefaultParent() {
        let (_, relations) = store()
        #expect(relations.all().isEmpty)
        let draft = CaregiverRelationDraft(nil)
        #expect(draft.committed(managerID: UUID(), babyID: ada) == nil)
    }
}
