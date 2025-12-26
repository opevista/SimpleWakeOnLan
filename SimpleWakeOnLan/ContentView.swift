import SwiftUI
import Network
import SwiftyPing

// 1. Data Model for a Device
enum DeviceStatus: String, Codable {
    case unknown
    case online
    case offline
}

struct LogEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var timestamp: Date = Date()
    var message: String
}

struct Device: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var macAddress: String
    var broadcastAddress: String
    var port: String
    var ipAddress: String
    var status: DeviceStatus = .unknown
    var logs: [LogEntry] = []
}

// 2. View for adding a new device
struct AddDeviceView: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var devices: [Device]
    
    @State private var name: String = ""
    @State private var macAddress: String = ""
    @State private var broadcastAddress: String = "255.255.255.255"
    @State private var port: String = "9"
    @State private var ipAddress: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            GroupBox(label: Text("Device")) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    TextField("MAC Address (AA:BB:CC:DD:EE:FF)", text: $macAddress)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    
                    TextField("IP Address", text: $ipAddress)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(8)
            }
            .glassEffect()

            GroupBox(label: Text("Network")) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Broadcast Address", text: $broadcastAddress)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Text("WoL Port")
                        Spacer()
                        TextField("", text: $port)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }
                .padding(8)
            }
            .glassEffect()

            Spacer()
        }
        .padding(20)
        .navigationTitle("New Device")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let newDevice = Device(
                        name: name,
                        macAddress: macAddress,
                        broadcastAddress: broadcastAddress,
                        port: port,
                        ipAddress: ipAddress
                    )
                    devices.append(newDevice)
                    presentationMode.wrappedValue.dismiss()
                }
                .disabled(name.isEmpty || macAddress.isEmpty || ipAddress.isEmpty)
            }
        }
        .frame(minWidth: 360, minHeight: 320)
    }
}

// 3. Main Content View
struct ContentView: View {
    @State private var devices: [Device] = []
    @State private var showingAddDeviceSheet = false
    @State private var statusMessage: String = "Ready"
    @State private var activePingers: [Device.ID: SwiftyPing] = [:]

    var body: some View {
        NavigationView {
            VStack {
                List {
                    ForEach(devices) { device in
                        NavigationLink(destination: DetailView(
                            device: self.binding(for: device.id),
                            onCheck: { self.checkDeviceStatus(for: $0) },
                            onWake: { self.sendWakeOnLan(for: $0) }
                        )) {
                            DeviceRowView(device: device)
                        }
                    }
                    .onDelete(perform: deleteDevice)
                }
                .listStyle(SidebarListStyle())
                .navigationTitle("Devices")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            showingAddDeviceSheet = true
                        }) {
                            Label("Add Device", systemImage: "plus")
                        }
                    }
                }
                
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)

            }
            .frame(minWidth: 250)

            // Placeholder for the detail view
            Text("Select a device to view details.")
                .font(.largeTitle)
                .foregroundColor(.secondary)
        }
        .onAppear(perform: loadDevices)
        .onChange(of: devices) { _ in
            saveDevices()
        }
        .sheet(isPresented: $showingAddDeviceSheet) {
            AddDeviceView(devices: $devices)
        }
        .frame(minWidth: 800, minHeight: 400)
    }

    private func binding(for deviceId: Device.ID) -> Binding<Device> {
        guard let index = devices.firstIndex(where: { $0.id == deviceId }) else {
            fatalError("Cannot find device with ID \(deviceId)")
        }
        return $devices[index]
    }

    // --- Data Persistence ---
    func loadDevices() {
        // Make sure decoding logs doesn't fail for older saved data
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: "savedDevices") {
            if let decodedDevices = try? decoder.decode([Device].self, from: data) {
                self.devices = decodedDevices
                statusMessage = "\(decodedDevices.count) device(s) loaded."
                return
            }
        }
        self.devices = []
        statusMessage = "No devices found. Add a new one."
    }

    func saveDevices() {
        if let encoded = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(encoded, forKey: "savedDevices")
        }
    }
    
    func deleteDevice(at offsets: IndexSet) {
        devices.remove(atOffsets: offsets)
        saveDevices()
        statusMessage = "Device removed."
    }

    // --- WOL Logic ---
    func sendWakeOnLan(for device: Device) {
        guard let deviceIndex = devices.firstIndex(where: { $0.id == device.id }) else { return }

        let macBytes = device.macAddress.split(separator: ":").compactMap { UInt8($0, radix: 16) }

        guard macBytes.count == 6 else {
            let message = "Error: Invalid MAC address format."
            devices[deviceIndex].logs.append(LogEntry(message: message))
            statusMessage = message
            return
        }

        var magicPacket = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            magicPacket.append(contentsOf: macBytes)
        }

        guard let portValue = NWEndpoint.Port(device.port) else {
            let message = "Error: Invalid Port."
            devices[deviceIndex].logs.append(LogEntry(message: message))
            statusMessage = message
            return
        }
        
        let host = NWEndpoint.Host(device.broadcastAddress)
        let parameters = NWParameters.udp
        let connection = NWConnection(host: host, port: portValue, using: parameters)

        connection.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                connection.send(content: magicPacket, completion: .contentProcessed { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            let message = "Error sending WoL packet: \(error.localizedDescription)"
                            self.devices[deviceIndex].logs.append(LogEntry(message: message))
                            self.statusMessage = message
                        } else {
                            let message = "Magic packet sent successfully."
                            self.devices[deviceIndex].logs.append(LogEntry(message: message))
                            self.statusMessage = "Magic packet sent to \(device.name)!"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                self.checkDeviceStatus(for: device)
                            }
                        }
                    }
                    connection.cancel()
                })
            case .failed(let error):
                DispatchQueue.main.async {
                    let message = "WoL connection failed: \(error.localizedDescription)"
                    self.devices[deviceIndex].logs.append(LogEntry(message: message))
                    self.statusMessage = message
                }
                connection.cancel()
            default:
                break
            }
        }
        
        DispatchQueue.main.async {
            let message = "Sending WoL packet..."
            self.devices[deviceIndex].logs.append(LogEntry(message: message))
            self.statusMessage = message
        }
        connection.start(queue: .main)
    }

    // --- Status Checking ---
    static func statusColor(for status: DeviceStatus) -> Color {
        switch status {
        case .online:
            return .green
        case .offline:
            return .red
        case .unknown:
            return .gray
        }
    }

    private func checkDeviceStatus(for device: Device) {
        guard let deviceIndex = devices.firstIndex(where: { $0.id == device.id }) else { return }

        // Cancel any existing ping for this device
        if let existingPinger = activePingers[device.id] {
            existingPinger.stopPinging()
        }

        devices[deviceIndex].status = .unknown
        devices[deviceIndex].logs.append(LogEntry(message: "Pinging \(device.ipAddress)..."))
        self.statusMessage = "Pinging \(device.name)..."

        do {
            let pinger = try SwiftyPing(
                host: device.ipAddress,
                configuration: PingConfiguration(interval: 0.8, with: 3),
                queue: DispatchQueue.global()
            )

            activePingers[device.id] = pinger
            var roundtripTimes: [Double] = []
            var lastError: PingError?

            pinger.observer = { response in
                if let error = response.error {
                    lastError = error
                } else {
                    roundtripTimes.append(response.duration)
                }
            }
            
            pinger.finished = { result in
                 DispatchQueue.main.async {
                    self.activePingers.removeValue(forKey: device.id)
                    guard let deviceIndex = self.devices.firstIndex(where: { $0.id == device.id }) else { return }

                    if result.packetsReceived > 0, !roundtripTimes.isEmpty {
                        let avgRTT = roundtripTimes.reduce(0, +) / Double(roundtripTimes.count)
                        let message = "Online (\(result.packetsReceived)/\(result.packetsTransmitted) packets, avg RTT: \(String(format: "%.2f", avgRTT * 1000)) ms)"
                        self.devices[deviceIndex].status = .online
                        self.devices[deviceIndex].logs.append(LogEntry(message: message))
                        self.statusMessage = "\(device.name) is online."
                    } else {
                        var message = "Offline (\(result.packetsReceived)/\(result.packetsTransmitted) packets received)."
                        if let error = lastError {
                             message += " (\(error.localizedDescription))"
                        }
                        self.devices[deviceIndex].status = .offline
                        self.devices[deviceIndex].logs.append(LogEntry(message: message))
                        self.statusMessage = "\(device.name) appears to be offline."
                    }
                }
            }

            try pinger.startPinging()

        } catch {
            DispatchQueue.main.async {
                self.activePingers.removeValue(forKey: device.id)
                guard let deviceIndex = self.devices.firstIndex(where: { $0.id == device.id }) else { return }
                let message = "Ping setup failed: \(error.localizedDescription)"
                self.devices[deviceIndex].status = .offline
                self.devices[deviceIndex].logs.append(LogEntry(message: message))
                self.statusMessage = message
            }
        }
    }
}

// 4. Detail and Row Views

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

struct DeviceRowView: View {
    let device: Device

    var body: some View {
        HStack {
            Circle()
                .frame(width: 10, height: 10)
                .foregroundColor(ContentView.statusColor(for: device.status))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.headline)
                Text(device.ipAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct DetailView: View {
    @Binding var device: Device
    
    var onCheck: (Device) -> Void
    var onWake: (Device) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Form {
                Section(header: Text("Device Details").font(.headline)) {
                    TextField("Name", text: $device.name)
                    TextField("IP Address", text: $device.ipAddress)
                    TextField("MAC Address", text: $device.macAddress)
                    TextField("Broadcast Address", text: $device.broadcastAddress)
                    TextField("WoL Port", text: $device.port)
                }
            }
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding()
            .glassEffect()
            
            Divider()
            
            VStack(alignment: .leading) {
                Text("Logs")
                    .font(.headline)
                    .padding(.horizontal)
                
                List {
                    ForEach(device.logs.sorted(by: { $0.timestamp > $1.timestamp })) { log in
                        Text("[\(log.timestamp, formatter: itemFormatter)] \(log.message)")
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .glassEffect()
            }
            .padding([.horizontal, .bottom])

            HStack {
                Spacer()
                Button { onCheck(device) } label: { Label("Check Status", systemImage: "arrow.clockwise") }
                Button { onWake(device) } label: { Label("Wake", systemImage: "power") }.buttonStyle(.borderedProminent)
            }
            .padding([.horizontal, .bottom])
        }
        .navigationTitle(device.name)
        .frame(minWidth: 400)
    }
}

// MARK: - Glass Effect Modifier

struct GlassEffect: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 12.0, *) {
            content.background(.regularMaterial)
        } else {
            // Fallback for older macOS versions
            content.background(Color.secondary.opacity(0.25))
        }
    }
}

extension View {
    func glassEffect() -> some View {
        self.modifier(GlassEffect())
    }
}

#Preview {
    ContentView()
}
