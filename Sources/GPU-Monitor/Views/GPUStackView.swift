import Cocoa
import SwiftUI

final class GPUStackView: NSView {
    private var gpus: [GPUInfo] = []
    private var status: ConnectionStatus = .disconnected

    // O3: cached fonts, static shared across instances
    private enum Fonts {
        static let compact = NSFont.systemFont(ofSize: 7, weight: .semibold)
        static let light = NSFont.systemFont(ofSize: 10, weight: .light)
        static let medium = NSFont.systemFont(ofSize: 10, weight: .medium)
        static let small = NSFont.systemFont(ofSize: 7, weight: .light)
        static let placeholder = NSFont.systemFont(ofSize: 9, weight: .bold)
    }

    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true; layer?.cornerRadius = 4
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); needsDisplay = true }

    func update(gpus: [GPUInfo], status: ConnectionStatus) {
        self.gpus = gpus; self.status = status
        self.frame.size.width = computeWidth(); needsDisplay = true
    }

    // O5: single layout calculation, used for width + drawing
    func computeWidth() -> CGFloat {
        if status != .connected || gpus.isEmpty {
            let a: [NSAttributedString.Key: Any] = [.font: Fonts.placeholder]
            return max(w("GPU", a), w("SSH", a)) + 12
        }
        let compact = AppSettings.isCompactMode
        let fc = compact ? Fonts.compact : Fonts.light
        let f2 = Fonts.medium
        var x: CGFloat = 6; let gap: CGFloat = 6
        for (i, gp) in gpus.enumerated() {
            if i > 0 { x += gap / 2 + 0.5 }
            let strs = ["\(gp.temperature)°", "\(Int(gp.power))W", "\(Int(gp.memoryPercent))%"]
            let cw = strs.map { w($0, [.font: fc]) }.max()! + (compact ? 0 : 2)
            x += cw + gap
            if !compact {
                let lw = w("GPU \(gp.index)", [.font: Fonts.small])
                x += max(w(strs[2], [.font: f2]), lw) + 2 + gap
            }
        }
        return x
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if status != .connected || gpus.isEmpty { drawPlaceholder(); return }

        let compact = AppSettings.isCompactMode
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let tc = dark ? NSColor.white : NSColor.black
        let fc = compact ? Fonts.compact : Fonts.light
        let f1 = Fonts.light
        let f2 = Fonts.medium
        var x: CGFloat = 6; let h = frame.height; let gap: CGFloat = 6
        let yT = compact ? h - 8 : max(1, h / 2 - 1)
        let yB = compact ? CGFloat(0) : max(0, yT - 9)
        let yM = compact ? h / 2 - 4 : yB
        let sepCol = (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.2)

        for (i, gp) in gpus.enumerated() {
            if i > 0 {
                sepCol.set(); NSBezierPath(rect: NSRect(x: x - gap / 2 - 0.5, y: 2, width: 1, height: h - 4)).fill()
                x += gap / 2 + 0.5
            }
            let t = "\(gp.temperature)°", p = "\(Int(gp.power))W", m = "\(Int(gp.memoryPercent))%"
            let cw = [t, p, m].map { w($0, [.font: fc]) }.max()! + (compact ? 0 : 2)

            if compact {
                t.draw(at: x, y: yT, f: fc, c: gp.tempColor.ns(), h: 8)
                p.draw(at: x, y: yM, f: fc, c: tc, h: 8)
                m.draw(at: x, y: yB, f: fc, c: gp.memColor.ns(), h: 8)
                x += cw + gap
            } else {
                t.draw(at: x, y: yT, f: f1, c: gp.tempColor.ns())
                p.draw(at: x, y: yB, f: f1, c: tc)
                x += cw + gap
                m.draw(at: x, y: yT, f: f2, c: gp.memColor.ns())
                let ls = "GPU \(gp.index)"
                ls.draw(at: x, y: yB, f: Fonts.small, c: tc.withAlphaComponent(0.5))
                let lw = w(ls, [.font: Fonts.small])
                x += max(w(m, [.font: f2]), lw) + 2 + gap
            }
        }
    }

    private func drawPlaceholder() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let f = Fonts.placeholder
        let c: NSColor = switch status {
        case .error: NSColor.systemRed
        case .disconnected: (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.5)
        default: dark ? NSColor.white : NSColor.black
        }
        let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: c]
        let h = frame.height, yT = max(1, h / 2 - 2)
        "GPU".draw(in: NSRect(x: 6, y: yT, width: 100, height: 10), withAttributes: a)
        "SSH".draw(in: NSRect(x: 6, y: yT - 9, width: 100, height: 10), withAttributes: a)
    }

    private func w(_ s: String, _ a: [NSAttributedString.Key: Any]) -> CGFloat {
        (s as NSString).size(withAttributes: a).width
    }
}

private extension String {
    func draw(at x: CGFloat, y: CGFloat, f: NSFont, c: NSColor, h: CGFloat = 12) {
        let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: c]
        self.draw(in: NSRect(x: x, y: y, width: 60, height: h), withAttributes: a)
    }
}

extension Color { func ns() -> NSColor { NSColor(self) } }
