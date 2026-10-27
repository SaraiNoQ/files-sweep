import AppKit
import SwiftUI
import FileSweepCore

@main
struct RenderingBenchmark {
    @MainActor static func main() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        // Includes bitmap readback; these timings do not measure onscreen FPS.
        let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let root = project.appendingPathComponent(".bench-fixture/glass-check-\(UUID())/Workspaces")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        for i in 0..<10 {
            for j in 0..<4 {
                let directory = root.appendingPathComponent("Branch-\(i)/Folder-\(j)")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for k in 0..<3 { try Data(count: 1).write(to: directory.appendingPathComponent("File-\(k)")) }
            }
        }
        let snapshot = try FileScanner.scan(root: root)
        for (name, size, radial) in [("benchmark", NSSize(width: 1240,height: 760), true)] {
            let model = Workspace()
            model.snapshot = snapshot; model.selectedID = 0; model.status = "合成样本 · 31 项"
            let view = NSHostingView(rootView: WorkspaceView(model: model, radial: radial))
            let window = NSWindow(contentRect: NSRect(origin: .zero,size: size), styleMask: [.titled,.resizable], backing: .buffered, defer: false)
            window.contentView = view
            view.frame = NSRect(origin: .zero,size: size)
            try await Task.sleep(for: .milliseconds(1000))
            window.setContentSize(size)
            try await Task.sleep(for: .milliseconds(1000))
            view.layoutSubtreeIfNeeded()
            print("Preview \(name): requested \(size), rendered \(view.bounds.size)")
            precondition(view.bounds.width >= 1000 && view.bounds.height >= 620)
            func findInput(_ node: NSView) -> SunburstInputView? {
                if let input = node as? SunburstInputView { return input }
                for child in node.subviews { if let input = findInput(child) { return input } }
                return nil
            }
            let input = findInput(view)!
            precondition(input.sectors.count >= 160)
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            var samples: [Double] = []
            for i in 0..<48 {
                let sector = input.sectors[(i*7) % input.sectors.count]
                let angle = (sector.start+sector.end)/2 * 2 * Double.pi - Double.pi/2
                let radius = min(input.bounds.width,input.bounds.height)/2 * (Sunburst.innerRadius(depth: sector.depth)+Sunburst.outerRadius(depth: sector.depth))/2
                let point = CGPoint(x: input.bounds.midX+cos(angle)*radius,y: input.bounds.midY+sin(angle)*radius)
                let event = NSEvent.mouseEvent(with: .mouseMoved, location: input.convert(point,to:nil),modifierFlags: [],timestamp: 0,windowNumber: window.windowNumber, context: nil,eventNumber: 0,clickCount: 0,pressure: 0)!
                let start = ProcessInfo.processInfo.systemUptime
                input.mouseMoved(with: event)
                view.layoutSubtreeIfNeeded()
                view.cacheDisplay(in: view.bounds,to:bitmap)
                let duration = (ProcessInfo.processInfo.systemUptime-start)*1000
                if i >= 8 { samples.append(duration) }
                try await Task.sleep(for: .milliseconds(20))
            }
            samples.sort()
            let label = CommandLine.arguments.dropFirst().first ?? "run"
            precondition(["before", "after"].contains(label))
            let report: [String: Any] = ["label":label,"sectors":input.sectors.count,"samples":samples.count,"median_ms":samples[samples.count/2],"p95_ms":samples[Int(Double(samples.count-1)*0.95)],"method":"offscreen native hover + layout + bitmap capture; not display FPS","all_ms":samples]
            let data = try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
            try data.write(to:project.appendingPathComponent("design/qa/ui-performance/\(label).json"))
            print(String(decoding:data,as:UTF8.self))
            model.shutdown()
            window.contentView = nil
        }
        print("PASS: native hover/render benchmark completed; generated fixtures only")
    }
}
