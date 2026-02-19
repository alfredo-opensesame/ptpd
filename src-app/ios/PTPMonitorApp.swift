import SwiftUI

@main
struct PTPMonitorApp: App {
    @StateObject private var ptpManager = PTPManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ptpManager)
        }
    }
}
