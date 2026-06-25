import SwiftUI

struct GPUColumnView: View {
    let gpu: GPUInfo

    var body: some View {
        VStack(spacing: 2) {
            Text("GPU \(gpu.index)")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)

            if let gen = gpu.pcieGen, let width = gpu.pcieWidth {
                Text("PCIe Gen\(gen) x\(width)")
                    .font(.system(size: 8, weight: .light))
                    .foregroundStyle(.secondary.opacity(0.8))
            }

            Text("\(gpu.temperature)°C")
                .font(.title3)
                .foregroundStyle(gpu.tempColor)

            Text("\(Int(gpu.power))W")
                .font(.subheadline)
                .foregroundStyle(.primary)

            VStack(spacing: 2) {
                if let fan = gpu.fanPercent {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("\(fan)%")
                            .font(.subheadline)
                            .foregroundStyle(.cyan)
                        Text("FAN")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("\(Int(gpu.memoryPercent))%")
                    .font(.subheadline)
                    .foregroundStyle(gpu.memColor)

                Capsule()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 56, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(gpu.memColor)
                            .frame(width: max(2, 56 * gpu.memoryPercent / 100), height: 4)
                            .clipShape(.capsule)
                    }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
