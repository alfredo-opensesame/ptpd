import Foundation
import Combine

struct LogEntry: Identifiable {
    let id = UUID()
    let message: String
    let level: Int32
}

class PTPManager: ObservableObject {
    @Published var isRunning = false
    @Published var state = "STOPPED"
    @Published var offset = "--"
    @Published var delay = "--"
    @Published var drift = "--"
    @Published var logs: [LogEntry] = []
    
    private var ptpThread: Thread?
    private var ptpBridge: PTPBridge?
    
    init() {
        // Set up log callback
        PTPBridge.setLogCallback { [weak self] message, level in
            DispatchQueue.main.async {
                self?.logs.append(LogEntry(message: message, level: level))
                // Keep only last 100 log entries
                if let count = self?.logs.count, count > 100 {
                    self?.logs.removeFirst(count - 100)
                }
            }
        }
    }
    
    func start(masterIP: String) {
        guard !isRunning else { return }
        
        ptpBridge = PTPBridge(masterIP: masterIP)
        
        ptpThread = Thread { [weak self] in
            guard let bridge = self?.ptpBridge else { return }
            
            DispatchQueue.main.async {
                self?.isRunning = true
                self?.state = "STARTING"
                self?.logs.append(LogEntry(message: "Starting PTP client...", level: 1))
            }
            
            // Run ptpd (blocking call)
            bridge.run()
            
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.state = "STOPPED"
                self?.logs.append(LogEntry(message: "PTP client stopped", level: 1))
            }
        }
        
        ptpThread?.start()
        
        // Start status update timer
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self, self.isRunning else {
                timer.invalidate()
                return
            }
            self.updateStatus()
        }
    }
    
    func stop() {
        guard isRunning else { return }
        ptpBridge?.stop()
        isRunning = false
        state = "STOPPED"
        offset = "--"
        delay = "--"
        drift = "--"
    }
    
    private func updateStatus() {
        guard let bridge = ptpBridge else { return }
        
        let status = bridge.getStatus()
        // Convert C char array to Swift String
        state = String(cString: withUnsafePointer(to: status.state) { $0.withMemoryRebound(to: CChar.self, capacity: 32) { $0 } })
        // Convert nanoseconds to milliseconds
        offset = String(format: "%.3f ms", Double(status.offset) / 1_000_000.0)
        delay = String(format: "%.3f ms", Double(status.delay) / 1_000_000.0)
        drift = String(format: "%.1f ppm", status.drift)
    }
}
