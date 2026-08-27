import SwiftUI
import AppKit
import Combine
import CadenceCore

@MainActor
struct RootView: View {
    @EnvironmentObject private var bootstrap: AppBootstrap

    var body: some View {
        switch bootstrap.state {
        case .loading:
            ZStack {
                WorkSurface()
                LoadingLine(message: "Ouverture du dossier…")
            }
        case .failed(let message):
            StartupFailureView(message: message)
        case .ready(let model):
            WorkspaceView()
                .environmentObject(model)
        }
    }
}

/// Shown when the database cannot be opened. It never falls back to a temporary
/// store: losing a day of work silently would be far worse than refusing to start.
@MainActor
struct StartupFailureView: View {
    let message: String
    @EnvironmentObject private var bootstrap: AppBootstrap

    var body: some View {
        ZStack {
            WorkSurface()
            VStack(spacing: Space.xl) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Ink.danger)
                VStack(spacing: Space.sm) {
                    Text("Cadence n'a pas pu ouvrir vos données")
                        .font(Typo.title)
                    Text(message)
                        .font(Typo.body)
                        .foregroundStyle(Ink.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Aucune donnée n'a été modifiée. Vos sauvegardes se trouvent dans le dossier ci-dessous.")
                        .font(Typo.caption)
                        .foregroundStyle(Ink.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Space.md) {
                    Button("Réessayer") { bootstrap.start() }
                        .buttonStyle(.cadencePrimary)
                    Button("Ouvrir le dossier de données") { bootstrap.revealDataFolder() }
                        .buttonStyle(.cadenceSecondary)
                }
            }
            .padding(Space.giant)
        }
    }
}

/// The window: a sidebar, a destination, and the two things that float above them —
/// the undo toast and the command palette.
@MainActor
struct WorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                // Fixed, not a range: with a flexible width the split view answers
                // pressure from the detail pane by shrinking the sidebar, which
                // makes the menu jump about as you move between screens.
                .navigationSplitViewColumnWidth(Metrics.sidebarWidth)
        } detail: {
            ZStack {
                WorkSurface()
                destinationView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(item: Binding(get: { model.activeSheet }, set: { model.activeSheet = $0 })) { sheet in
                sheetView(for: sheet)
            }
        }
        .navigationTitle(model.destination.title)
        .overlay(alignment: .top) { failureLayer }
        .overlay(alignment: .bottom) { toastLayer }
        .overlay { paletteLayer }
        .modifier(PrivacyCover(isEnabled: model.settings.privacyBlurWhenInactive))
        .task {
            if !model.settings.hasCompletedOnboarding { model.isOnboarding = true }
            await model.calendarSync.synchronise(trigger: .launch)
        }
        .sheet(isPresented: Binding(get: { model.isOnboarding }, set: { model.isOnboarding = $0 })) {
            OnboardingView()
                .environmentObject(model)
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch model.destination {
        case .today: TodayView()
        case .session: SessionView()
        case .agenda: AgendaView()
        case .patients: PatientsView()
        case .finances: FinancesView()
        case .settings: SettingsView()
        }
    }

    /// Errors are shown where the user is looking, whichever screen that is, and
    /// never as a modal alert that interrupts what they were doing.
    @ViewBuilder
    private var failureLayer: some View {
        if let failure = model.failure {
            InlineError(message: failure, retryTitle: "Fermer") { model.failure = nil }
                .frame(maxWidth: 560)
                .padding(.top, Space.lg)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .animation(Motion.respectful(Motion.standard, reduceMotion: reduceMotion), value: failure)
        }
    }

    @ViewBuilder
    private var toastLayer: some View {
        if let toast = model.toast {
            ToastView(
                message: toast.text,
                undoTitle: toast.undoLabel,
                onUndo: toast.undoLabel == nil ? nil : { model.performUndo() },
                redoTitle: toast.redoLabel,
                onRedo: toast.redoLabel == nil ? nil : { model.performRedo() }
            )
            .padding(.bottom, Space.xxxl)
            .transition(
                reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    )
            )
            .animation(Motion.respectful(Motion.entrance, reduceMotion: reduceMotion), value: toast.id)
            .onTapGesture { model.dismissToast() }
        }
    }

    @ViewBuilder
    private var paletteLayer: some View {
        if model.isCommandPaletteVisible {
            CommandPaletteView()
                .environmentObject(model)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ViewBuilder
    private func sheetView(for sheet: AppSheet) -> some View {
        switch sheet {
        case .newConsultation(let start, let patientID):
            ConsultationEditor(mode: .create(suggestedStart: start, patientID: patientID))
                .environmentObject(model)
        case .editConsultation(let consultation):
            ConsultationEditor(mode: .edit(consultation))
                .environmentObject(model)
        case .newPatient:
            PatientEditor(patient: nil)
                .environmentObject(model)
        case .editPatient(let patient):
            PatientEditor(patient: patient)
                .environmentObject(model)
        case .editPayment(let payment, let patientName):
            PaymentEditor(payment: payment, patientName: patientName)
                .environmentObject(model)
        case .shortcuts:
            ShortcutsSheet()
        }
    }
}

// MARK: - Sidebar

@MainActor
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            List(selection: destinationBinding) {
                Section {
                    ForEach(Destination.allCases) { destination in
                        SidebarRow(
                            destination: destination,
                            badge: badge(for: destination),
                            isSelected: model.destination == destination,
                            isLive: destination == .session && model.runningItem != nil
                        )
                        .tag(destination)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Spacer(minLength: 0)
            SyncStatusPill()
        }
        .background(Ink.sidebar)
    }

    private var destinationBinding: Binding<Destination?> {
        Binding(
            get: { model.destination },
            set: { if let value = $0 { model.destination = value } }
        )
    }

    /// Only counts that mean "there is work waiting for you" are shown.
    private func badge(for destination: Destination) -> Int? {
        switch destination {
        case .today:
            let pending = model.dayItems.filter { $0.needsAttention || $0.awaitsPayment || $0.needsPatient }.count
            return pending > 0 && model.isShowingToday ? pending : nil
        case .finances:
            return model.pendingPayments.isEmpty ? nil : model.pendingPayments.count
        default:
            return nil
        }
    }
}

@MainActor
private struct SidebarRow: View {
    let destination: Destination
    let badge: Int?
    let isSelected: Bool
    var isLive = false

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: destination.symbol)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 18)
                .foregroundStyle(isLive ? Ink.accent : (isSelected ? Ink.accent : Ink.textSecondary))
                .symbolEffect(.pulse, isActive: isLive)
            Text(destination.title)
                .font(Typo.bodyStrong)
                .foregroundStyle(Ink.textPrimary)
            Spacer(minLength: Space.sm)
            if isLive {
                Circle()
                    .fill(Ink.accent)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel("Séance en cours")
            }
            if let badge {
                Text("\(badge)")
                    .font(Typo.captionNumeric)
                    .foregroundStyle(Ink.accent)
                    .padding(.horizontal, 6)
                    .frame(height: 17)
                    .background(Capsule().fill(Ink.accentSoft))
                    .accessibilityLabel("\(badge) élément(s) à traiter")
            }
        }
        .padding(.vertical, 2)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Always-visible, always-honest state of the calendar connection.
@MainActor
struct SyncStatusPill: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let sync = model.calendarSync
        Button {
            if sync.access.canRead && sync.hasEnabledCalendars {
                Task { await sync.synchronise(trigger: .userAction) }
            } else {
                model.destination = .settings
                model.settingsSection = .calendars
            }
        } label: {
            HStack(spacing: Space.sm) {
                Image(systemName: sync.statusSymbol)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(tint(for: sync))
                    .rotationEffect(.degrees(sync.isSyncing ? 360 : 0))
                    .animation(
                        sync.isSyncing ? .linear(duration: 1.1).repeatForever(autoreverses: false) : .default,
                        value: sync.isSyncing
                    )
                Text(sync.statusLine)
                    .font(Typo.caption)
                    .foregroundStyle(Ink.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(sync.access.canRead ? "Synchroniser l'agenda maintenant (⌘R)" : "Configurer l'accès à l'agenda")
        .padding(Space.sm)
        .accessibilityLabel("État de l'agenda : \(sync.statusLine)")
    }

    private func tint(for sync: CalendarSyncService) -> Color {
        if sync.lastError != nil || !sync.access.canRead { return Ink.warning }
        if sync.isSyncing { return Ink.textSecondary }
        if sync.lastSyncAt != nil { return Ink.accent }
        return Ink.textTertiary
    }
}

/// Hides the window's contents whenever Cadence is not the active application.
///
/// The realistic risk in a consulting room is not a remote attacker: it is the
/// patient sitting across the desk while their therapist switches to another
/// window. An opaque cover — not a blur, which stays partly readable — closes that
/// gap, and costs nothing when the setting is off.
struct PrivacyCover: ViewModifier {
    let isEnabled: Bool

    @State private var isCovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if isEnabled && isCovered { cover }
            }
            .animation(Motion.respectful(Motion.quick, reduceMotion: reduceMotion), value: isCovered)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                isCovered = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                isCovered = false
            }
    }

    private var cover: some View {
        ZStack {
            Ink.canvas
            VStack(spacing: Space.lg) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Ink.textTertiary)
                Text("Contenu masqué")
                    .font(Typo.heading)
                    .foregroundStyle(Ink.textSecondary)
                Text("Revenez dans Cadence pour l'afficher.")
                    .font(Typo.caption)
                    .foregroundStyle(Ink.textTertiary)
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
        .accessibilityLabel("Contenu masqué pendant que Cadence est en arrière-plan")
    }
}
