import Foundation
import Testing
@testable import BabyLogKit

struct ImportLaneTests {
    @Test func standardJSONStaysOffline() {
        ImportTraffic.reset()
        let json = """
        {"schema":"littlebabylog.import","schemaVersion":1,"rows":[{"babyName":"月月","kind":"diaper","start":"2026-03-10T09:00:00+08:00","diaper":"wet"}]}
        """
        let result = ImportIntake.openOrdinary(data: Data(json.utf8), filename: "feed.json")
        guard case .schema(let file) = result else {
            Issue.record("expected a schema file")
            return
        }
        #expect(file.rows.first?.field.diaper == .wet)
        #expect(file.rows.first?.field.kind == .diaper)
        #expect(ImportTraffic.modelRequests == 0)
    }

    @Test func foreignCSVAsksForALocalMapAndDoesNotCallAModel() {
        ImportTraffic.reset()
        let csv = "Baby,What,When\n月月,pee,2026-03-10\n"
        let result = ImportIntake.openOrdinary(data: Data(csv.utf8), filename: "other.csv")
        guard case .manual(let table) = result else {
            Issue.record("expected a manual map")
            return
        }
        #expect(table.headers == ["Baby", "What", "When"])
        let mapped = ImportIntake.applyManualMap(table, mappings: [
            ColumnMapping(source: "Baby", target: "babyName"),
            ColumnMapping(source: "What", target: "kind"),
            ColumnMapping(source: "When", target: "start"),
        ])
        #expect(mapped.fileProblems.isEmpty)
        #expect(mapped.rows.first?.field.babyName == "月月")
        #expect(mapped.rows.first?.problems.contains(.unknownKind("pee")) == true)
        #expect(ImportTraffic.modelRequests == 0)
        ImportTraffic.noteModelRequest(lane: .ordinary)
        #expect(ImportTraffic.modelRequests == 0)
    }

    @Test func pictureAndPDFAreRefusedWithoutUpload() {
        ImportTraffic.reset()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        if case .rejected(let message) = ImportIntake.openOrdinary(data: png, filename: "scan.png") {
            #expect(message.contains("没有上传"))
        } else {
            Issue.record("png should be rejected")
        }
        let pdf = Data("%PDF-1.4\n".utf8)
        if case .rejected(let message) = ImportIntake.openOrdinary(data: pdf, filename: "book.pdf") {
            #expect(message.contains("没有上传") || message.contains("没有可提取"))
        } else {
            Issue.record("pdf should be rejected")
        }
        #expect(ImportTraffic.modelRequests == 0)
    }

    @Test func assistedCounterDoesNotMoveTheOrdinaryDoor() {
        ImportTraffic.reset()
        ImportTraffic.noteModelRequest(lane: .assisted)
        #expect(ImportTraffic.modelRequests == 1)
        _ = ImportIntake.openOrdinary(data: Data("hello".utf8), filename: "note.txt")
        #expect(ImportTraffic.modelRequests == 1)
    }

    @Test func syntheticBljdIsNotGuessedOrSent() {
        ImportTraffic.reset()
        var bytes = Data([0x00, 0x11, 0x22, 0x33, 0x44])
        bytes.append(Data(count: 64))
        let ordinary = ImportIntake.openOrdinary(data: bytes, filename: "fixture-not-a-real-backup.bljd")
        let assisted = ImportIntake.openAssisted(data: bytes, filename: "fixture-not-a-real-backup.bljd")
        if case .rejected(let message) = ordinary {
            #expect(message.contains("没有发给 AI") || message.contains("没有把二进制"))
        } else {
            Issue.record("ordinary bljd fixture should be rejected")
        }
        if case .unsupported(let message) = assisted {
            #expect(!message.contains("ZIP") || bytes.prefix(2) == Data([0x50, 0x4B]))
            #expect(message.contains("AI") || message.contains("没有"))
        } else {
            Issue.record("assisted bljd fixture should be unsupported")
        }
        #expect(ImportTraffic.modelRequests == 0)
        let prompt = ImportIntake.assistPrompt("kind,start")
        #expect(!prompt.contains("sk-"))
        #expect(prompt.contains("littlebabylog.import"))
    }

    @Test func zipClaimIsNotInflated() {
        var header = Data([0x50, 0x4B, 0x03, 0x04])
        header.append(contentsOf: [20, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        header.append(contentsOf: [0, 0, 0, 0])
        header.append(contentsOf: [0, 0, 0, 0])
        header.append(contentsOf: [0, 0, 2, 0])
        header.append(contentsOf: [1, 0, 0, 0])
        header.append(Data("a".utf8))
        let result = ImportIntake.openAssisted(data: header, filename: "fixture.bljd")
        if case .unsupported(let message) = result {
            #expect(message.contains("没有发给 AI"))
            #expect(message.contains("过大") || message.contains("ZIP"))
        } else {
            Issue.record("huge zip claim should be refused")
        }
        #expect(ImportTraffic.modelRequests == 0)
    }
}
