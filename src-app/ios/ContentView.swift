import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ptpManager: PTPManager
    @State private var masterIP = "192.168.68.114"
    @State private var selectedInterface = ""
    @State private var unicastMode = true

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Connection Settings
                GroupBox(label: Label("PTP Master", systemImage: "network")) {
                    VStack(spacing: 8) {
                        // Interface picker
                        HStack {
                            Text("Interface")
                                .fontWeight(.medium)
                                .frame(width: 80, alignment: .leading)
                            Picker("", selection: $selectedInterface) {
                                ForEach(ptpManager.availableInterfaces, id: \.name) { iface in
                                    Text(iface.label).tag(iface.name)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Mode toggle
                        Toggle(isOn: $unicastMode) {
                            Text(unicastMode ? "Unicast" : "Multicast")
                                .fontWeight(.medium)
                        }
                        .disabled(ptpManager.isRunning)

                        // Master IP (only shown in unicast mode)
                        if unicastMode {
                            HStack {
                                TextField("Master IP", text: $masterIP)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .keyboardType(.numbersAndPunctuation)
                            }
                        }

                        // Start / Stop
                        Button(ptpManager.isRunning ? "Stop" : "Start") {
                            if ptpManager.isRunning {
                                ptpManager.stop()
                            } else {
                                ptpManager.start(masterIP: masterIP,
                                                 interface: selectedInterface,
                                                 unicast: unicastMode)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ptpManager.isRunning ? .red : .green)
                        .disabled(selectedInterface.isEmpty)
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                }
                .onAppear {
                    ptpManager.refreshInterfaces()
                    if selectedInterface.isEmpty {
                        selectedInterface = ptpManager.availableInterfaces.first?.name ?? ""
                    }
                    // Apply launch arguments (-PTPInterface, -PTPMasterIP, -PTPAutoStart).
                    // This lets ptp-ios-run.sh wire up and start the session without
                    // any manual UI interaction.
                    let launch = ptpManager.parseLaunchArgs()
                    if let iface = launch.interface,
                       ptpManager.availableInterfaces.contains(where: { $0.name == iface }) {
                        selectedInterface = iface
                    }
                    if let ip = launch.masterIP {
                        masterIP = ip
                    }
                    if launch.autoStart {
                        ptpManager.start(masterIP: masterIP,
                                         interface: selectedInterface,
                                         unicast: unicastMode)
                    }
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
                    Button(action: {
                        ptpManager.logs.removeAll()
                    }) {
                        Label("Clear", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
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
            .navigationBarTitleDisplayMode(.inline)
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
