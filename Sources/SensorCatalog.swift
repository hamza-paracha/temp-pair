import Foundation

// Concrete CPU zones from exelban/stats v3.0.21, Modules/Sensors/values.swift (MIT).
enum SensorCatalog {
    static func hostKeys() -> [String] {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return [] }
        return keys(for: String(cString: buffer))
    }

    static func keys(for brand: String) -> [String] {
        let words = brand.lowercased().split(separator: " ")
        if words.contains(where: { $0.hasPrefix("intel") }) { return ["TCAC", "TCBC"] }
        guard words.first == "apple", words.count >= 2 else { return [] }
        let zones: String
        switch words[1] {
        case "m1": zones = "Tp09 Tp0T Tp01 Tp05 Tp0D Tp0H Tp0L Tp0P Tp0X Tp0b"
        case "m2": zones = "Tp1h Tp1t Tp1p Tp1l Tp01 Tp05 Tp09 Tp0D Tp0X Tp0b Tp0f Tp0j"
        case "m3": zones = "Te05 Te0L Te0P Te0S Tf04 Tf09 Tf0A Tf0B Tf0D Tf0E Tf44 Tf49 Tf4A Tf4B Tf4D Tf4E"
        case "m4": zones = "Te05 Te0S Te09 Te0H Tp01 Tp05 Tp09 Tp0D Tp0V Tp0Y Tp0b Tp0e"
        case "m5": zones = "Tp00 Tp04 Tp08 Tp0C Tp0G Tp0K Tp0O Tp0R Tp0U Tp0X Tp0a Tp0d Tp0g Tp0j Tp0m Tp0p Tp0u Tp0y"
        case "m6": zones = "Tp0j Tp0g Tp09 Tp07 Tp0m Tp0L Tp0I Tp0d Tp0E Tp0G Tp0b Tp05 Te07 Te08 Te09 Te0c Te0h Te0i"
        case "a18" where words.dropFirst(2).first == "pro": zones = "Te05 Te0S Tp05 Tp0D"
        default: return []
        }
        return zones.split(separator: " ").map(String.init)
    }
}
