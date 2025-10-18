import Combine
import CoreWLAN
import Darwin
import Foundation
import Network

struct NetworkSummary: Equatable {
    enum InterfaceKind: String {
        case wifi
        case wired
        case other
    }

    var isConnected: Bool
    var interface: InterfaceKind?
    var ssid: String?
    var localAddress: String?
    var description: String {
        guard isConnected else { return "Offline" }
        switch interface {
        case .wifi:
            if let ssid {
                return "Wi‑Fi · \(ssid)"
            }
            return "Wi‑Fi connected"
        case .wired:
            return "Ethernet connected"
        case .other, .none:
            return "Network connected"
        }
    }

    static let disconnected = NetworkSummary(isConnected: false, interface: nil, ssid: nil, localAddress: nil)
}

final class NetworkMonitor: ObservableObject {
    @Published private(set) var summary: NetworkSummary = .disconnected

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.clipboard.sync.network")

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let summary = self.buildSummary(for: path)
            DispatchQueue.main.async {
                self.summary = summary
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }

    private func buildSummary(for path: NWPath) -> NetworkSummary {
        guard path.status == .satisfied else {
            return .disconnected
        }

        let interfaceKind: NetworkSummary.InterfaceKind
        if path.usesInterfaceType(.wifi) {
            interfaceKind = .wifi
        } else if path.usesInterfaceType(.wiredEthernet) {
            interfaceKind = .wired
        } else {
            interfaceKind = .other
        }

        let ssid: String?
        if interfaceKind == .wifi {
            ssid = CWWiFiClient.shared().interface()?.ssid()
        } else {
            ssid = nil
        }

        let address = currentIPAddress(preferWiFi: interfaceKind == .wifi)

        return NetworkSummary(
            isConnected: true,
            interface: interfaceKind,
            ssid: ssid,
            localAddress: address
        )
    }

    private func currentIPAddress(preferWiFi: Bool) -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }

        var wifiCandidate: String?
        var ethernetCandidate: String?

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            guard addrFamily == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: hostname)

            if name == "en0" {
                wifiCandidate = ip
            } else if name.hasPrefix("en") {
                ethernetCandidate = ip
            } else if address == nil {
                address = ip
            }
        }

        if preferWiFi, let wifiCandidate {
            return wifiCandidate
        }
        if let ethernetCandidate {
            return ethernetCandidate
        }
        return address
    }
}
