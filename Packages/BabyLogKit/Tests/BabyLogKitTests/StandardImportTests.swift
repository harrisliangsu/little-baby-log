import CoreData
import Foundation
import Testing
@testable import BabyLogKit

@MainActor
struct StandardImportTests {
    private let header = StandardImporter.columns.joined(separator: ",")

    private func row(_ values: [String: String]) -> String {
        StandardImporter.columns.map { values[$0] ?? "" }.joined(separator: ",")
    }

    @Test func jsonAndCSVKeepTheOffsetAndRejectABadVersion() throws {
        let json = """
        {"schema":"littlebabylog.import","schemaVersion":1,"rows":[{"babyName":"月月","kind":"bottle","start":"2026-03-10T23:30:00+08:00","amountML":40,"amountUnit":"ml","bottleContent":"formula"}]}
        """
        let file = StandardImporter.parse(data: Data(json.utf8))
        let start = try #require(file.rows.first?.field.start)
        var shanghai = Calendar(identifier: .gregorian)
        shanghai.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let parts = shanghai.dateComponents([.hour, .minute], from: start)
        #expect(parts.hour == 23)
        #expect(parts.minute == 30)
        #expect(file.rows.first?.field.amountML == 40)

        let csv = "# littlebabylog.import 1\n" + header + "\n" + row([
            "schemaVersion": "1", "babyName": "月月", "kind": "sleep",
            "start": "2026-03-10T23:30:00+08:00", "end": "2026-03-11T01:00:00+08:00",
        ])
        let sleep = StandardImporter.parse(data: Data(csv.utf8))
        let sleepRow = try #require(sleep.rows.first)
        #expect(sleep.fileProblems.isEmpty)
        #expect(sleepRow.field.end != nil)
        #expect(sleepRow.problems.isEmpty)

        let bad = StandardImporter.parse(data: Data(#"{"schema":"other","schemaVersion":1,"rows":[]}"#.utf8))
        #expect(bad.fileProblems == [.unsupportedVersion])
        let latin = StandardImporter.parse(data: Data([0xFF, 0xFE, 0x41]))
        #expect(latin.fileProblems == [.badEncoding])
        let bare = StandardImporter.parse(data: Data("2026-03-10 23:30,feed\n".utf8))
        #expect(bare.fileProblems == [.missingHeader])
    }

    @Test func ouncesUnknownsAndFormulaText() {
        let csv = header + "\n" + row([
            "babyName": "Ada", "kind": "bottle", "start": "2026-03-10T09:00:00Z",
            "amountML": "2", "amountUnit": "oz", "bottleContent": "formula", "notes": "=cmd",
        ]) + "\n" + row([
            "babyName": "Ada", "kind": "teleport", "start": "2026-03-10T10:00:00Z",
        ]) + "\n" + row([
            "babyName": "Ada", "kind": "diaper", "start": "not-a-date", "diaper": "sparkles",
        ])
        let file = StandardImporter.parse(data: Data(csv.utf8))
        #expect(abs((file.rows[0].field.amountML ?? 0) - VolumeUnit.ounces.milliliters(from: 2)) < 0.001)
        #expect(file.rows[0].field.notes == "=cmd")
        #expect(file.rows[1].problems.contains(.unknownKind("teleport")))
        #expect(file.rows[2].problems.contains(.badDate))
        #expect(file.rows[2].problems.contains(.unknownValue("sparkles")))
        #expect(file.rows.count == 3)
    }

    @Test func mappingDedupRollbackAndUndo() throws {
        let (_, context) = TestSupport.makeContext()
        let ada = Baby.create(name: "Ada", birthDate: TestSupport.utc(2026, 1, 1), in: context)
        let existing = LogEvent.create(kind: .bottle, for: ada, start: TestSupport.utc(2026, 3, 10, 9), in: context)
        existing.amountML = 40
        existing.bottleContent = .formula
        existing.externalID = "keep-me"
        let sameTimeDifferentAmount = LogEvent.create(kind: .bottle, for: ada, start: TestSupport.utc(2026, 3, 10, 12), in: context)
        sameTimeDifferentAmount.amountML = 150
        sameTimeDifferentAmount.bottleContent = .formula
        try context.save()
        let before = try context.fetch(LogEvent.fetchRequest()).count

        let csv = header + "\n" + [
            row(["babyName": "Ada", "externalId": "keep-me", "kind": "bottle", "start": "2026-03-10T09:00:00Z", "amountML": "40", "bottleContent": "formula"]),
            row(["babyName": "Ada", "kind": "bottle", "start": "2026-03-10T12:00:00Z", "amountML": "150", "bottleContent": "formula"]),
            row(["babyName": "Ada", "kind": "bottle", "start": "2026-03-10T12:00:00Z", "amountML": "80", "bottleContent": "formula"]),
            row(["babyName": "Bo", "kind": "bottle", "start": "2026-03-10T13:00:00Z", "amountML": "10", "bottleContent": "formula"]),
            row(["babyName": "Ada", "externalId": "new-1", "kind": "sleep", "start": "2026-03-10T23:30:00+08:00", "end": "2026-03-11T01:00:00+08:00"]),
        ].joined(separator: "\n")
        let file = StandardImporter.parse(data: Data(csv.utf8))
        let babies = [KnownBaby(id: try #require(ada.uuid), name: "Ada")]
        let known = try context.fetch(LogEvent.fetchRequest()).map {
            KnownEvent(
                babyID: $0.baby?.uuid ?? UUID(), externalID: $0.externalID, kind: $0.kind,
                start: $0.startDate ?? .distantPast, amountML: $0.amountML, bottleContent: $0.bottleContent
            )
        }
        let plan = StandardImporter.plan(file: file, babies: babies, events: known)
        #expect(plan.map(\.action) == [.skipIdempotent, .skipCandidate, .insert, .unmappedBaby, .insert])

        let result = try ImportCommit.apply(
            file: file, plan: plan, babies: [try #require(ada.uuid): ada], in: context
        )
        #expect(result.inserted == 2)
        #expect(try context.fetch(LogEvent.fetchRequest()).count == before + 2)
        let sleep = try context.fetch(LogEvent.fetchRequest()).first { $0.externalID == "new-1" }
        #expect(sleep?.endDate != nil)
        #expect(sleep?.startDate ?? .distantPast < (sleep?.endDate ?? .distantPast))

        let edited = try #require(context.fetch(LogEvent.fetchRequest()).first { $0.kind == .bottle && $0.amountML == 80 })
        edited.notes = "changed"
        edited.modifiedAt = Date().addingTimeInterval(5)
        try context.save()
        let undo = try ImportCommit.undo(batchID: result.batchID, in: context)
        #expect(undo.deleted == 1)
        #expect(undo.keptBecauseEdited == 1)
        #expect(try context.fetch(LogEvent.fetchRequest()).contains { $0.externalID == "keep-me" })
        #expect(try context.fetch(LogEvent.fetchRequest()).contains { $0.amountML == 150 && $0.importBatchID == nil })
    }
}
