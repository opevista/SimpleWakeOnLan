import SwiftUI
import Network
import SwiftyPing

// MARK: - Models

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

// MARK: - Add Device View

struct AddDeviceView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var devices: [Device]

    @State private var name = ""
    @State private var macAddress = ""
    @State private var broadcastAddress = ""
    @State private var port = "9"
    @State private var ipAddress = ""

    var body: some View {
        Form {
            Section("Device") {
                TextField("Name", text: $name)
                TextField("MAC Address", text: $macAddress)
                    .font(.system(.body, design: .monospaced))
                TextField("IP Address", text: $ipAddress)
            }

            Section("Network") {
                TextField("Broadcast Address (e.g. 192.168.1.255)", text: $broadcastAddress)
                TextField("WoL Port", text: $port)
                    .keyboardType(.numberPad)
            }
        }
        .navigationTitle("New Device")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    devices.append(
                        Device(
                            name: name,
                            macAddress: macAddress,
                            broadcastAddress: broadcastAddress,
                            port: port,
                            ipAddress: ipAddress
                        )
                    )
                    dismiss()
                }
                .disabled(
                    name.isEmpty ||
                    macAddress.isEmpty ||
                    ipAddress.isEmpty ||
                    broadcastAddress.isEmpty
                )
            }
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @State private var devices: [Device] = []
    @State private var showingAddDeviceSheet = false
    @State private var statusMessage = "Ready"
    @State private var activePingers: [Device.ID: SwiftyPing] = [:]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    ForEach(devices) { device in
                        NavigationLink(value: device.id) {
                            DeviceRowView(device: device)
                        }
                    }
                    .onDelete(perform: deleteDevice)
                }
                .listStyle(.plain)

                Text(statusMessage)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddDeviceSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: Device.ID.self) { id in
                if let binding = binding(for: id) {
                    DetailView(
                        device: binding,
                        onCheck: checkDeviceStatus,
                        onWake: sendWakeOnLan
                    )
                }
            }
        }
        .sheet(isPresented: $showingAddDeviceSheet) {
            NavigationStack {
                AddDeviceView(devices: $devices)
            }
        }
        .onAppear(perform: loadDevices)
        .onChange(of: devices) { saveDevices() }
    }

    private func binding(for id: Device.ID) -> Binding<Device>? {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return nil }
        return $devices[index]
    }
}

// MARK: - Persistence

extension ContentView {
    func loadDevices() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: "savedDevices"),
           let decoded = try? decoder.decode([Device].self, from: data) {
            devices = decoded
            statusMessage = "\(decoded.count) device(s) loaded"
        }
    }

    func saveDevices() {
        if let encoded = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(encoded, forKey: "savedDevices")
        }
    }

    func deleteDevice(at offsets: IndexSet) {
        devices.remove(atOffsets: offsets)
        statusMessage = "Device removed"
    }
}

// MARK: - Wake on LAN（iOS 実機対応版）

extension ContentView {
    func sendWakeOnLan(for device: Device) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }),
              let port = NWEndpoint.Port(device.port) else { return }

        devices[index].logs.append(
            LogEntry(message: "WoL start")
        )

        let mac = device.macAddress
            .split(separator: ":")
            .compactMap { UInt8($0, radix: 16) }

        guard mac.count == 6 else {
            devices[index].logs.append(
                LogEntry(message: "Invalid MAC address")
            )
            return
        }

        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: mac) }

        let connection = NWConnection(
            host: .init(device.broadcastAddress),
            port: port,
            using: .udp
        )

        connection.stateUpdateHandler = { state in
            DispatchQueue.main.async {
                devices[index].logs.append(
                    LogEntry(message: "NWConnection state: \(state)")
                )
            }

            if case .ready = state {
                connection.send(content: packet, completion: .contentProcessed { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            devices[index].logs.append(
                                LogEntry(message: "Send error: \(error.localizedDescription)")
                            )
                        } else {
                            devices[index].logs.append(
                                LogEntry(message: "WoL packet sent successfully")
                            )
                            statusMessage = "Magic packet sent to \(device.name)"
                        }
                    }
                    connection.cancel()
                })
            }
        }

        connection.start(queue: .main)
    }
}

// MARK: - Ping

extension ContentView {
    func checkDeviceStatus(for device: Device) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }

        do {
            let pinger = try SwiftyPing(
                host: device.ipAddress,
                configuration: .init(interval: 0.8, with: 3),
                queue: .global()
            )

            activePingers[device.id] = pinger
            var received = false

            pinger.observer = { response in
                if response.error == nil {
                    received = true
                }
            }

            pinger.finished = { _ in
                DispatchQueue.main.async {
                    self.devices[index].status = received ? .online : .offline
                    self.devices[index].logs.append(
                        LogEntry(message: "Ping result: \(received ? "online" : "offline")")
                    )
                    self.activePingers.removeValue(forKey: device.id)
                }
            }

            try pinger.startPinging()
        } catch {
            devices[index].logs.append(
                LogEntry(message: "Ping error: \(error.localizedDescription)")
            )
        }
    }
}

// MARK: - Views

struct DeviceRowView: View {
    let device: Device

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading) {
                Text(device.name).font(.headline)
                Text(device.ipAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var color: Color {
        switch device.status {
        case .online: return .green
        case .offline: return .red
        case .unknown: return .gray
        }
    }
}

struct DetailView: View {
    @Binding var device: Device
    let onCheck: (Device) -> Void
    let onWake: (Device) -> Void

    var body: some View {
        Form {
            Section("Device") {
                TextField("Name", text: $device.name)
                TextField("IP Address", text: $device.ipAddress)
                TextField("MAC Address", text: $device.macAddress)
                TextField("Broadcast Address", text: $device.broadcastAddress)
                TextField("WoL Port", text: $device.port)
            }

            Section("Logs") {
                ForEach(device.logs.sorted { $0.timestamp > $1.timestamp }) { log in
                    Text(log.message)
                        .font(.footnote.monospaced())
                }
            }
        }
        .navigationTitle(device.name)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Check") { onCheck(device) }
                Spacer()
                Button("Wake") { onWake(device) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview {
    ContentView()
}
