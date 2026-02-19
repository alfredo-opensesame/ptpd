import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ptpManager: PTPManager
    @State private var masterIP = "192.168.1.100"
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Connection Settings
                GroupBox(label: Label("PTP Master", systemImage: "network")) {
                    HStack {
                        TextField("Master IP", text: $masterIP)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        Button(ptpManager.isRunning ? "Stop" : "Start") {
                            if ptpManager.isRunning {
                                ptpManager.stop()
                            } else {
                                ptpManager.start(masterIP: masterIP)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ptpManager.isRunning ? .red : .green)
                    }
                    .padding()
                }
                
                // Status Display
                GroupBox(label: Label("PTP Status", systemImage: "clock")) {
                    VStack(alignment: .leading, spacing: 10) {
                        StatusRow(title: "State", value: ptpManager.state)
                        StatusRow(title: "Offset", value: ptpManager.offset)
                        StatusRow(title: "Delay", value: ptpManager.delay)
                        StatusRow(title: "Drift", value: ptpManager.drift)
                    }
                    .padding()
                }
                
                // Log Display
                GroupBox(label: HStack {
                    Label("Logs", systemImage: "text.alignleft")
                    Spacer()
                    Button(action: {
                        let logText = ptpManager.logs.map { $0.message }.joined(separator: "\n")
                        UIPasteboard.general.string = logText
                    }) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(ptpManager.logs.isEmpty)
                }) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(ptpManager.logs) { log in
                                    Text(log.message)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(log.level == 0 ? .red : .primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(log.id)
                                }
                            }
                            .padding(8)
                        }
                        .frame(height: 200)
                        .onChange(of: ptpManager.logs.count) { _ in
                            if let lastLog = ptpManager.logs.last {
                                withAnimation {
                                    proxy.scrollTo(lastLog.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("PTP Monitor")
        }
    }
}

struct StatusRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .fontWeight(.medium)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(PTPManager())
    }
}
