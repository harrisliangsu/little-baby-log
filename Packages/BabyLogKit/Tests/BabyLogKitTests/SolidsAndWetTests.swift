import CoreData
import Foundation
import Testing
@testable import BabyLogKit

@MainActor
struct SolidsAndWetTests {
    @Test func oldFoodNameIsNotTurnedIntoSpoons() {
        let detail = SolidsDetail.reading(foodName: "米糊 30g", json: nil)
        #expect(detail.items.count == 1)
        #expect(detail.items[0].name == "米糊 30g")
        #expect(detail.items[0].spoons == nil)
        #expect(detail.waterML == nil)
    }

    @Test func severalFoodsShareOneWaterAmount() throws {
        let detail = SolidsDetail(
            items: [SolidsFood(name: "米糊", spoons: 1.5), SolidsFood(name: "蛋黄", spoons: 0.5)],
            waterML: 30
        )
        let again = SolidsDetail.reading(foodName: nil, json: detail.json)
        #expect(again.items.map(\.name) == ["米糊", "蛋黄"])
        #expect(again.items.map(\.spoons) == [1.5, 0.5])
        #expect(again.waterML == 30)
        #expect(again.reused().items.allSatisfy { $0.id != detail.items[0].id })
    }

    @Test func newWetWritesOneChangeAndASecondSaveDoesNot() throws {
        let (_, context) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: .now, in: context)
        let wet = LogEvent.create(kind: .diaper, for: baby, start: .now, in: context)
        wet.diaperKind = .wet
        WetDiaperLink.sync(event: wet, isNew: true, in: context)
        WetDiaperLink.sync(event: wet, isNew: true, in: context)
        let events = try context.fetch(LogEvent.fetchRequest())
        let changes = events.filter { $0.diaperKind == .dry }
        #expect(changes.count == 1)
        #expect(changes[0].externalID == WetDiaperLink.key(for: wet.uuid!))
        #expect(changes[0].baby?.uuid == baby.uuid)
        let alone = LogEvent.create(kind: .diaper, for: baby, start: .now, in: context)
        alone.diaperKind = .dry
        WetDiaperLink.sync(event: alone, isNew: true, in: context)
        let after = try context.fetch(LogEvent.fetchRequest())
        #expect(after.filter { $0.diaperKind == .wet }.count == 1)
        #expect(after.filter { WetDiaperLink.isAutomatic($0) }.count == 1)
    }

    @Test func editingAnOldWetDoesNotInventAChange() throws {
        let (_, context) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: .now, in: context)
        let wet = LogEvent.create(kind: .diaper, for: baby, start: .now, in: context)
        wet.diaperKind = .wet
        WetDiaperLink.sync(event: wet, isNew: false, in: context)
        let events = try context.fetch(LogEvent.fetchRequest())
        #expect(events.filter { $0.diaperKind == .dry }.isEmpty)
    }
}
