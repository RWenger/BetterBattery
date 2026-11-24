import SwiftUI
import AppKit

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case nothing
    case percent
    case time
    case watts

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nothing: return "None"
        case .percent: return "%"
        case .time: return "Time"
        case .watts: return "Watts"
        }
    }
}

enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    /// The original filled capsule with the reading punched out.
    case classic
    /// Closer to the system battery: solid white outline and fill, faint
    /// white empty track, reading and bolt cut out as transparent holes.
    case outline

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: return "Classic"
        case .outline: return "Outline"
        }
    }
}

/// Flat, modern battery glyph modeled on the iOS status bar battery:
/// translucent capsule track, solid fill sized to the charge level, and the
/// reading (percent / time / watts) punched out of the shape as a cutout.
///
/// The glyph is drawn offscreen into an image before it reaches the menu
/// bar — the status item pipeline drops blend modes when compositing live
/// views (which erased the battery shape entirely in 1.1.0), but it shows
/// pre-rendered images pixel-for-pixel.
struct BatteryGlyph: View {
    let snapshot: BatterySnapshot
    let mode: MenuBarDisplayMode
    var style: MenuBarIconStyle = .classic
    let darkMenuBar: Bool
    let warn: Int
    let critical: Int

    private let bodyHeight: CGFloat = 13
    private let cornerRadius: CGFloat = 4
    // One fixed size for every display mode so the menu bar never shifts.
    private let bodyWidth: CGFloat = 36

    private var baseColor: Color { darkMenuBar ? .white : .black }

    var body: some View {
        switch style {
        case .classic: classicBody
        case .outline: outlineBody
        }
    }

    // MARK: - Classic

    private var classicBody: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(baseColor.opacity(0.35))

                Rectangle()
                    .fill(fillColor)
                    .frame(width: fillWidth)

                readoutOverlay
                    .frame(width: bodyWidth, height: bodyHeight)
                    .blendMode(.destinationOut)
            }
            .frame(width: bodyWidth, height: bodyHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .compositingGroup()

            // the nub
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(baseColor.opacity(0.5))
                .frame(width: 2, height: 4.5)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 1)
    }

    // MARK: - Outline

    private let outlineWidth: CGFloat = 28
    private let outlineHeight: CGFloat = 12.5
    private let outlineInset: CGFloat = 2
    private var outlineInnerWidth: CGFloat { outlineWidth - outlineInset * 2 }
    private var outlineInnerHeight: CGFloat { outlineHeight - outlineInset * 2 }

    private var outlineFillWidth: CGFloat {
        guard snapshot.state != .noBattery else { return 0 }
        let fraction = max(0, min(1, Double(snapshot.percent) / 100))
        return max(2, outlineInnerWidth * CGFloat(fraction))
    }

    /// White like the system battery; orange/red only past the low-battery
    /// thresholds.
    private var outlineFillColor: Color {
        if snapshot.state == .discharging {
            if snapshot.percent <= critical { return PowerAccent.red }
            if snapshot.percent <= warn { return PowerAccent.orange }
        }
        return .white
    }

    private var outlineBody: some View {
        HStack(spacing: 1) {
            ZStack {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 1)

                ZStack(alignment: .leading) {
                    // Faint track so the cut-out reading stays legible past
                    // the fill (a fully transparent track would swallow it).
                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                    Rectangle()
                        .fill(outlineFillColor)
                        .frame(width: outlineFillWidth)
                    readoutContent(boltSize: 6.5, textSize: 8.5, weight: .semibold, design: .default)
                        .frame(width: outlineInnerWidth, height: outlineInnerHeight)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .frame(width: outlineInnerWidth, height: outlineInnerHeight)
                .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))
            }
            .frame(width: outlineWidth, height: outlineHeight)

            // the nub
            RoundedRectangle(cornerRadius: 0.75, style: .continuous)
                .fill(Color.white)
                .frame(width: 1.5, height: 4)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 1)
    }

    // MARK: - Pieces

    private var readoutOverlay: some View {
        readoutContent(boltSize: 7, textSize: 9.5, weight: .bold, design: .rounded)
    }

    @ViewBuilder
    private func readoutContent(boltSize: CGFloat, textSize: CGFloat, weight: Font.Weight, design: Font.Design) -> some View {
        if snapshot.state != .noBattery {
            HStack(spacing: style == .outline ? 0.5 : 1) {
                if snapshot.state == .charging && mode != .watts {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: boltSize, weight: .bold))
                }
                if let readout {
                    Text(readout)
                        .font(.system(size: textSize, weight: weight, design: design))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }
        }
    }

    private var readout: String? {
        switch mode {
        case .nothing:
            return nil
        case .percent:
            return "\(snapshot.percent)"
        case .watts:
            let magnitude = abs(snapshot.smoothedWatts)
            if magnitude < 0.05 { return "0W" }
            let number = magnitude >= 10
                ? String(format: "%.0f", magnitude)
                : String(format: "%.1f", magnitude)
            switch snapshot.state {
            case .charging:
                return "▴\(number)W"
            case .discharging:
                return "▾\(number)W"
            default:
                return "\(number)W"
            }
        case .time:
            let minutes: Int?
            switch snapshot.state {
            case .charging: minutes = snapshot.timeToFullMinutes
            case .discharging: minutes = snapshot.timeToEmptyMinutes
            default: minutes = nil
            }
            guard let minutes else {
                return (snapshot.state == .charging || snapshot.state == .discharging) ? "–" : nil
            }
            let hours = minutes / 60
            let mins = minutes % 60
            if hours > 0 { return String(format: "%dh%02dm", hours, mins) }
            return "\(mins)m"
        }
    }

    private var fillWidth: CGFloat {
        guard snapshot.state != .noBattery else { return 0 }
        let fraction = max(0, min(1, Double(snapshot.percent) / 100))
        return max(4, bodyWidth * CGFloat(fraction))
    }

    private var fillColor: Color {
        PowerAccent.iconFill(for: snapshot, warn: warn, critical: critical, neutral: baseColor)
    }

    /// Everything that affects the rendered pixels, cheap to compare —
    /// MenuBarLabel uses this to skip re-rendering identical frames.
    var cacheKey: String {
        "\(style.rawValue)|\(mode.rawValue)|\(readout ?? "")|\(snapshot.percent)|\(String(describing: snapshot.state))|\(darkMenuBar)|\(warn)|\(critical)"
    }
}

struct MenuBarLabel: View {
    @ObservedObject var monitor: PowerMonitor
    @AppStorage(DefaultsKey.menuBarDisplayMode) private var displayModeRaw = MenuBarDisplayMode.percent.rawValue
    @AppStorage(DefaultsKey.menuBarIconStyle) private var iconStyleRaw = MenuBarIconStyle.classic.rawValue
    @AppStorage(DefaultsKey.warnThreshold) private var warnThreshold = 20
    @AppStorage(DefaultsKey.criticalThreshold) private var criticalThreshold = 10
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let glyph = BatteryGlyph(
            snapshot: monitor.snapshot,
            mode: MenuBarDisplayMode(rawValue: displayModeRaw) ?? .percent,
            style: MenuBarIconStyle(rawValue: iconStyleRaw) ?? .classic,
            darkMenuBar: colorScheme == .dark,
            warn: warnThreshold,
            critical: criticalThreshold
        )
        if let image = renderedImage(for: glyph) {
            Image(nsImage: image)
        } else {
            glyph
        }
    }

    private final class RenderCache {
        var key = ""
        var image: NSImage?
    }
    private static let cache = RenderCache()

    private func renderedImage(for glyph: BatteryGlyph) -> NSImage? {
        // Re-render only when the glyph's visible content changed — at idle
        // (say, percent mode on a steady charge) the 1 Hz tick draws nothing.
        let key = glyph.cacheKey
        if key == Self.cache.key, let cached = Self.cache.image {
            return cached
        }
        let renderer = ImageRenderer(content: glyph)
        renderer.scale = max(2, NSScreen.main?.backingScaleFactor ?? 2)
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        Self.cache.key = key
        Self.cache.image = image
        return image
    }
}
