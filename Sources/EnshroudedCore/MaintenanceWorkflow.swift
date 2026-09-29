import Foundation

public enum MaintenanceWorkflow {
    public static func run(action: String, initialState: String, empty: () throws -> Bool, execute: (String) throws -> Void, output: (String) -> Void) throws {
        guard action == "update" || action == "restart", initialState != "NOT_INSTALLED" else { throw EngineError("Install the server first") }
        let running = initialState == "RUNNING"
        guard running || action != "restart" else { throw EngineError("Start the server before requesting a restart") }
        if running {
            guard try empty() else { throw EngineError("Players are connected. Maintenance waits until the server is empty because player warnings are unavailable.") }
            output("Saving and stopping server…\n"); try execute("stop")
        }
        if action == "update" { output("Backing up and updating server…\n"); try execute("install") }
        if running { output("Starting server…\n"); try execute("start") }
        else if initialState == "VM_STOPPED" { try execute("shutdown") }
    }
}
