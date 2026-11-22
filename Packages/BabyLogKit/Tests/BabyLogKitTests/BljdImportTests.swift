import CoreData
import Foundation
import Testing
@testable import BabyLogKit

@MainActor
struct BljdImportTests {
    private func wrapped(_ tables: [String: [[String: Any]]]) -> Data {
        var object: [String: String] = [:]
        for key in BljdImporter.keys {
            let rows = tables[key] ?? []
            let data = try! JSONSerialization.data(withJSONObject: rows)
            object[key] = String(data: data, encoding: .utf8)!
        }
        return try! JSONSerialization.data(withJSONObject: object)
    }

    private func sample() -> Data {
        wrapped([
            "kExportKeyBabyInfos": [[
                "hashid": "baby-a", "name": "虚构甲", "gender": 0,
            ], [
                "hashid": "baby-b", "name": "虚构甲", "gender": 1,
            ]],
            "kExportKeyUrines": [[
                "hashid": "u1", "babyHashid": "baby-a", "time": "1700000000.0",
                "dateString": "1999-01-01", "end": "", "created_at": "1700001000.0",
            ]],
            "kExportKeyCraps": [[
                "hashid": "c1", "babyHashid": "baby-a", "time": "1700000000.0",
                "crapColor": 3, "crapAmount": 1, "crapShape": 2,
            ]],
            "kExportKeyFormulas": [[
                "hashid": "f1", "babyHashid": "baby-a", "time": "1700000100.0",
                "formulaFedAmount": "90",
            ]],
            "kExportKeyFoods": [[
                "hashid": "food1", "babyHashid": "baby-a", "time": "1700000200.0",
                "foodName": "虚构米糊", "foodItems": NSNull(),
            ]],
            "kExportKeyEvents": [[
                "hashid": "e-diaper", "babyHashid": "baby-a", "time": "1700000000.0", "eventType": "diaper",
            ], [
                "hashid": "e-todo", "babyHashid": "baby-a", "time": "1700000300.0", "eventType": "todo",
            ], [
                "hashid": "e-loose", "time": "1700000400.0", "eventType": "medicine",
            ]],
            "kExportKeyDeletes": [[
                "hashid": "del1",
                "snap": "{\"hashid\":\"ghost\",\"kind\":\"bottle\"}",
            ]],
            "kExportKeySleeps": [[
                "hashid": "s1", "babyHashid": "baby-b", "time": "1700000500.0", "end": "",
            ]],
        ])
    }

    @Test func contentNotExtensionDecodesTheWrapper() throws {
        let file = try #require(BljdImporter.parseIfWrapped(sample()))
        #expect(BljdImporter.parseIfWrapped(Data("{\"schema\":\"littlebabylog.import\"}".utf8)) == nil)
        let urine = try #require(file.rows.first { $0.field.externalId == "bljd:urines:u1" })
        #expect(urine.field.kind == .diaper)
        #expect(urine.field.diaper == .wet)
        #expect(urine.field.start == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(urine.field.end == nil)
        let formula = try #require(file.rows.first { $0.field.externalId == "bljd:formulas:f1" })
        #expect(formula.field.amountML == 90)
        #expect(formula.notices.joined().contains("毫升"))
        let food = try #require(file.rows.first { $0.field.externalId == "bljd:foods:food1" })
        #expect(food.field.food == "虚构米糊")
        #expect(food.field.amountML == nil)
        #expect(food.notices.joined().contains("不会补编"))
        let crap = try #require(file.rows.first { $0.field.externalId == "bljd:craps:c1" })
        #expect(crap.field.diaper == .dirty)
        #expect(crap.notices.joined().contains("crapColor=3"))
        #expect(file.rows.contains { $0.hold && $0.notices.joined().contains("gender=0") })
        #expect(file.rows.contains { $0.hold && $0.notices.joined().contains("todo") })
        #expect(file.rows.contains { $0.hold && $0.notices.joined().contains("墓碑") })
        #expect(file.rows.contains { $0.hold && $0.notices.joined().contains("没有 babyHashid") })
        #expect(!file.rows.contains { $0.field.externalId == "bljd:events:e-diaper" && !$0.hold })
    }

    @Test func sameNameBabiesStayApartAndUrineDoesNotCreateADiaperChange() throws {
        let file = try #require(BljdImporter.parseIfWrapped(sample()))
        let (_, context) = TestSupport.makeContext()
        let ada = Baby.create(name: "虚构甲", birthDate: .now, in: context)
        let bo = Baby.create(name: "虚构甲", birthDate: .now, in: context)
        let known = [
            KnownBaby(id: ada.uuid!, name: ada.displayName),
            KnownBaby(id: bo.uuid!, name: bo.displayName),
        ]
        let unmapped = StandardImporter.plan(file: file, babies: known, events: [])
        let urineLine = try #require(file.rows.first { $0.field.externalId == "bljd:urines:u1" }?.line)
        #expect(unmapped.first { $0.line == urineLine }?.action == .unmappedBaby)
        var assign: [String: UUID] = [:]
        assign["虚构甲 baby-a"] = ada.uuid
        let plan = StandardImporter.plan(file: file, babies: known, events: [], assign: assign)
        let sleepLine = try #require(file.rows.first { $0.field.externalId == "bljd:sleeps:s1" }?.line)
        #expect(plan.first { $0.line == sleepLine }?.action == .unmappedBaby)
        #expect(plan.first { $0.line == urineLine }?.action == .insert)
        let result = try ImportCommit.apply(file: file, plan: plan, babies: [ada.uuid!: ada, bo.uuid!: bo], in: context)
        #expect(result.inserted >= 1)
        let events = try context.fetch(LogEvent.fetchRequest())
        #expect(events.contains { $0.externalID == "bljd:urines:u1" && $0.diaperKind == .wet })
        #expect(!events.contains { $0.externalID?.hasPrefix(WetDiaperLink.prefix) == true })
        #expect(events.filter { $0.baby?.uuid == bo.uuid }.isEmpty)
        let again = StandardImporter.plan(file: file, babies: known, events: events.map {
            KnownEvent(babyID: $0.baby!.uuid!, externalID: $0.externalID, kind: $0.kind, start: $0.startDate!, diaper: $0.diaperKind)
        }, assign: assign)
        #expect(again.first { $0.line == urineLine }?.action == .skipIdempotent)
    }
}
