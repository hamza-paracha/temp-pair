import Cocoa

if CommandLine.arguments.contains("--sample") {
    let smc = TemperatureSMC()
    TemperatureSnapshot.capture(cpuKeys: SensorCatalog.hostKeys(), read: smc.getValue).printReport()
} else {
    let app = NSApplication.shared
    let monitor = TemperatureMonitor()
    app.setActivationPolicy(.accessory)
    app.delegate = monitor
    withExtendedLifetime(monitor) { app.run() }
}
