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
                "hashid": "baby-a", "name": "虚构甲", "gender": 0, "birthday": "2024-02-10", "dueDate": NSNull(),
            ], [
                "hashid": "baby-b", "name": "虚构甲", "gender": 1, "birthday": "2023-03-22", "dueDate": "2023-03-01",
            ]],
            "kExportKeyUrines": [[
                "hashid": "u1", "babyHashid": "baby-a", "urineTime": "1700000000.0",
                "dateString": "1999-01-01", "created_at": "1700001000.0",
            ], [
                "hashid": "u-decoy", "babyHashid": "baby-a", "time": "1700000000.0",
            ]],
            "kExportKeyCraps": [[
                "hashid": "c1", "babyHashid": "baby-a", "crapTime": "1700000000.0",
                "crapColor": 3, "crapAmount": 1, "crapShape": 2,
            ]],
            "kExportKeyFormulas": [[
                "hashid": "f1", "babyHashid": "baby-a",
                "formulaFedTime": "1700000100.0", "formulaFedEndTime": "", "formulaFedAmount": "90",
                "created_at": "1700001000.0",
            ]],
            "kExportKeyFoods": [[
                "hashid": "food1", "babyHashid": "baby-a",
                "fedTime": "1700000200.0", "fedEndTime": "", "foodName": "虚构米糊", "foodItems": NSNull(),
            ]],
            "kExportKeyBreasts": [[
                "hashid": "b1", "babyHashid": "baby-a",
                "breastFedTime": "1700000800", "endFedTime": "", "breastFedDuration": "600", "breastSide": 2,
            ]],
            "kExportKeySleeps": [[
                "hashid": "s1", "babyHashid": "baby-b", "starttime": "1700000500.0", "endtime": "",
                "startTime": "1690000000.0",
            ]],
            "kExportKeyBabyHeights": [[
                "hashid": "h1", "babyHashid": "baby-a", "dateString": "2024-02-10", "height": "70.0", "unit": "cm",
                "time": "1700000000.0",
            ]],
            "kExportKeyBabyWeights": [[
                "hashid": "w1", "babyHashid": "baby-a", "dateString": "2024-02-10", "weight": "8.0", "unit": "kg",
            ]],
            "kExportKeyRemarks": [[
                "hashid": "r1", "babyHashid": "baby-a", "remarkTime": "1700000300.0", "remark": "虚构备注", "note": "不要读这个",
            ]],
            "kExportKeyEvents": [[
                "hashid": "e-med", "babyHashid": "baby-a", "eventTime": "1700000700.0", "eventType": "medicine",
                "valueName": "虚构药", "value": "", "note": "",
            ], [
                "hashid": "e-water", "babyHashid": "baby-a", "eventTime": "1700000710.0", "eventType": "water", "value": "40",
            ], [
                "hashid": "e-head", "babyHashid": "baby-a", "eventTime": "1700000720.0", "eventType": "headCircumference", "value": "36.5",
            ], [
                "hashid": "e-vac", "babyHashid": "baby-a", "eventTime": "1700000730.0", "eventType": "vaccination", "value": "虚构疫苗",
            ], [
                "hashid": "e-mile", "babyHashid": "baby-a", "eventTime": "1700000740.0", "eventType": "milestone", "valueName": "虚构里程",
            ], [
                "hashid": "e-user", "babyHashid": "baby-a", "eventTime": "1700000600.0", "eventType": "userDefinedRecord",
                "valueName": "1700000000000", "value": "原值", "note": "原注",
            ], [
                "hashid": "e-diaper", "babyHashid": "baby-a", "eventTime": "1700000000.0", "eventType": "diaper",
            ], [
                "hashid": "e-todo", "babyHashid": "baby-a", "eventTime": "1700000750.0", "eventType": "todo",
            ]],
            "kExportKeyDeletes": [[
                "hashid": "del1",
                "snap": "{\"hashid\":\"ghost-breast\",\"breastFedTime\":\"1700000900\",\"eventType\":\"breast\"}",
            ]],
        ])
    }

    @Test func exactFieldsNotGuessedNames() throws {
        let file = try #require(BljdImporter.parseIfWrapped(sample()))
        let urine = try #require(file.rows.first { $0.field.externalId == "bljd:urines:u1" })
        #expect(urine.field.start == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(urine.problems.isEmpty)
        let decoy = try #require(file.rows.first { $0.field.externalId == "bljd:urines:u-decoy" })
        #expect(decoy.problems.contains(.missingStart))
        let formula = try #require(file.rows.first { $0.field.externalId == "bljd:formulas:f1" })
        #expect(formula.field.start == Date(timeIntervalSince1970: 1_700_000_100))
        #expect(formula.field.end == nil)
        #expect(formula.field.amountML == 90)
        let food = try #require(file.rows.first { $0.field.externalId == "bljd:foods:food1" })
        #expect(food.field.start == Date(timeIntervalSince1970: 1_700_000_200))
        #expect(food.field.food == "虚构米糊")
        let breast = try #require(file.rows.first { $0.field.externalId == "bljd:breasts:b1" })
        #expect(breast.field.start == Date(timeIntervalSince1970: 1_700_000_800))
        #expect(breast.field.leftSeconds == 0)
        #expect(breast.field.rightSeconds == 0)
        #expect(breast.notices.joined().contains("breastSide=2"))
        let sleep = try #require(file.rows.first { $0.field.externalId == "bljd:sleeps:s1" })
        #expect(sleep.field.start == Date(timeIntervalSince1970: 1_700_000_500))
        #expect(sleep.field.end == nil)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let day = calendar.date(from: DateComponents(year: 2024, month: 2, day: 10))
        let height = try #require(file.rows.first { $0.field.externalId == "bljd:heights:h1" })
        #expect(height.field.start == day)
        #expect(height.field.start != Date(timeIntervalSince1970: 1_700_000_000))
        #expect(height.field.lengthCm == 70)
        #expect(height.notices.joined().contains("只有日期 2024-02-10"))
        let weight = try #require(file.rows.first { $0.field.externalId == "bljd:weights:w1" })
        #expect(weight.field.weightKg == 8)
        let medicine = try #require(file.rows.first { $0.field.externalId == "bljd:events:e-med" })
        #expect(medicine.field.medicine == "虚构药")
        #expect(medicine.field.dose.isEmpty)
        let joined = file.rows.filter(\.hold).flatMap(\.notices).joined(separator: "\n")
        #expect(joined.contains("虚构备注"))
        #expect(!joined.contains("不要读这个"))
        #expect(joined.contains("value=40"))
        #expect(joined.contains("不会写成厘米"))
        #expect(joined.contains("虚构疫苗"))
        #expect(joined.contains("虚构里程"))
        #expect(joined.contains("valueName=1700000000000"))
        #expect(joined.contains("不另造"))
        #expect(joined.contains("墓碑"))
        #expect(joined.contains("gender=0"))
        #expect(!file.rows.contains { $0.field.externalId == "bljd:breasts:ghost-breast" })
        #expect(file.rows.contains { $0.hold && $0.notices.joined().contains("valueName=1700000000000") && $0.field.start == nil })
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
        var assign: [String: UUID] = [:]
        assign["虚构甲 baby-a"] = ada.uuid
        let plan = StandardImporter.plan(file: file, babies: known, events: [], assign: assign)
        let urineLine = try #require(file.rows.first { $0.field.externalId == "bljd:urines:u1" }?.line)
        let sleepLine = try #require(file.rows.first { $0.field.externalId == "bljd:sleeps:s1" }?.line)
        let urineAction = plan.first { $0.line == urineLine }?.action
        let sleepAction = plan.first { $0.line == sleepLine }?.action
        #expect(urineAction == .insert)
        #expect(sleepAction == .unmappedBaby)
        _ = try ImportCommit.apply(file: file, plan: plan, babies: [ada.uuid!: ada, bo.uuid!: bo], in: context)
        let events = try context.fetch(LogEvent.fetchRequest())
        let keptUrine = events.contains { $0.externalID == "bljd:urines:u1" && $0.diaperKind == .wet }
        #expect(keptUrine)
        let linked = events.contains { event in
            guard let id = event.externalID else { return false }
            return id.hasPrefix(WetDiaperLink.prefix)
        }
        #expect(linked == false)
        let writtenToOtherBaby = events.contains { event in
            guard let baby = event.baby else { return false }
            return baby.uuid == bo.uuid
        }
        #expect(writtenToOtherBaby == false)
        let again = StandardImporter.plan(file: file, babies: known, events: events.map {
            KnownEvent(babyID: $0.baby!.uuid!, externalID: $0.externalID, kind: $0.kind, start: $0.startDate!, diaper: $0.diaperKind)
        }, assign: assign)
        let againAction = again.first { $0.line == urineLine }?.action
        #expect(againAction == .skipIdempotent)
    }
}
