import SwiftUI

@main
struct LatencyBenchApp: App {
    @StateObject private var server = BenchmarkServer(port: 8765)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(server)
                .onAppear {
                    server.start()
                }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var server: BenchmarkServer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LatencyBench")
                .font(.system(size: 32, weight: .semibold))
            Text(server.status)
                .font(.system(size: 15, design: .monospaced))
            Text("URL")
                .font(.headline)
            Text(server.displayURL)
                .font(.system(size: 15, design: .monospaced))
                .textSelection(.enabled)
            Text("Last Result")
                .font(.headline)
            Text(server.lastResult)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
        }
        .padding()
    }
}

