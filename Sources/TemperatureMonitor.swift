import Cocoa

struct TemperatureSnapshot {
    struct Zone {
        let key: String
        let celsius: Double?
    }

    var cpu: [Zone] = []
    var battery: [Zone] = []
    var checkedAt: Date?
    var cpuPeak: Double? { cpu.compactMap(\.celsius).max() }
    var batteryPeak: Double? { battery.compactMap(\.celsius).max() }

    static func capture(cpuKeys: [String], read: (String) -> Double?) -> Self {
        func zones(_ keys: [String], range: ClosedRange<Double>) -> [Zone] {
            keys.map { key in
                let value = read(key).flatMap { $0.isFinite && range.contains($0) ? $0 : nil }
                return Zone(key: key, celsius: value)
            }
        }
        return Self(cpu: zones(cpuKeys, range: 10...120), battery: zones(["TB1T", "TB2T"], range: 0.01...100),
                    checkedAt: Date())
    }

    static func detail(_ celsius: Double?) -> String {
        celsius.map { String(format: "%.1f \u{b0}C", $0) } ?? "Unavailable"
    }

    func summary(_ zones: [Zone]) -> String {
        guard checkedAt != nil else { return "Not sampled yet" }
        guard !zones.isEmpty else { return "No mapped sensors" }
        let readings = zones.compactMap(\.celsius)
        return "\(Self.detail(readings.max()))  (\(readings.count)/\(zones.count) reporting)"
    }

    func printReport() {
        for zone in cpu + battery {
            print("\(zone.key): \(Self.detail(zone.celsius))")
        }
        print("CPU peak: \(Self.detail(cpuPeak))\nBattery peak: \(Self.detail(batteryPeak))")
        print("Reporting (max of this sample): CPU \(summary(cpu)); battery \(summary(battery))")
    }
}

private enum ColorSetting: String, CaseIterable {
    case cpuWarm, cpuHot, batteryWarm, batteryHot

    var title: String {
        switch self {
        case .cpuWarm: return "CPU yellow"
        case .cpuHot: return "CPU red"
        case .batteryWarm: return "Battery yellow"
        case .batteryHot: return "Battery red"
        }
    }

    var options: [Int] {
        switch self {
        case .cpuWarm: return [55, 60, 65, 70, 75]
        case .cpuHot: return [80, 85, 90, 95]
        case .batteryWarm: return [32, 34, 35, 36, 38]
        case .batteryHot: return [40, 42, 45]
        }
    }

    var key: String { "temperatureOnly.\(rawValue)" }
    var value: Int {
        let stored = UserDefaults.standard.integer(forKey: key)
        if options.contains(stored) { return stored }
        switch self {
        case .cpuWarm: return 65
        case .cpuHot: return 80
        case .batteryWarm: return 35
        case .batteryHot: return 40
        }
    }
}

final class TemperatureMonitor: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let queue = DispatchQueue(label: "TempPair.temperature.sample", qos: .utility)
    private let cpuKeys = SensorCatalog.hostKeys()
    private var timer: DispatchSourceTimer?
    private var generation = 0
    private var systemAsleep = false
    private var displayAsleep = false
    private var item: NSStatusItem!
    private var readout: TemperatureReadout!
    private var snapshot = TemperatureSnapshot()
    private let cpuLine = NSMenuItem()
    private let batteryLine = NSMenuItem()
    private let sampleLine = NSMenuItem()
    private var zoneLines: [String: NSMenuItem] = [:]
    private var menuOpen = false
    private var cpuScale = HeatScale(warm: 65, hot: 80, lead: 15)
    private var batteryScale = HeatScale(warm: 35, hot: 40, lead: 5)

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: 44)
        guard let button = item.button else { return }
        button.isBordered = false
        readout = TemperatureReadout(frame: button.bounds)
        readout.autoresizingMask = [.width, .height]
        button.addSubview(readout)
        button.setAccessibilityLabel("Temp Pair")
        item.menu = makeMenu()
        reloadScales()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(self, selector: #selector(powerChanged(_:)), name: name, object: nil)
        }
        start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        stop()
    }

    @objc private func powerChanged(_ note: Notification) {
        switch note.name {
        case NSWorkspace.willSleepNotification: systemAsleep = true
        case NSWorkspace.didWakeNotification: systemAsleep = false
        case NSWorkspace.screensDidSleepNotification: displayAsleep = true
        case NSWorkspace.screensDidWakeNotification: displayAsleep = false
        default: return
        }
        if systemAsleep || displayAsleep {
            stop()
        } else {
            start()
        }
    }

    private func start() {
        guard timer == nil else { return }
        let token = generation
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .seconds(3), leeway: .milliseconds(350))
        // Confine the connection and all reads to one queue; reopen after sleep or total failure.
        var smc: TemperatureSMC?
        source.setEventHandler { [weak self, cpuKeys] in
            let connection = smc ?? TemperatureSMC()
            let sample = TemperatureSnapshot.capture(cpuKeys: cpuKeys, read: connection.getValue)
            smc = sample.cpuPeak == nil && sample.batteryPeak == nil ? nil : connection
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.snapshot = sample
                self.refresh()
            }
        }
        timer = source
        source.resume()
    }

    private func stop() {
        generation += 1
        timer?.cancel()
        timer = nil
        snapshot = TemperatureSnapshot()
        refresh()
    }

    private func refresh() {
        let width = readout.update(cpu: snapshot.cpuPeak, battery: snapshot.batteryPeak,
                                   cpuScale: cpuScale, batteryScale: batteryScale)
        if item.length != width { item.length = width }
        let description = "Left: battery max, \(snapshot.summary(snapshot.battery))\nRight: CPU zone max, \(snapshot.summary(snapshot.cpu))"
        if item.button?.toolTip != description {
            item.button?.toolTip = description
            item.button?.setAccessibilityValue(description)
        }
        if menuOpen { updateDetails() }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Temp Pair", action: nil, keyEquivalent: "")
        for (line, keys) in [(batteryLine, ["TB1T", "TB2T"]), (cpuLine, cpuKeys)] {
            menu.addItem(line)
            let sub = NSMenu()
            for key in keys {
                zoneLines[key] = sub.addItem(withTitle: key, action: nil, keyEquivalent: "")
            }
            if keys.isEmpty { sub.addItem(withTitle: "No mapped zones", action: nil, keyEquivalent: "") }
            line.submenu = sub
        }
        menu.addItem(sampleLine)
        menu.addItem(.separator())
        let colors = NSMenu()
        colors.addItem(withTitle: "Personal cues, not Apple damage limits", action: nil, keyEquivalent: "")
        colors.addItem(.separator())
        for setting in ColorSetting.allCases {
            let range = NSMenu()
            for value in setting.options {
                let choice = range.addItem(withTitle: "\(value) \u{b0}C", action: #selector(setThreshold(_:)), keyEquivalent: "")
                choice.target = self
                choice.tag = value
                choice.representedObject = setting.rawValue
                choice.state = setting.value == value ? .on : .off
            }
            colors.addItem(withTitle: setting.title, action: nil, keyEquivalent: "").submenu = range
        }
        menu.addItem(withTitle: "Personal color thresholds", action: nil, keyEquivalent: "").submenu = colors
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Temp Pair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) { menuOpen = true; updateDetails() }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false }

    private func updateDetails() {
        cpuLine.title = "CPU zones:  \(snapshot.summary(snapshot.cpu))"
        batteryLine.title = "Battery:  \(snapshot.summary(snapshot.battery))"
        if let date = snapshot.checkedAt {
            sampleLine.title = "Last SMC check: \(date.formatted(date: .omitted, time: .standard))"
        } else {
            sampleLine.title = "Waiting for first SMC check"
        }
        for (key, line) in zoneLines {
            let value = (snapshot.cpu + snapshot.battery).first { $0.key == key }?.celsius
            line.title = "\(key)    \(TemperatureSnapshot.detail(value))"
        }
    }

    @objc private func setThreshold(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let setting = ColorSetting(rawValue: name),
              setting.options.contains(sender.tag) else { return }
        UserDefaults.standard.set(sender.tag, forKey: setting.key)
        sender.menu?.items.forEach { $0.state = $0 == sender ? .on : .off }
        reloadScales()
    }

    private func reloadScales() {
        cpuScale = HeatScale(warm: ColorSetting.cpuWarm.value, hot: ColorSetting.cpuHot.value, lead: 15)
        batteryScale = HeatScale(warm: ColorSetting.batteryWarm.value, hot: ColorSetting.batteryHot.value, lead: 5)
        refresh()
    }
}
