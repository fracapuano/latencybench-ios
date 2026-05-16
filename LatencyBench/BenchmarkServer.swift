import Darwin
import Foundation
import Network
import SwiftUI
import UIKit

struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data
}

final class BenchmarkServer: ObservableObject {
    @Published var status: String = "Stopped"
    @Published var displayURL: String = "Starting..."
    @Published var lastResult: String = "No requests yet."

    private let port: UInt16
    private var listener: NWListener?
    private let benchmarker = ModelBenchmarker()

    init(port: UInt16) {
        self.port = port
        self.displayURL = "http://\(Self.wifiAddress() ?? "IPHONE_IP"):\(port)"
    }

    func start() {
        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.status = "Listening on port \(self?.port ?? 0)"
                        self?.displayURL = "http://\(Self.wifiAddress() ?? "IPHONE_IP"):\(self?.port ?? 0)"
                    case .failed(let error):
                        self?.status = "Server failed: \(error)"
                    default:
                        break
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            status = "Could not start server: \(error)"
        }
    }

    private func handle(connection: NWConnection) {
        var buffer = Data()
        func receiveMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let data {
                    buffer.append(data)
                }
                if let request = Self.parseRequest(buffer) {
                    self.respond(to: request, on: connection)
                    return
                }
                if isComplete || error != nil {
                    self.sendJSON(["error": "Incomplete request"], status: "400 Bad Request", on: connection)
                    return
                }
                receiveMore()
            }
        }
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                receiveMore()
            }
        }
        connection.start(queue: .main)
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        if request.method == "GET" && request.path == "/health" {
            sendJSON(
                [
                    "status": "ok",
                    "device": UIDevice.current.name,
                    "system": "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
                ],
                on: connection
            )
            return
        }

        guard request.method == "POST", request.path == "/benchmark" else {
            sendJSON(["error": "Unknown endpoint"], status: "404 Not Found", on: connection)
            return
        }

        do {
            let result = try benchmarker.benchmark(upload: request.body, query: request.query)
            let data = try JSONEncoder().encode(result)
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.lastResult = text
                }
            }
            send(data: data, status: "200 OK", contentType: "application/json", on: connection)
        } catch {
            DispatchQueue.main.async {
                self.lastResult = "Error: \(error)"
            }
            sendJSON(["error": "\(error)"], status: "500 Internal Server Error", on: connection)
        }
    }

    private func sendJSON(_ object: [String: String], status: String = "200 OK", on connection: NWConnection) {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        send(data: data, status: status, contentType: "application/json", on: connection)
    }

    private func send(data: Data, status: String, contentType: String, on connection: NWConnection) {
        var response = Data()
        response.append("HTTP/1.1 \(status)\r\n".data(using: .utf8)!)
        response.append("Content-Type: \(contentType)\r\n".data(using: .utf8)!)
        response.append("Content-Length: \(data.count)\r\n".data(using: .utf8)!)
        response.append("Connection: close\r\n\r\n".data(using: .utf8)!)
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func parseRequest(_ data: Data) -> HTTPRequest? {
        guard let marker = "\r\n\r\n".data(using: .utf8),
              let headerRange = data.range(of: marker) else {
            return nil
        }
        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }
        let requestParts = requestLine.split(separator: " ").map(String.init)
        guard requestParts.count >= 2 else {
            return nil
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        guard data.count - bodyStart >= contentLength else {
            return nil
        }
        let body = data[bodyStart..<(bodyStart + contentLength)]
        let target = requestParts[1]
        let components = URLComponents(string: "http://localhost\(target)")
        var query: [String: String] = [:]
        components?.queryItems?.forEach { item in
            query[item.name] = item.value ?? ""
        }

        return HTTPRequest(
            method: requestParts[0],
            path: components?.path ?? target,
            query: query,
            headers: headers,
            body: Data(body)
        )
    }

    private static func wifiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            let interface = ptr!.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        socklen_t(0),
                        NI_NUMERICHOST
                    )
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
}
