import Cocoa
import QuartzCore

struct HeatScale {
    let warm: Int
    let hot: Int
    let lead: Int

    // 0 = menu text, 1 = yellow, 2 = red. Use the raw reading, not the displayed integer.
    func position(_ celsius: Double?) -> Double {
        guard let celsius, celsius.isFinite else { return 0 }
        if celsius <= Double(warm) {
            return max(0, (celsius - Double(warm - lead)) / Double(lead))
        }
        return 1 + min(1, (celsius - Double(warm)) / Double(hot - warm))
    }
}

final class TemperatureReadout: NSView {
    private let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    private let inset: CGFloat = 1
    private let gap: CGFloat = 4
    private let numbers = [CATextLayer(), CATextLayer()]
    private var heat = [0.0, 0.0]
    private var widths: [CGFloat] = [0, 0]
    private lazy var minimumWidth = width("00\u{b0}")
    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for text in numbers {
            text.font = numberFont
            text.fontSize = numberFont.pointSize
            text.alignmentMode = .center
            text.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            text.actions = ["string": NSNull(), "bounds": NSNull(), "position": NSNull(), "foregroundColor": NSNull()]
            layer?.addSublayer(text)
        }
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func width(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: numberFont]).width)
    }

    func update(cpu: Double?, battery: Double?, cpuScale: HeatScale, batteryScale: HeatScale) -> CGFloat {
        let values = [battery, cpu].map { $0.map { "\(Int($0.rounded()))\u{b0}" } ?? "\u{2014}" }
        for i in numbers.indices where numbers[i].string as? String != values[i] {
            numbers[i].string = values[i]
            let w = max(minimumWidth, width(values[i]))
            if widths[i] != w { widths[i] = w; needsLayout = true }
        }
        let next = [batteryScale.position(battery), cpuScale.position(cpu)]
        if next != heat || numbers[0].foregroundColor == nil {
            heat = next
            recolor(animate: window != nil)
        }
        return 2 * inset + widths[0] + gap + widths[1]
    }

    override func layout() {
        super.layout()
        var x = (bounds.width - widths[0] - gap - widths[1]) / 2
        let height = ceil(numberFont.ascender - numberFont.descender)
        for i in numbers.indices {
            numbers[i].frame = CGRect(x: x, y: floor(bounds.midY - height / 2), width: widths[i], height: height)
            x += widths[i] + gap
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil } // Let the native status button track clicks.

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        for text in numbers { text.contentsScale = window?.backingScaleFactor ?? 2 }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        recolor(animate: false)
    }

    private func recolor(animate: Bool) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let neutral = NSColor.labelColor.usingColorSpace(.sRGB) ?? (dark ? .white : .black)
            // Darken gold on a light menu bar so it stays legible at menu-bar size.
            let yellow = dark ? NSColor(srgbRed: 1, green: 0.85, blue: 0.23, alpha: 1)
                              : NSColor(srgbRed: 0.52, green: 0.37, blue: 0, alpha: 1)
            let red = dark ? NSColor(srgbRed: 1, green: 0.38, blue: 0.32, alpha: 1)
                           : NSColor(srgbRed: 0.72, green: 0.13, blue: 0.09, alpha: 1)
            for i in numbers.indices {
                let t = heat[i]
                let target = t <= 1 ? neutral.blended(withFraction: t, of: yellow) : yellow.blended(withFraction: t - 1, of: red)
                let color = (target ?? neutral).cgColor
                let text = numbers[i]
                guard text.foregroundColor != color else { continue }
                if animate, let old = text.presentation()?.foregroundColor ?? text.foregroundColor,
                   !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    let fade = CABasicAnimation(keyPath: "foregroundColor")
                    fade.fromValue = old
                    fade.toValue = color
                    fade.duration = 0.45
                    text.add(fade, forKey: "temperatureTint")
                }
                text.foregroundColor = color
            }
        }
    }
}
