import Cocoa

@main
enum TemperatureOnlyCheck {
    static func main() {
        let inputs: [String: Double] = ["cold": 2, "ok": 50.7, "peak": 79.4, "broken": .infinity,
                                       "sentinel": 255, "TB1T": .nan, "TB2T": 33.42]
        let sample = TemperatureSnapshot.capture(cpuKeys: ["cold", "ok", "peak", "broken", "sentinel"],
                                                 read: { inputs[$0] })
        precondition(sample.cpu.compactMap(\.celsius) == [50.7, 79.4] && sample.cpuPeak == 79.4)
        precondition(sample.batteryPeak == 33.42)
        precondition(sample.summary(sample.battery) == "33.4 \u{b0}C  (1/2 reporting)")
        precondition(sample.summary(sample.cpu) == "79.4 \u{b0}C  (2/5 reporting)")
        let missing = TemperatureSnapshot.capture(cpuKeys: ["peak"], read: { _ in nil })
        precondition(missing.cpuPeak == nil && missing.batteryPeak == nil)
        precondition(missing.checkedAt != nil && missing.summary(missing.battery) == "Unavailable  (0/2 reporting)")
        precondition(missing.summary([]) == "No mapped sensors")
        precondition(TemperatureSnapshot().summary([]) == "Not sampled yet")
        let cpu = HeatScale(warm: 65, hot: 80, lead: 15)
        let battery = HeatScale(warm: 35, hot: 40, lead: 5)
        for (scale, values) in [(cpu, [50.0, 57.5, 65, 72.5, 80]), (battery, [30, 32.5, 35, 37.5, 40])] {
            precondition(values.map { scale.position($0) } == [0, 0.5, 1, 1.5, 2])
            precondition(scale.position(nil) == 0 && scale.position(110) == 2)
            let near = values[2]
            precondition(scale.position(near - 0.01) < 1 && scale.position(near + 0.01) > 1)
        }

        _ = NSApplication.shared
        let view = TemperatureReadout(frame: .zero)
        func layout(_ a: Double?, _ b: Double?) -> [CGRect] {
            let w = view.update(cpu: a, battery: b, cpuScale: cpu, batteryScale: battery)
            view.frame = NSRect(x: 0, y: 0, width: w, height: 24)
            view.layoutSubtreeIfNeeded()
            let text = view.layer!.sublayers!.compactMap { ($0 as? CATextLayer)?.frame }
            let ink = text.reduce(CGRect.null) { $0.union($1) }
            precondition(text.count == 2 && view.bounds.contains(ink))
            precondition(text[0].midY == text[1].midY && text[0].maxX < text[1].minX)
            precondition(!view.isOpaque && (view.layer?.backgroundColor?.alpha ?? 0) == 0)
            precondition(abs(ink.minX - (w - ink.maxX)) < 0.01)
            return text
        }
        let base = layout(65, 35)
        precondition(view.layer!.sublayers!.compactMap { ($0 as? CATextLayer)?.string as? String } == ["35\u{b0}", "65\u{b0}"])
        precondition(layout(79.4, 33.42) == base && layout(nil, nil) == base)
        precondition(layout(101, 35)[1].width > base[1].width)
        print("Passed: valid zones, missing samples, continuous color anchors, balanced two- and three-digit layout.")
    }
}
