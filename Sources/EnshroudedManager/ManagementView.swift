import SwiftUI
import Charts
import EnshroudedCore

struct ManagementView: View {
    @ObservedObject var model: Model
    @State private var setupOpen = false
    var removeServer: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Text("●").font(.system(size: 17)).foregroundStyle(model.busy ? .orange : model.state == "RUNNING" ? .green : .red)
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(model.name) — \(model.label)")
                    Text(model.peerSummary).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.horizontal, 8).padding(.top, 8)
            HStack {
                Text("Enshrouded Manager · \(model.build.label)").font(.system(size: 11)).foregroundStyle(.secondary).help(model.build.detail)
                Spacer()
            }.padding(.horizontal, 8)
            if model.busy {
                HStack { ProgressView().controlSize(.small); VStack(alignment: .leading) { Text(model.operationTitle).font(.headline); Text("Keep the manager open until this operation finishes.").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Show Progress") { ServerProgressWindow.show(model: model) } }.padding(12).background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            }
            if model.state == "NOT_INSTALLED" {
                GroupBox("Set up your Enshrouded server") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Setup downloads the server and its compatibility environment. Keep 30 GB free for installation and updates; this is not the download size.")
                        Button("Set Up Server") { setupOpen = true }.disabled(model.busy)
                    }.padding(8)
                }
            }
            if let error = model.error {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(error).font(.caption).textSelection(.enabled).lineLimit(4)
                    Spacer(); Button("Dismiss") { model.error = nil }
                }.padding(10).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            NativeTabs(pages: [
                ("Performance", AnyView(PerformanceView(model: model))),
                ("Automation", AnyView(AutomationView(model: model))),
                ("Moderation", AnyView(PlayersView(model: model))),
                ("Backups", AnyView(BackupsView(model: model)))
            ])
            HStack(spacing: 6) {
                Button(model.busy ? model.operationTitle : ["RUNNING", "RECOVERING"].contains(model.state) ? "Stop Server" : "Start Server") { model.run(["RUNNING", "RECOVERING"].contains(model.state) ? "stop" : "start") }
                    .disabled(model.busy || (!["RUNNING", "RECOVERING"].contains(model.state) && !model.canEdit))
                Button("Server Settings") { EditorWindows.showSettings(model) }.disabled(!["RUNNING", "RECOVERING", "INSTALLED", "VM_STOPPED"].contains(model.state))
                Button("Open Log") { LogsWindowController.show(model: model) }
                Button("Logs Folder") { NSWorkspace.shared.open(model.engine.serverLogFolder) }
                Button("Open Server Folder") { NSWorkspace.shared.open(model.engine.data.appendingPathComponent("server")) }
            }.font(.system(size: 11)).controlSize(.small)
            HStack {
                Text(model.busy ? model.operationTitle : model.automationMessage).lineLimit(1)
                Spacer()
                Button("Delete Server…", action: removeServer).disabled(model.busy)
                if let check = model.lastCheck { Text("Checked \(check, style: .time)") }
            }.font(.system(size: 11)).foregroundStyle(.secondary).frame(height: 16)
        }.padding(16).frame(width: 640, height: 860)
        .background(ManagementWindowTitle(name: model.name))
        .sheet(isPresented: $setupOpen) { SetupView(model: model, draft: model.settings) }
        .confirmationDialog("Update or repair the Enshrouded server?", isPresented: $model.showMaintenance, titleVisibility: .visible) {
            Button("Update Enshrouded Server") { model.run("update") }
        } message: { Text("Running servers must be empty. The manager saves and stops, backs up the world and configuration, then downloads and validates the latest files from Valve. A previously running server restarts; a stopped server stays stopped.") }
        .confirmationDialog("Save and restart this server?", isPresented: $model.showRestart, titleVisibility: .visible) {
            Button("Save & Restart") { model.run("restart") }
        } message: { Text("The server must be empty because in-game restart warnings are unavailable. The manager saves, stops and starts it again.") }
    }
}

struct MetricGraph: View {
    let title: String
    let subtitle: String
    let points: [PerformancePoint]
    let color: Color
    var fillsAvailableSpace = false
    var maximumGap: TimeInterval = 45
    var reportIntervals = false
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                if points.isEmpty {
                    Text("Readings appear while the server is running.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: fillsAvailableSpace ? 0 : 175, maxHeight: fillsAvailableSpace ? .infinity : 175)
                } else {
                    Chart(PerformanceHistory.chartPoints(points, maximumGap: maximumGap)) { point in
                        if reportIntervals {
                            // Each report describes the preceding minute, not a
                            // live sample. Show its measured interval without
                            // joining across unreported periods.
                            RuleMark(xStart: .value("From", point.date.addingTimeInterval(-60)), xEnd: .value("To", point.date), y: .value(title, point.value)).foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 3))
                        } else {
                        LineMark(x: .value("Time", point.date), y: .value(title, point.value), series: .value("Session", point.segment)).foregroundStyle(color)
                        }
                        PointMark(x: .value("Time", point.date), y: .value(title, point.value)).symbolSize(reportIntervals ? 18 : 8).foregroundStyle(color)
                    }.chartXScale(domain: Date().addingTimeInterval(-PerformanceHistory.duration)...Date()).chartYScale(domain: .automatic(includesZero: true))
                        .chartXAxis { AxisMarks(values: (0...3).map { Date().addingTimeInterval(-Double(3 - $0) * 3600) }) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour().minute()) } }
                        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { _ in AxisGridLine(); AxisValueLabel() } }
                        .frame(minHeight: 0, maxHeight: fillsAvailableSpace ? .infinity : 175)
                }
            }.padding(6).frame(maxWidth: .infinity, maxHeight: fillsAvailableSpace ? .infinity : nil, alignment: .leading)
        }.frame(maxHeight: fillsAvailableSpace ? .infinity : nil)
    }
}
struct PerformanceView: View {
    @ObservedObject var model: Model
    var selected = "Server"
    var nested = true
    var body: some View {
        if nested {
            NativeTabs(pages: [("Server", AnyView(PerformanceView(model: model, selected: "Server", nested: false))), ("Ping", AnyView(PerformanceView(model: model, selected: "Ping", nested: false)))])
        } else if selected == "Server" {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 28) {
                    stat("UPTIME", model.metrics.map { Duration.seconds($0.uptimeSeconds).formatted(.time(pattern: .hourMinuteSecond)) } ?? "—")
                    stat("MEMORY USED", model.metrics.map { String(format: "%.2f GB", $0.memoryBytes / 1_073_741_824) } ?? "—")
                    stat("LAST SAVE", model.snapshot.lastSaveCompleted ? "Completed in log" : "No completion in recent log")
                }.padding(.vertical, 4).layoutPriority(1)
                MetricGraph(title: "Server Speed (updates per second)", subtitle: model.speedSummary, points: model.updateHistory, color: .blue, fillsAvailableSpace: true, maximumGap: ServerSpeedHistory.freshness, reportIntervals: true)
                    .help("Simulation speed, not graphics FPS. Each bar represents a reported one-minute average. Enshrouded can skip reports for several minutes; gaps mean no measurement was provided. The report age updates every second.")
                MetricGraph(title: "Server Memory (GB)", subtitle: "Memory used to run this server · 5-second averages", points: model.memoryHistory, color: .blue, fillsAvailableSpace: true, maximumGap: 7.5)
                Text("Last 3 hours · memory: 5-second averages. Speed: game reports, which may be several minutes apart.").font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.visiblePingIDs.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "network").font(.largeTitle).foregroundStyle(.secondary)
                            Text(model.playerCount == 0 || model.stopped ? "No players connected" : "No current latency report").font(.headline)
                            Text("Readings appear when Enshrouded reports an active connection.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity, minHeight: 380)
                    }
                    ForEach(model.visiblePingIDs, id: \.self) { id in
                        MetricGraph(title: "Connection \(id)", subtitle: "Milliseconds · reported by Enshrouded, about every 30 seconds", points: model.pingHistory[id] ?? [], color: .blue)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption2).foregroundStyle(.secondary); Text(value).font(.subheadline.bold()) }
    }
}
struct PlayersView: View {
    @ObservedObject var model: Model
    @State private var accessOpen = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reported Connections").font(.headline)
            if model.state == "RUNNING", let observed = model.lastPeers, Date().timeIntervalSince(observed) < 90 {
                Text("Latest session report observed \(observed, style: .time)").font(.caption).foregroundStyle(.secondary)
                ForEach(model.snapshot.peers) { peer in
                    HStack { Label("Connection \(peer.id)", systemImage: "person.crop.circle"); Spacer(); Text("\(Int(peer.ping)) ms"); Text("\(peer.lost) reported lost packets").foregroundStyle(.secondary) }.padding(10)
                }
                if model.snapshot.peers.isEmpty { Text("No remote connections in the latest report.") }
            } else { Text("No current connection report.").foregroundStyle(.secondary) }
            Divider()
            HStack { Text("Enshrouded Player Permissions").font(.headline); Spacer(); Button("Roles & Saved Bans…") { accessOpen = true }.disabled(model.busy || model.state == "NOT_INSTALLED") }
            Text("Players receive the permissions of the password they use. Share the Friend password for normal play; keep the Admin password private. Existing custom roles and bans are preserved when settings change.")
            Text("To kick or ban a player, join with the admin password and open Enshrouded’s Social tab.").foregroundStyle(.secondary)
            Spacer()
        }.padding(20).sheet(isPresented: $accessOpen) { AccessSettingsView(model: model) }
    }
}
