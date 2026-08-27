import SwiftUI
import CadenceCore

// MARK: - Buttons

struct CadenceButtonStyle: ButtonStyle {
    enum Variant {
        case primary        // the one action that matters here
        case secondary      // surface with a hairline
        case ghost          // no chrome until hovered
        case destructive
    }

    enum Size {
        case small, regular, large

        var height: CGFloat {
            switch self {
            case .small: return Metrics.smallControlHeight
            case .regular: return Metrics.controlHeight
            case .large: return Metrics.largeControlHeight
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small: return Space.md
            case .regular: return Space.lg
            case .large: return Space.xl
            }
        }

        var font: Font {
            switch self {
            case .small: return Typo.captionStrong
            case .regular, .large: return Typo.bodyStrong
            }
        }
    }

    var variant: Variant = .secondary
    var size: Size = .regular
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        ButtonSurface(configuration: configuration, variant: variant, size: size, fullWidth: fullWidth)
    }

    @MainActor
    private struct ButtonSurface: View {
        let configuration: ButtonStyleConfiguration
        let variant: Variant
        let size: Size
        let fullWidth: Bool

        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(size.font)
                .foregroundStyle(foreground)
                .padding(.horizontal, size.horizontalPadding)
                .frame(height: size.height)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                )
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .animation(Motion.respectful(Motion.instant, reduceMotion: reduceMotion), value: configuration.isPressed)
                .animation(Motion.respectful(Motion.instant, reduceMotion: reduceMotion), value: isHovering)
                .onHover { isHovering = $0 && isEnabled }
                .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }

        private var foreground: Color {
            switch variant {
            case .primary: return Ink.textOnAccent
            case .secondary: return Ink.textPrimary
            case .ghost: return Ink.textSecondary
            case .destructive: return Ink.danger
            }
        }

        private var background: Color {
            switch variant {
            case .primary:
                if configuration.isPressed { return Ink.accentHover }
                return isHovering ? Ink.accentHover : Ink.accent
            case .secondary:
                if configuration.isPressed { return Ink.surfaceSunken }
                return isHovering ? Ink.surfaceHover : Ink.surface
            case .ghost:
                if configuration.isPressed { return Ink.surfaceSunken }
                return isHovering ? Ink.surfaceHover : .clear
            case .destructive:
                if configuration.isPressed { return Ink.dangerSoft }
                return isHovering ? Ink.dangerSoft : .clear
            }
        }

        private var border: Color {
            switch variant {
            case .primary: return .clear
            case .secondary: return Ink.hairlineStrong
            case .ghost: return .clear
            case .destructive: return isHovering ? Ink.danger.opacity(0.35) : Ink.hairline
            }
        }
    }
}

extension ButtonStyle where Self == CadenceButtonStyle {
    static var cadencePrimary: CadenceButtonStyle { CadenceButtonStyle(variant: .primary) }
    static var cadenceSecondary: CadenceButtonStyle { CadenceButtonStyle(variant: .secondary) }
    static var cadenceGhost: CadenceButtonStyle { CadenceButtonStyle(variant: .ghost) }
    static var cadenceDestructive: CadenceButtonStyle { CadenceButtonStyle(variant: .destructive) }

    static func cadence(_ variant: CadenceButtonStyle.Variant,
                        size: CadenceButtonStyle.Size = .regular,
                        fullWidth: Bool = false) -> CadenceButtonStyle {
        CadenceButtonStyle(variant: variant, size: size, fullWidth: fullWidth)
    }
}

// MARK: - Status

/// State is never carried by colour alone: every chip pairs a tint with a glyph
/// and a word, so it survives both a monochrome screen and colour blindness.
@MainActor
struct StatusChip: View {
    let status: ConsultationStatusPresentation
    var compact = false

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: status.symbol)
                .font(.system(size: compact ? 8.5 : 9.5, weight: .semibold))
            if !compact {
                Text(status.label)
                    .font(Typo.label)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
        }
        .foregroundStyle(status.foreground)
        .padding(.horizontal, compact ? Space.xs : Space.sm)
        .frame(height: 18)
        .background(
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .fill(status.background)
        )
        .accessibilityLabel(status.label)
    }
}

/// Presentation rules for a consultation status, kept in one place so the same
/// vocabulary appears on every screen.
struct ConsultationStatusPresentation {
    let label: String
    let symbol: String
    let foreground: Color
    let background: Color

    static func of(_ status: ConsultationStatus) -> ConsultationStatusPresentation {
        switch status {
        case .scheduled:
            return .init(label: "Planifié", symbol: "circle.dashed",
                         foreground: Ink.textSecondary, background: Ink.neutralSoft)
        case .confirmed:
            return .init(label: "Confirmé", symbol: "checkmark.circle",
                         foreground: Ink.textSecondary, background: Ink.neutralSoft)
        case .inProgress:
            return .init(label: "En cours", symbol: "record.circle",
                         foreground: Ink.accent, background: Ink.accentSoft)
        case .attended:
            return .init(label: "Présent", symbol: "checkmark.circle.fill",
                         foreground: Ink.accent, background: Ink.accentSoft)
        case .absent:
            return .init(label: "Absent", symbol: "xmark.circle.fill",
                         foreground: Ink.danger, background: Ink.dangerSoft)
        case .cancelled:
            return .init(label: "Annulé", symbol: "slash.circle",
                         foreground: Ink.textTertiary, background: Ink.neutralSoft)
        }
    }
}

// MARK: - Patient avatar

@MainActor
struct PatientAvatar: View {
    let monogram: String
    let seed: Int
    var size: CGFloat = 28

    init(monogram: String, seed: Int, size: CGFloat = 28) {
        self.monogram = monogram
        self.seed = seed
        self.size = size
    }

    init(patient: Patient, size: CGFloat = 28) {
        self.init(monogram: patient.monogram, seed: patient.colourSeed, size: size)
    }

    var body: some View {
        let tint = Ink.monogramTint(seed: seed)
        Text(monogram)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(tint.opacity(0.22), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

/// Stands in for an appointment with nobody attached to it yet.
@MainActor
struct UnknownAvatar: View {
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: "questionmark")
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(Ink.warning)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(Ink.warningSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(Ink.warning.opacity(0.25), lineWidth: 1)
            )
            .accessibilityLabel("Patient à rattacher")
    }
}

// MARK: - Canvas texture

/// The faint dot grid that gives the work surface its texture. Drawn once per
/// resize, at low enough contrast that it never competes with content.
@MainActor
struct DotGrid: View {
    var spacing: CGFloat = 22
    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let radius: CGFloat = 0.8
            let colour = Ink.textPrimary.opacity(0.055)
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                        with: .color(colour)
                    )
                    x += spacing
                }
                y += spacing
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The standard page background: warm canvas plus the dot grid.
@MainActor
struct WorkSurface: View {
    var body: some View {
        ZStack {
            Ink.canvas
            DotGrid()
        }
        .ignoresSafeArea()
    }
}

// MARK: - Small parts

@MainActor
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Typo.sectionLabel)
            .tracking(0.7)
            .textCase(.uppercase)
            .foregroundStyle(Ink.textTertiary)
    }
}

@MainActor
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Ink.hairline)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// A keyboard hint, e.g. ⏎ next to the suggested payment.
@MainActor
struct KeyHint: View {
    let keys: String
    var body: some View {
        Text(keys)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Ink.textTertiary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Ink.surfaceSunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Ink.hairline, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

/// One headline figure. Used on the day rail and across the statistics screen.
@MainActor
struct MetricTile: View {
    let label: String
    let value: String
    var note: String? = nil
    var tone: Tone = .neutral
    var isCompact = false

    enum Tone {
        case neutral, positive, warning, negative

        var colour: Color {
            switch self {
            case .neutral: return Ink.textPrimary
            case .positive: return Ink.accent
            case .warning: return Ink.warning
            case .negative: return Ink.danger
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            SectionLabel(text: label)
            Text(value)
                .font(isCompact ? Typo.titleNumeric : Typo.displayNumeric)
                .foregroundStyle(tone.colour)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let note {
                Text(note)
                    .font(Typo.caption)
                    .foregroundStyle(Ink.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) : \(value)")
    }
}

/// A proportion bar, used for the payment-method split.
@MainActor
struct ShareBar: View {
    let slices: [(colour: Color, share: Double)]
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1.5) {
                ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                    Capsule(style: .continuous)
                        .fill(slice.colour)
                        .frame(width: max(2, geometry.size.width * slice.share))
                }
                if slices.isEmpty {
                    Capsule(style: .continuous).fill(Ink.neutralSoft)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Nothing here — but always with a reason and a way forward.
@MainActor
struct EmptyState: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Space.lg) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Ink.textTertiary)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Ink.surfaceSunken))

            VStack(spacing: Space.xs) {
                Text(title)
                    .font(Typo.heading)
                    .foregroundStyle(Ink.textPrimary)
                if let message {
                    Text(message)
                        .font(Typo.body)
                        .foregroundStyle(Ink.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.cadencePrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.giant)
    }
}

/// Inline error, never a modal alert: the user keeps working while they read it.
@MainActor
struct InlineError: View {
    let message: String
    var retryTitle: String? = nil
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Ink.danger)
            Text(message)
                .font(Typo.caption)
                .foregroundStyle(Ink.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.md)
            if let retryTitle, let retry {
                Button(retryTitle, action: retry)
                    .buttonStyle(.cadence(.ghost, size: .small))
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Ink.dangerSoft))
        .accessibilityElement(children: .combine)
    }
}

/// Progress that does not pretend to know how long it will take.
@MainActor
struct LoadingLine: View {
    let message: String
    var body: some View {
        HStack(spacing: Space.md) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.75)
            Text(message)
                .font(Typo.caption)
                .foregroundStyle(Ink.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Text field

@MainActor
struct CadenceTextField: View {
    let placeholder: String
    @Binding var text: String
    var symbol: String? = nil
    var isMultiline = false

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Space.sm) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Ink.textTertiary)
            }
            Group {
                if isMultiline {
                    TextEditor(text: $text)
                        .font(Typo.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 64)
                } else {
                    TextField(placeholder, text: $text)
                        .font(Typo.body)
                }
            }
            .textFieldStyle(.plain)
            .focused($isFocused)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, isMultiline ? Space.sm : 0)
        .frame(minHeight: isMultiline ? 72 : Metrics.controlHeight)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Ink.surfaceSunken)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(isFocused ? Ink.accent : Ink.hairlineStrong, lineWidth: isFocused ? 1.5 : 1)
        )
        .animation(Motion.instant, value: isFocused)
        .accessibilityLabel(placeholder)
    }
}

// MARK: - Toast

/// The counterweight to having no confirmation dialogs: every action says what it
/// did and how to take it back.
@MainActor
struct ToastView: View {
    let message: String
    var undoTitle: String? = nil
    var onUndo: (() -> Void)? = nil
    var redoTitle: String? = nil
    var onRedo: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Space.lg) {
            Text(message)
                .font(Typo.bodyStrong)
                .foregroundStyle(Ink.textPrimary)
            if let undoTitle, let onUndo {
                Divider().frame(height: 16)
                Button(action: onUndo) {
                    HStack(spacing: Space.sm) {
                        Text(undoTitle)
                        KeyHint(keys: "⌘Z")
                    }
                }
                .buttonStyle(.cadence(.ghost, size: .small))
            }
            if let redoTitle, let onRedo {
                Divider().frame(height: 16)
                Button(action: onRedo) {
                    HStack(spacing: Space.sm) {
                        Text(redoTitle)
                        KeyHint(keys: "⇧⌘Z")
                    }
                }
                .buttonStyle(.cadence(.ghost, size: .small))
            }
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.lg)
        .cadenceFloating(Radius.sheet)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Attendance

/// Presence as a control rather than a label.
///
/// The status used to be a read-only chip: once you clicked Présent the buttons
/// disappeared and the only way back was a hidden menu. A misclick is the most
/// common thing that happens in a busy day, so the control stays on screen in
/// every state — and clicking the segment that is already active clears it.
@MainActor
struct AttendanceControl: View {
    enum Size {
        case regular, large

        var height: CGFloat { self == .large ? 34 : 26 }
        var font: Font { self == .large ? Typo.bodyStrong : Typo.captionStrong }
        var iconSize: CGFloat { self == .large ? 12 : 10 }
        var padding: CGFloat { self == .large ? Space.lg : Space.md }
    }

    let status: ConsultationStatus
    var size: Size = .regular
    let onPresent: () -> Void
    let onAbsent: () -> Void
    /// Called when the active segment is clicked again — the misclick escape hatch.
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment(
                title: "Présent",
                symbol: "checkmark.circle.fill",
                isActive: status == .attended || status == .inProgress,
                tint: Ink.accent,
                background: Ink.accentSoft,
                action: { status == .attended ? onClear() : onPresent() },
                hint: status == .attended ? "Annuler la présence" : "Marquer présent (P)"
            )

            Rectangle()
                .fill(Ink.hairline)
                .frame(width: 1)
                .padding(.vertical, 4)

            segment(
                title: "Absent",
                symbol: "xmark.circle.fill",
                isActive: status == .absent,
                tint: Ink.danger,
                background: Ink.dangerSoft,
                action: { status == .absent ? onClear() : onAbsent() },
                hint: status == .absent ? "Annuler l'absence" : "Marquer absent (A)"
            )
        }
        .frame(height: size.height)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Ink.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Ink.hairlineStrong, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    private func segment(
        title: String,
        symbol: String,
        isActive: Bool,
        tint: Color,
        background: Color,
        action: @escaping () -> Void,
        hint: String
    ) -> some View {
        AttendanceSegment(
            title: title, symbol: symbol, isActive: isActive,
            tint: tint, background: background, size: size, action: action
        )
        .help(hint)
        .accessibilityLabel(hint)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

@MainActor
private struct AttendanceSegment: View {
    let title: String
    let symbol: String
    let isActive: Bool
    let tint: Color
    let background: Color
    let size: AttendanceControl.Size
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                Image(systemName: isActive ? symbol : symbol.replacingOccurrences(of: ".fill", with: ""))
                    .font(.system(size: size.iconSize, weight: .semibold))
                Text(title)
                    .font(size.font)
            }
            .foregroundStyle(isActive ? tint : (isHovering ? Ink.textPrimary : Ink.textSecondary))
            .padding(.horizontal, size.padding)
            .frame(maxHeight: .infinity)
            .background(isActive ? background : (isHovering ? Ink.surfaceHover : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Motion.respectful(Motion.instant, reduceMotion: reduceMotion), value: isActive)
        .animation(Motion.respectful(Motion.instant, reduceMotion: reduceMotion), value: isHovering)
    }
}

/// Start and stop a session. Separate from attendance on purpose: being present and
/// having a measured session are two different facts, and one should not imply the
/// other. Clicking it while running offers to stop; the menu can clear the times.
@MainActor
struct SessionButton: View {
    let isRunning: Bool
    let elapsed: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Image(systemName: isRunning ? "stop.circle.fill" : "play.circle")
                    .font(.system(size: 13, weight: .medium))
                if let elapsed {
                    Text(elapsed)
                        .font(Typo.captionNumeric)
                }
            }
            .foregroundStyle(isRunning ? Ink.textOnAccent : (isHovering ? Ink.accent : Ink.textSecondary))
            .padding(.horizontal, isRunning ? Space.md : Space.sm)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(isRunning ? Ink.accent : (isHovering ? Ink.surfaceHover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isRunning ? "Terminer la séance" : "Démarrer la séance et ouvrir l'écran dédié")
        .accessibilityLabel(isRunning ? "Terminer la séance" : "Démarrer la séance")
    }
}

// MARK: - Settlement

/// The tick that says a transfer or a cheque has landed.
///
/// It sits directly on the payment it refers to — on the day rail, on the patient's
/// record, in the ledger — because that is where the user is looking when they
/// reconcile, and a separate screen would be one navigation too many.
@MainActor
struct SettlementTick: View {
    let isSettled: Bool
    var showsLabel = false
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Image(systemName: isSettled ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSettled ? Ink.accent : Ink.warning)
                    .symbolEffect(.bounce, value: isSettled)
                if showsLabel {
                    Text(isSettled ? "Reçu" : "Marquer reçu")
                        .font(Typo.caption)
                        .foregroundStyle(isSettled ? Ink.textSecondary : Ink.warning)
                }
            }
            .padding(.horizontal, showsLabel ? Space.md : Space.xs)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .fill(isHovering ? Ink.surfaceHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Motion.respectful(Motion.quick, reduceMotion: reduceMotion), value: isSettled)
        .help(isSettled ? "Remettre en attente de règlement" : "Marquer comme reçu")
        .accessibilityLabel(isSettled ? "Reçu — cliquer pour remettre en attente" : "En attente — cliquer pour marquer reçu")
    }
}

// MARK: - Progress

/// The day as a ring. Gives the working day a shape and an end, which a bare
/// counter does not.
@MainActor
struct DayProgressRing: View {
    let done: Int
    let total: Int
    var diameter: CGFloat = 46

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(done) / Double(total))
    }

    private var isComplete: Bool { total > 0 && done >= total }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Ink.surfaceSunken, lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    isComplete ? Ink.accent : Ink.accent.opacity(0.85),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(Motion.standard, value: fraction)

            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: diameter * 0.34, weight: .semibold))
                    .foregroundStyle(Ink.accent)
            } else {
                VStack(spacing: -2) {
                    Text("\(done)")
                        .font(.system(size: diameter * 0.34, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Ink.textPrimary)
                    Text("/\(total)")
                        .font(.system(size: diameter * 0.21, weight: .medium).monospacedDigit())
                        .foregroundStyle(Ink.textTertiary)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isComplete ? "Journée terminée" : "\(done) rendez-vous traités sur \(total)")
    }
}
