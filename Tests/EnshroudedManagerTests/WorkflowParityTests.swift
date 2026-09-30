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
            XCTAssertTrue(FileManager.default.fileExists(atPath: model.engine.home.appendingPathComponent("needs-setup").path), "Pending installation must survive reopening the manager")
            XCTAssertEqual(model.menuTitle, settings.name + " — Installation Pending")
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

    @MainActor func testStartingOneServerDoesNotBlockCreatingAnotherOrRequestingVersionCheck() async throws {
        try await withFixture { _ in
            let fleet = FleetModel()
            defer { fleet.models.forEach { $0.retire() } }
            for model in fleet.models { try await settled(model) }
            let starting = fleet.selected
            let releaseStart = DispatchSemaphore(value: 0)
            starting.operation("Starting…", action: "start", work: { _ in releaseStart.wait() })
            defer { releaseStart.signal(); starting.busy = false }
            XCTAssertTrue(fleet.canChangeProfiles)
            var settings = ServerSettings()
            settings.name = "Independent Server"
            settings.password = "test-player-only"; settings.adminPassword = "test-admin-only"
            let second = try fleet.create(settings: settings, port: 45679)
            XCTAssertFalse(second.busy)
            XCTAssertTrue(starting.busy)
            starting.checkUpdates()
            XCTAssertTrue(starting.releaseCheckQueued, "A user check must queue during startup rather than silently do nothing")
            XCTAssertFalse(starting.checkingRelease, "Do not compete with startup for the same VM")
            releaseStart.signal()
            try await settled(starting)
            starting.afterRefresh()
            XCTAssertFalse(starting.releaseCheckQueued)
            XCTAssertTrue(starting.checkingRelease, "Queued check must begin once startup completes")
            for _ in 0..<100 {
                if !starting.checkingRelease { break }
                try await Task.sleep(for: .milliseconds(30))
            }
            XCTAssertFalse(starting.checkingRelease)
            try await settled(second)
            starting.busy = true // Fleet-wide operations still protect profile mutation.
            XCTAssertFalse(fleet.canChangeProfiles)
        }
    }

    @MainActor func testPendingInstallationNeverShowsPlayerLookupInMenu() async throws {
        try await withFixture { home in
            let model = Model(homeOverride: home)
            defer { model.retire() }
            try await settled(model)
            model.state = "NOT_INSTALLED"
            XCTAssertEqual(model.label, "Installation Pending")
            XCTAssertEqual(model.peerSummary, "")
            XCTAssertEqual(model.menuTitle, model.name + " — Installation Pending")
            model.setupProgress = SetupProgress()
            model.busy = true
            model.operationTitle = "Very long installation stage message"
            XCTAssertEqual(model.menuTitle, model.name + " — Installation Pending")
            model.busy = false
            model.state = "VM_STOPPED" // Failed after creating the environment.
            model.setupProgress?.finish(success: false)
            XCTAssertEqual(model.menuTitle, model.name + " — Installation Pending")
            model.setupProgress?.finish(success: true)
            XCTAssertEqual(model.peerSummary, "0 players")
            XCTAssertEqual(model.label, "Stopped")
            model.state = "RUNNING"; model.playerCount = 2
            XCTAssertEqual(model.peerSummary, "2 players")
        }
    }

    @MainActor func testUpdateRelaunchCreatesMenuWithoutManagementWindow() async throws {
        try await withFixture { _ in
            let fleet = FleetModel()
            let delegate = ManagerAppDelegate()
            defer {
                delegate.managementWindow?.close()
                fleet.statusMenu?.invalidate(); fleet.statusMenu = nil
                fleet.models.forEach { $0.retire() }
            }
            for model in fleet.models { try await settled(model) }
            let visibleBefore = Set(NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) }.map(\.windowNumber))
            delegate.start(fleet: fleet, afterUpdate: true)
            XCTAssertNotNil(fleet.statusMenu, "The menu must not depend on management appearing")
            XCTAssertNil(delegate.managementWindow)
            XCTAssertEqual(Set(NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) }.map(\.windowNumber)), visibleBefore)
            XCTAssertTrue(delegate.fleet === fleet, "The fleet must stay alive and continue hosting without a window")
            fleet.statusMenu?.openSelectedManagement()
            let opened = try XCTUnwrap(delegate.managementWindow)
            XCTAssertTrue(opened.isVisible)
            fleet.statusMenu?.openSelectedManagement()
            XCTAssertTrue(delegate.managementWindow === opened, "Repeated menu actions reuse the same window")
            opened.close()
            XCTAssertNil(delegate.managementWindow)
            XCTAssertNil(opened.contentView)
            XCTAssertNotNil(fleet.statusMenu)
            XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
            fleet.statusMenu?.openSelectedManagement()
            XCTAssertTrue(delegate.managementWindow?.isVisible == true)
        }
    }
    @MainActor func testNormalLaunchStillOpensManagement() async throws {
        try await withFixture { _ in
            let fleet = FleetModel()
            let delegate = ManagerAppDelegate()
            defer {
                delegate.managementWindow?.close()
                fleet.statusMenu?.invalidate(); fleet.statusMenu = nil
                fleet.models.forEach { $0.retire() }
            }
            for model in fleet.models { try await settled(model) }
            delegate.start(fleet: fleet, afterUpdate: false)
            XCTAssertTrue(delegate.managementWindow?.isVisible == true)
            XCTAssertNotNil(fleet.statusMenu)
        }
    }

    @MainActor func testSetupLogOpensInstallationOutputAndRefreshes() async throws {
        try await withFixture { home in
            let model = Model(homeOverride: home)
            defer { LogsWindowController.close(model); model.retire() }
            try await settled(model)
            LogsWindowController.show(model: model)
            let previousWindow = NSApp.windows.first { $0.isVisible && $0.title == "Server Logs — " + model.name }
            model.recordActivity("Unrelated manager activity\n")
            model.resetSetupLog()
            model.setupProgress = SetupProgress(); model.busy = true
            model.recordSetupActivity("Configuring processor compatibility\n")
            await model.flushActivity()
            LogsWindowController.show(model: model)
            let window = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.title == "Server Logs — " + model.name })
            @MainActor func text(_ view: NSView) -> String {
                if let editor = view as? NSTextView, !editor.isEditable { return editor.string }
                return view.subviews.map(text).joined(separator: "\n")
            }
            @MainActor func waitFor(_ expected: String) async throws {
                for _ in 0..<60 {
                    if text(window.contentView!).contains(expected) { return }
                    try await Task.sleep(for: .milliseconds(50))
                }
                XCTFail("Installation viewer did not display " + expected)
            }
            XCTAssertNil(previousWindow?.contentView, "Reopening logs during setup must switch away from an earlier game-log view")
            try await waitFor("Configuring processor compatibility")
            XCTAssertFalse(text(window.contentView!).contains("Unrelated manager activity"))
            model.recordActivity("Setting up server failed: fixture failure\n")
            await model.flushActivity()
            try await waitFor("fixture failure")
            model.resetSetupLog(); model.recordSetupActivity("Retrying installation\n")
            await model.flushActivity()
            try await waitFor("Retrying installation")
            XCTAssertFalse(text(window.contentView!).contains("fixture failure"))
            model.busy = false
        }
    }

    @MainActor func testClearedCacheCreatesFreshServerInsteadOfReusingRetainedEnvironment() async throws {
        try await withFixture { home in
            let fleet = FleetModel()
            defer { fleet.models.forEach { $0.retire() } }
            for model in fleet.models { try await settled(model) }
            let retained = home.deletingLastPathComponent().appendingPathComponent("retained")
            try FileManager.default.createDirectory(at: retained, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: fleet.store.retainedDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(ServerProfile(id: "old", name: "Old", home: retained.path, port: 45678))
                .write(to: fleet.store.retainedDirectory.appendingPathComponent("old.json"))
            try fleet.selected.engine.clearSharedDownloads()
            var settings = ServerSettings(); settings.name = "Fresh Installation"
            settings.password = "test-only-password"; settings.adminPassword = "different-test-password"
            let model = try fleet.create(settings: settings, port: 45678)
            XCTAssertNotEqual(model.engine.home, retained)
            XCTAssertTrue(model.installationPending)
            XCTAssertTrue(FileManager.default.fileExists(atPath: retained.path))
            try await settled(model)
        }
    }

    @MainActor func testUpdateResumeKeepsIndependentMenuActionsEnabled() async throws {
        try await withFixture { home in
            let resume = home.appendingPathComponent("resume-after-manager-update")
            try Data().write(to: resume)
            let fleet = FleetModel()
            defer { fleet.statusMenu?.invalidate(); fleet.models.forEach { $0.retire() } }
            let starting = fleet.selected
            // Exercise the actual post-update branch before its asynchronous work runs.
            starting.polling = false; starting.state = "VM_STOPPED"
            starting.afterRefresh()
            XCTAssertTrue(starting.busy)
            XCTAssertEqual(starting.activeAction, "start")
            XCTAssertNotNil(starting.serverProgress)
            XCTAssertTrue(fleet.canChangeProfiles)
            XCTAssertTrue(starting.canRequestReleaseCheck)
            var managementOpened = false
            let status = StatusMenu(fleet: fleet) { managementOpened = true }
            fleet.statusMenu = status
            status.menuNeedsUpdate(status.menu)
            let menu = status.menu
            for title in ["New Server…", "Check for Manager Updates", "Open Manager at Login", "Automatically Update All Enshrouded Servers"] {
                XCTAssertEqual(menu.item(withTitle: title)?.isEnabled, true, title)
            }
            let server = try XCTUnwrap(menu.items.first { $0.submenu != nil }?.submenu)
            for title in ["Server Management…", "Show Progress…"] {
                XCTAssertEqual(server.item(withTitle: title)?.isEnabled, true, title)
            }
            let manage = try XCTUnwrap(server.item(withTitle: "Server Management…"))
            XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(manage.action), to: manage.target, from: manage))
            XCTAssertTrue(managementOpened)
            let check = try XCTUnwrap(menu.items.compactMap { $0.view?.subviews.first as? NSButton }.first)
            XCTAssertTrue(check.isEnabled)
            check.performClick(nil)
            XCTAssertTrue(starting.releaseCheckQueued)
            for title in ["Uninstall Server Files…", "Clear Installation Downloads…", "Quit Manager (Servers Keep Running)"] {
                XCTAssertEqual(menu.item(withTitle: title)?.isEnabled, false, title)
            }
            XCTAssertFalse(NSApp.windows.contains { $0.isVisible && $0.title == "Server Progress — " + starting.name }, "Automatic resume must remain quiet")
            try await settled(starting)
            XCTAssertTrue(FileManager.default.fileExists(atPath: resume.path), "A failed restart retains the retry marker")
        }
    }

}
