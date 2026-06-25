import SwiftUI

struct GPUInfo: Equatable, Identifiable {
    let index: Int
    var id: Int { index }
    let temperature: Int
    let power: Double
    let memoryPercent: Double
    let fanPercent: Int?
    let pcieGen: Int?
    let pcieWidth: Int?

    var tempColor: Color {
        if temperature < 60 { return .green }
        if temperature < 75 { return .yellow }
        return .red
    }

    var memColor: Color {
        if memoryPercent < 50 { return .green }
        if memoryPercent <= 80 { return .yellow }
        return .red
    }
}
