import Foundation
import Testing
@testable import OmarchyVMHelper

@Suite("Per-VM migration history")
struct GuestMigrationHistoryTests {
    private let identity = String(repeating: "a", count: 64)

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Review shows additions and revisions, with only their groups and notes")
    func incrementalReview() throws {
        let catalog = try migrationCatalogFixture()
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        var revisions = catalog.revisions
        revisions.removeValue(forKey: "japanese-input")
        revisions["ghostty"] = 1
        let report = GuestBootFixReport(schema: 1, type: "boot-fixes", identity: identity,
            state: "complete", components: ["clipboard": "current", "screensaver": "current", "alacritty": "current"])
        try JSONEncoder().encode(GuestBootFixCache(checkedAt: Date(), report: report, revisions: revisions)).write(to: url)
        let pending = try #require(GuestBootFixCache.pendingIDs(cacheURL: url, catalog: catalog))
        #expect(pending == ["japanese-input", "ghostty"])
        let selected = catalog.selecting(pending)
        #expect(selected.features.map(\.title) == ["Japanese input", "Ghostty installer"])
        #expect(selected.groups.isEmpty)
        #expect(!selected.notes.contains("Battery"))
        #expect(catalog.selecting(["clock"]).features.map(\.title) == ["Clock"])
        #expect(catalog.selecting(["clock", "power", "holds"]).features.map(\.title) == ["Power, clock & update fixes"])
    }

    @Test("Checks and successful updates retain progress; interrupted attempts never advance it")
    func outcomeReceipts() throws {
        let catalog = try migrationCatalogFixture()
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        var outcomes = Dictionary(uniqueKeysWithValues: catalog.componentIDs.map { ($0, "current") })
        outcomes["japanese-input"] = "pending"
        outcomes["battery"] = "unavailable"
        let checked = GuestBootFixReport(schema: 1, type: "boot-fixes", identity: identity,
            state: "skipped", components: outcomes)
        try GuestBootFixCache.retain(checked, cacheURL: url, catalog: catalog)
        #expect(GuestBootFixCache.pendingIDs(cacheURL: url, catalog: catalog) == ["japanese-input"])
        for state in ["running", "failed", "recovery-required", "unconfirmed"] {
            let interrupted = GuestBootFixReport(schema: 1, type: "boot-fixes", identity: identity,
                state: state, components: GuestBootFixReport.pendingComponents)
            try GuestBootFixCache.retain(interrupted, cacheURL: url, catalog: catalog)
            #expect(GuestBootFixCache.pendingIDs(cacheURL: url, catalog: catalog) == ["japanese-input"])
        }
        outcomes["japanese-input"] = "applied"
        try GuestBootFixCache.retain(.init(schema: 1, type: "boot-fixes", identity: identity,
            state: "complete", components: outcomes), cacheURL: url, catalog: catalog)
        #expect(GuestBootFixCache.pendingIDs(cacheURL: url, catalog: catalog) == [])
    }

    @Test("Factory baselines come from the image; a replacement disk cannot inherit history")
    func factoryAndReset() throws {
        let catalog = try migrationCatalogFixture()
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = directory.appendingPathComponent("rootfs.ext4")
        try Data("disk".utf8).write(to: disk)
        let provenance = directory.appendingPathComponent("provenance.json")
        var revisions = catalog.revisions
        revisions["ghostty"] = 1 // The image may be older than the app's catalog.
        try JSONEncoder().encode(["migrationRevisions": revisions]).write(to: provenance)
        try GuestBootFixCache.seedFactory(storageRoot: directory, diskURL: disk,
            provenanceURL: provenance, catalog: catalog, identity: identity)
        let previous = try #require(GuestBootFixCache.url(storageRoot: directory, diskURL: disk))
        #expect(GuestBootFixCache.pendingIDs(cacheURL: previous, catalog: catalog) == ["ghostty"])
        // Model inode reuse by changing only the replacement's birth time.
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: disk.path)
        let replacement = try #require(GuestBootFixCache.url(storageRoot: directory, diskURL: disk))
        #expect(replacement != previous)
        #expect(GuestBootFixCache.read(replacement) == nil)
        try JSONEncoder().encode(["migrationRevisions": catalog.revisions]).write(to: provenance)
        try GuestBootFixCache.seedFactory(storageRoot: directory, diskURL: disk,
            provenanceURL: provenance, catalog: catalog, identity: identity)
        #expect(GuestBootFixCache.pendingIDs(cacheURL: replacement, catalog: catalog) == [])
    }

    @Test("Only complete inspection coverage for this bundle establishes a baseline")
    func inspectionValidation() throws {
        let catalog = try migrationCatalogFixture()
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("report.json")
        for state in ["complete", "skipped", "unconfirmed", "recovery-required"] {
            let report = GuestBootFixReport(schema: 1, type: "boot-fixes", identity: identity,
                state: state, components: Dictionary(uniqueKeysWithValues: catalog.componentIDs.map { ($0, "current") }))
            try JSONEncoder().encode(report).write(to: url)
            if ["complete", "skipped"].contains(state) {
                #expect(try GuestMigrationInspection.read(output: directory, identity: identity, catalog: catalog) == report)
            } else {
                #expect(throws: (any Error).self) { try GuestMigrationInspection.read(output: directory, identity: identity, catalog: catalog) }
            }
            #expect(throws: (any Error).self) {
                try GuestMigrationInspection.read(output: directory, identity: String(repeating: "b", count: 64), catalog: catalog)
            }
        }
        try Data(repeating: 32, count: 4097).write(to: url)
        #expect(throws: (any Error).self) { try GuestMigrationInspection.read(output: directory, identity: identity, catalog: catalog) }
    }
}
