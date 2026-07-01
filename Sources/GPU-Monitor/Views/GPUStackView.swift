import Cocoa
import SwiftUI

final class GPUStackView: NSView {
    private var gpus: [GPUInfo] = []
    private var status: ConnectionStatus = .disconnected
    private var compact = false

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

    func update(gpus: [GPUInfo], status: ConnectionStatus, compact: Bool) {
        self.gpus = gpus; self.status = status; self.compact = compact
        self.frame.size.width = computeWidth(); needsDisplay = true
    }

    func computeWidth() -> CGFloat {
        if status != .connected || gpus.isEmpty {
            let a: [NSAttributedString.Key: Any] = [.font: Fonts.placeholder]
            return max(w("GPU", a), w("SSH", a)) + 12
        }
        let layout = GPULayout(compact: compact)
        var x: CGFloat = 6
        for (i, gp) in gpus.enumerated() {
            if i > 0 { x += layout.separatorAdvance }
            x += layout.columnWidth(for: gp)
        }
        return x
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if status != .connected || gpus.isEmpty { drawPlaceholder(); return }

        let layout = GPULayout(compact: compact)
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let tc = dark ? NSColor.white : NSColor.black
        let sepCol = tc.withAlphaComponent(0.2)
        var x: CGFloat = 6
        let h = frame.height

        for (i, gp) in gpus.enumerated() {
            if i > 0 {
                sepCol.set()
                NSBezierPath(rect: NSRect(x: x - layout.gap / 2 - 0.5, y: 2, width: 1, height: h - 4)).fill()
                x += layout.separatorAdvance
            }
            x = layout.draw(gpu: gp, at: x, height: h, textColor: tc) + layout.gap
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

    private struct GPULayout {
        let compact: Bool
        let gap: CGFloat = 6

        var separatorAdvance: CGFloat { gap / 2 + 0.5 }

        private var fc: NSFont { compact ? Fonts.compact : Fonts.light }

        private func strings(for gpu: GPUInfo) -> (temp: String, power: String, mem: String) {
            ("\(gpu.temperature)°", "\(Int(gpu.power))W", "\(Int(gpu.memoryPercent))%")
        }

        private func primaryWidth(for gpu: GPUInfo) -> CGFloat {
            let s = strings(for: gpu)
            return [s.temp, s.power, s.mem].map { w($0, [.font: fc]) }.max()! + (compact ? 0 : 2)
        }

        func columnWidth(for gpu: GPUInfo) -> CGFloat {
            let cw = primaryWidth(for: gpu)
            if compact { return cw + gap }
            let s = strings(for: gpu)
            let lw = w("GPU \(gpu.index)", [.font: Fonts.small])
            return cw + gap + max(w(s.mem, [.font: Fonts.medium]), lw) + 2 + gap
        }

        func draw(gpu: GPUInfo, at x: CGFloat, height h: CGFloat, textColor tc: NSColor) -> CGFloat {
            let s = strings(for: gpu)
            let cw = primaryWidth(for: gpu)
            let yT = compact ? h - 8 : max(1, h / 2 - 1)
            let yB = compact ? CGFloat(0) : max(0, yT - 9)
            let yM = compact ? h / 2 - 4 : yB

            if compact {
                s.temp.draw(at: x, y: yT, f: fc, c: gpu.tempColor.ns(), h: 8)
                s.power.draw(at: x, y: yM, f: fc, c: tc, h: 8)
                s.mem.draw(at: x, y: yB, f: fc, c: gpu.memColor.ns(), h: 8)
                return x + cw
            } else {
                s.temp.draw(at: x, y: yT, f: Fonts.light, c: gpu.tempColor.ns())
                s.power.draw(at: x, y: yB, f: Fonts.light, c: tc)
                let nx = x + cw + gap
                s.mem.draw(at: nx, y: yT, f: Fonts.medium, c: gpu.memColor.ns())
                let ls = "GPU \(gpu.index)"
                ls.draw(at: nx, y: yB, f: Fonts.small, c: tc.withAlphaComponent(0.5))
                let lw = w(ls, [.font: Fonts.small])
                return nx + max(w(s.mem, [.font: Fonts.medium]), lw) + 2
            }
        }

        private func w(_ s: String, _ a: [NSAttributedString.Key: Any]) -> CGFloat {
            (s as NSString).size(withAttributes: a).width
        }
    }
}

private extension String {
    func draw(at x: CGFloat, y: CGFloat, f: NSFont, c: NSColor, h: CGFloat = 12) {
        let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: c]
        self.draw(in: NSRect(x: x, y: y, width: 60, height: h), withAttributes: a)
    }
}

extension Color { func ns() -> NSColor { NSColor(self) } }
