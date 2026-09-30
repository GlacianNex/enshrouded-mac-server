import XCTest
import AppKit
import SwiftUI
import Darwin
import EnshroudedCore
@testable import EnshroudedManager

final class WorkflowParityTests: XCTestCase {
    @MainActor private func withFixture(_ body: (URL) async throws -> Void) async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = root.appendingPathComponent("server")
        let resources = root.appendingPathComponent("resources")
        let previousHome = ProcessInfo.processInfo.environment["ESM_HOME"]
        let previousResources = ProcessInfo.processInfo.environment["ESM_RESOURCES"]
        let previousOperations = ApplicationLifetime.activeOperations
        for url in [home.appendingPathComponent("lima/engine"), home.appendingPathComponent("data/server"), resources.appendingPathComponent("Lima/bin")] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try Data("fixture".utf8).write(to: home.appendingPathComponent("lima/engine/lima.yaml"))
        try Data("{\"name\":\"Isolated Workflow Server\"}".utf8).write(to: home.appendingPathComponent("data/server/enshrouded_server.json"))
        try Data("[]".utf8).write(to: resources.appendingPathComponent("game-rules.json"))
        let executable = resources.appendingPathComponent("Lima/bin/limactl")
        try "#!/bin/sh\necho \"$1\" >> commands\nif [ \"$1\" = list ]; then echo Stopped; else exit 99; fi\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        setenv("ESM_HOME", home.path, 1); setenv("ESM_RESOURCES", resources.path, 1)
        defer {
            if let previousHome { setenv("ESM_HOME", previousHome, 1) } else { unsetenv("ESM_HOME") }
            if let previousResources { setenv("ESM_RESOURCES", previousResources, 1) } else { unsetenv("ESM_RESOURCES") }
            ApplicationLifetime.activeOperations = previousOperations
            try? FileManager.default.removeItem(at: root)
        }
        try await body(home)
    }

    @MainActor private func settled(_ model: Model) async throws {
        for _ in 0..<100 {
            if !model.polling && !model.busy { return }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTFail("Isolated model failed to settle")
    }

    @MainActor func testSettingsWindowReuseAndHostingViewSurviveManagementClose() async throws {
        try await withFixture { home in
            let model = Model(homeOverride: home)
            defer { model.retire() }
            try await settled(model)
            EditorWindows.showSettings(model)
            let window = try XCTUnwrap(NSApp.windows.first { $0.title == "Server Settings — Isolated Workflow Server" })
            defer { window.close() }
            let draftHost = try XCTUnwrap(window.contentView)
            XCTAssertNil(window.sheetParent)
            XCTAssertTrue(window.styleMask.contains(.resizable))
            EditorWindows.showSettings(model)
            XCTAssertEqual(NSApp.windows.filter { $0.isVisible && $0.title == window.title }.count, 1)
            XCTAssertTrue(window.contentView === draftHost)
            let management = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            management.isReleasedWhenClosed = false
            management.close()
            XCTAssertTrue(window.isVisible)
            XCTAssertTrue(window.contentView === draftHost, "Closing management must retain the same SwiftUI draft storage")
            window.close()
            XCTAssertNil(window.contentView)
            EditorWindows.showSettings(model)
            let reopened = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.title == window.title })
            defer { reopened.close() }
            XCTAssertFalse(reopened === window)
        }
    }

    @MainActor func testNewServerWindowReuseAndHostingViewSurviveManagementClose() async throws {
        try await withFixture { _ in
            let fleet = FleetModel()
            defer { fleet.models.forEach { $0.retire() } }
            for model in fleet.models { try await settled(model) }
            EditorWindows.showNew(fleet)
            let window = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.title == "New Enshrouded Server" })
            defer { window.close() }
            let draftHost = try XCTUnwrap(window.contentView)
            XCTAssertNil(window.sheetParent)
            EditorWindows.showNew(fleet)
            XCTAssertEqual(NSApp.windows.filter { $0.isVisible && $0.title == window.title }.count, 1)
            let management = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            management.isReleasedWhenClosed = false; management.close()
            XCTAssertTrue(window.isVisible)
            XCTAssertTrue(window.contentView === draftHost)
            window.close()
            XCTAssertNil(window.contentView)
        }
    }

    @MainActor func testOpeningManagerDoesNotStartStoppedLoginEnabledServer() async throws {
        try await withFixture { home in
            let resources = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ESM_RESOURCES"]!)
            let engine = Engine(home: home, resources: resources)
            var automation = HostingAutomation(); automation.startAtLogin = true
            try engine.saveAutomation(automation)
            let model = Model(homeOverride: home)
            defer { model.retire() }
            try await settled(model)
            XCTAssertEqual(model.state, "VM_STOPPED")
            XCTAssertFalse(model.busy)
            let commands = try String(contentsOf: home.appendingPathComponent("commands")).split(separator: "\n")
            XCTAssertFalse(commands.isEmpty)
            XCTAssertTrue(commands.allSatisfy { $0 == "list" }, "Opening the manager must only observe a manually stopped server")
        }
    }
    @MainActor func testRetiringServerClosesItsOwnedWindowsWithoutQuitNotice() async throws {
        try await withFixture { home in
            let model = Model(homeOverride: home)
            defer { model.retire() }
            try await settled(model)
            model.serverProgress = ServerOperationProgress(action: "start")
            EditorWindows.showSettings(model)
            LogsWindowController.show(model: model)
            ServerProgressWindow.show(model: model)
            let titles = ["Server Settings — " + model.name, "Server Logs — " + model.name, "Server Progress — " + model.name]
            let windows = try titles.map { title in try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.title == title }) }
            defer { windows.forEach { $0.close() } }
            EditorWindows.closeSettings(model)
            LogsWindowController.close(model)
            ServerProgressWindow.close(model)
            XCTAssertTrue(windows.allSatisfy { !$0.isVisible && $0.contentView == nil })
            let delegate = ManagerAppDelegate()
            XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
            XCTAssertNil(delegate.quitNotice)
            // Cleanup is idempotent after deletion removes the model from its fleet.
            EditorWindows.closeSettings(model)
            LogsWindowController.close(model)
            ServerProgressWindow.close(model)
        }
    }

    @MainActor func testFailedReleaseCheckCannotApplyPreviouslyCachedUpdate() async throws {
        try await withFixture { home in
            let model = Model(homeOverride: home)
            defer { model.retire() }
            try await settled(model)
            model.retire() // This test drives checks explicitly, without the polling timer.
            let script = #"""
            #!/bin/sh
            echo "$*" >> commands
            case "$1" in
              list) echo Running ;;
              shell) if [ "$5" = status ]; then echo RUNNING; else exit 99; fi ;;
              *) exit 99 ;;
            esac
            """#
            try script.write(to: model.engine.lima, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: model.engine.lima.path)
            model.state = "RUNNING"; model.playerCount = 0
            model.automation.automaticUpdates = true
            model.release = ServerRelease(installed: "100", latest: "200")
            model.releaseCheckedAt = Date()
            model.checkUpdates()
            for _ in 0..<100 {
                if !model.checkingRelease { break }
                try await Task.sleep(for: .milliseconds(30))
            }
            XCTAssertFalse(model.checkingRelease)
            XCTAssertNotNil(model.releaseError)
            XCTAssertNil(model.releaseCheckedAt)
            XCTAssertTrue(model.release?.updateAvailable == true, "Fixture must retain the previously cached newer release")
            let before = try String(contentsOf: home.appendingPathComponent("commands"))
            XCTAssertTrue(before.contains("DepotDownloader"), "The version check must actually reach and fail its fake downloader")
            model.afterRefresh()
            XCTAssertFalse(model.busy)
            XCTAssertNil(model.automation.lastAutomaticManifest)
            try await Task.sleep(for: .milliseconds(80))
            XCTAssertEqual(try String(contentsOf: home.appendingPathComponent("commands")), before)
        }
    }

    @MainActor func testCombinedCreationStartsSetupAndFailureKeepsSingleProfile() async throws {
        try await withFixture { _ in
            let fleet = FleetModel()
            defer { fleet.models.forEach { $0.retire() } }
            for model in fleet.models { try await settled(model) }
            var settings = ServerSettings()
            settings.name = "Combined Setup Test"
            settings.password = "test-player-only"
            settings.adminPassword = "test-admin-only"
            let before = try fleet.store.load().count
            XCTAssertThrowsError(try fleet.createAndSetUp(settings: settings, port: 1, world: nil, start: false))
            XCTAssertEqual(try fleet.store.load().count, before)
            let model = try fleet.createAndSetUp(settings: settings, port: 45679, world: nil, start: false)
            XCTAssertTrue(model.busy, "Creation must start installation without another form or click")
            XCTAssertNotNil(model.setupProgress)
            XCTAssertFalse(model.setupStartsServer)
            XCTAssertEqual(try fleet.store.load().count, before + 1)
            XCTAssertEqual(model.engine.hostPort, 45679)
            XCTAssertEqual(model.settings.name, settings.name)
            try await settled(model)
            XCTAssertEqual(model.setupProgress?.failed, true, "Fake installer deliberately fails; the same profile must remain retryable")
            model.setup(settings, world: nil, start: false)
            try await settled(model)
            XCTAssertEqual(try fleet.store.load().count, before + 1)
            model.operation("Different operation", work: { _ in })
            XCTAssertNil(model.setupProgress, "A later operation must not display stale setup progress")
            try await settled(model)
        }
    }

    @MainActor func testCombinedFormNativeFieldsRetainInputAndSelectionDuringRefresh() async throws {
        try await withFixture { _ in
            let fleet = FleetModel()
            defer { fleet.models.forEach { $0.retire() } }
            for model in fleet.models { try await settled(model) }
            EditorWindows.showNew(fleet)
            let window = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.title == "New Enshrouded Server" })
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(100))
            @MainActor func fields(_ view: NSView) -> [NSTextField] {
                (view as? NSTextField).map { $0.isEditable ? [$0] : [] } ?? view.subviews.flatMap(fields)
            }
            let inputs = fields(try XCTUnwrap(window.contentView))
            XCTAssertEqual(inputs.count, 4, "One combined form must provide name, two passwords and UDP port")
            XCTAssertEqual(inputs.filter { $0 is NSSecureTextField }.count, 2)
            let started = Date()
            for index in 0..<40 {
                let input = inputs[index % inputs.count]
                XCTAssertTrue(window.makeFirstResponder(input))
                let editor = try XCTUnwrap(input.currentEditor() as? NSTextView)
                editor.selectAll(nil)
                editor.insertText("fixture-\(index)", replacementRange: editor.selectedRange())
                XCTAssertEqual(input.stringValue, "fixture-\(index)")
            }
            XCTAssertLessThan(Date().timeIntervalSince(started), 1, "Rapid native focus changes must not wait 1–2 seconds per field")
            let name = try XCTUnwrap(inputs.first { $0.placeholderString == "Server name" })
            XCTAssertTrue(window.makeFirstResponder(name))
            let editor = try XCTUnwrap(name.currentEditor() as? NSTextView)
            editor.setSelectedRange(NSRange(location: 2, length: 2))
            let text = name.stringValue
            fleet.selected.objectWillChange.send()
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(name.stringValue, text)
            XCTAssertTrue(name.currentEditor() === editor)
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 2))
            XCTAssertTrue(window.makeFirstResponder(inputs[1]))
            XCTAssertEqual(name.stringValue, text)
        }
    }

}
