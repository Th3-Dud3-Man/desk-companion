import SwiftUI
import CadenceCore

/// The screen for the fifty minutes the application exists to support.
///
/// Everything that matters while a session runs is here and nothing else is: how
/// long it has been going, who is in the room, somewhere to jot a practical note,
/// and one button to finish. Ending the session brings the payment up in place, so
/// the whole sequence — start, run, end, get paid — never leaves this screen.
@MainActor
struct SessionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var notes = ""
    @State private var loadedNotesFor: UUID?
    @State private var noteSaver: Task<Void, Never>?
    /// The session just finished on this screen; its payment stays in view.
    @State private var justEnded: UUID?
    @FocusState private var isNotesFocused: Bool

    private var running: DayItem? { model.runningItem }

    private var settling: DayItem? {
        guard let justEnded else { return nil }
        return model.dayItems.first { $0.id == justEnded && $0.awaitsPayment }
    }

    var body: some View {
        Group {
            if let item = running {
                activeSession(item)
            } else if let item = settling {
                finishedSession(item)
            } else {
                idle
            }
        }
        .onChange(of: model.runningItem?.id) { previous, current in
            if current == nil, let previous { justEnded = previous }
            if current != nil { justEnded = nil }
        }
        .onDisappear { flushNotes() }
    }

    // MARK: Running

    private func activeSession(_ item: DayItem) -> some View {
        VStack(spacing: 0) {
            header(item)

            ScrollView {
                VStack(spacing: Space.huge) {
                    timer(item)
                    identity(item)
                    notesCard(item)
                    controls(item)
                    context(item)
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, Space.xxl)
                .padding(.bottom, Space.giant)
            }
            .scrollContentBackground(.hidden)
        }
        .onAppear { loadNotes(item) }
        .onChange(of: item.id) { _, _ in loadNotes(item) }
    }

    private func header(_ item: DayItem) -> some View {
        HStack(spacing: Space.lg) {
            Button {
                model.destination = .today
            } label: {
                HStack(spacing: Space.xs) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                    Text("Journée")
                }
            }
            .buttonStyle(.cadence(.ghost, size: .small))
            .help("Revenir à la journée (⌘1)")

            Spacer()

            HStack(spacing: Space.sm) {
                Circle()
                    .fill(Ink.accent)
                    .frame(width: 7, height: 7)
                Text("Séance en cours")
                    .font(Typo.captionStrong)
                    .foregroundStyle(Ink.accent)
            }
            .padding(.horizontal, Space.md)
            .frame(height: 24)
            .background(Capsule().fill(Ink.accentSoft))
        }
        .padding(.horizontal, Space.xxl)
        .padding(.top, Space.xl)
        .padding(.bottom, Space.lg)
    }

    /// A live clock, ticking every second because this is the one place a minute's
    /// resolution is not enough.
    private func timer(_ item: DayItem) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let start = item.consultation.actualStart ?? item.consultation.scheduledStart
            let elapsed = max(0, context.date.timeIntervalSince(start))
            let planned = max(1, item.consultation.scheduledDuration)
            let fraction = min(1.2, elapsed / planned)
            let isOvertime = elapsed > planned

            VStack(spacing: Space.lg) {
                ZStack {
                    Circle()
                        .stroke(Ink.surfaceSunken, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: min(1, fraction))
                        .stroke(
                            isOvertime ? Ink.warning : Ink.accent,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        Text(Self.clock(elapsed))
                            .font(.system(size: 40, weight: .medium).monospacedDigit())
                            .foregroundStyle(Ink.textPrimary)
                        Text(isOvertime
                             ? "+ \(CadenceFormat.duration(elapsed - planned))"
                             : "sur \(CadenceFormat.duration(planned))")
                            .font(Typo.caption)
                            .foregroundStyle(isOvertime ? Ink.warning : Ink.textTertiary)
                    }
                }
                .frame(width: 190, height: 190)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Séance commencée depuis \(CadenceFormat.duration(elapsed))")
        }
        .padding(.top, Space.lg)
    }

    private func identity(_ item: DayItem) -> some View {
        VStack(spacing: Space.md) {
            HStack(spacing: Space.lg) {
                if let patient = item.patient {
                    PatientAvatar(patient: patient, size: 40)
                } else {
                    UnknownAvatar(size: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(Typo.display)
                        .foregroundStyle(Ink.textPrimary)
                    Text(slotDescription(item))
                        .font(Typo.body)
                        .foregroundStyle(Ink.textSecondary)
                }
            }
        }
    }

    private func slotDescription(_ item: DayItem) -> String {
        var parts = [
            "\(CadenceFormat.time(item.consultation.scheduledStart)) – \(CadenceFormat.time(item.consultation.scheduledEnd))"
        ]
        if let start = item.consultation.actualStart {
            parts.append("démarrée à \(CadenceFormat.time(start))")
        }
        if let location = item.consultation.location, !location.isEmpty { parts.append(location) }
        return parts.joined(separator: " · ")
    }

    private func notesCard(_ item: DayItem) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                SectionLabel(text: "Note de séance")
                Spacer()
                Text("informations pratiques — pas un dossier clinique")
                    .font(Typo.caption)
                    .foregroundStyle(Ink.textTertiary)
            }
            TextEditor(text: $notes)
                .font(Typo.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 92)
                .focused($isNotesFocused)
                .padding(Space.md)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Ink.surfaceSunken)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(isNotesFocused ? Ink.accent : Ink.hairlineStrong,
                                      lineWidth: isNotesFocused ? 1.5 : 1)
                )
                .onChange(of: notes) { _, _ in scheduleNoteSave(item) }
                .onChange(of: isNotesFocused) { _, focused in if !focused { flushNotes() } }
                .accessibilityLabel("Note de séance")
        }
        .cadenceCard(padding: Space.xl)
    }

    private func controls(_ item: DayItem) -> some View {
        VStack(spacing: Space.lg) {
            Button {
                flushNotes()
                model.endSession(item)
            } label: {
                HStack(spacing: Space.md) {
                    Image(systemName: "stop.circle.fill").font(.system(size: 15, weight: .medium))
                    Text("Terminer la séance")
                }
            }
            .buttonStyle(.cadence(.primary, size: .large, fullWidth: true))
            .keyboardShortcut(.return, modifiers: .command)
            .help("Terminer et passer au paiement (⌘⏎)")

            Button("Annuler le démarrage") {
                model.cancelSessionStart(item)
                model.destination = .today
            }
            .buttonStyle(.cadence(.ghost, size: .regular))
            .help("La séance n'aurait pas dû être démarrée : efface les horaires réels")
        }
    }

    private func context(_ item: DayItem) -> some View {
        HStack(spacing: Space.xxl) {
            contextItem(
                label: "Paiement proposé",
                value: item.advice.primary.money.formatted(),
                note: "\(model.settings.methodLabel(item.advice.primary.methodID)) · \(item.advice.basis.shortLabel.lowercased())"
            )
            if let patient = item.patient,
               let profile = try? model.store.profile(forPatient: patient.id, settings: model.settings) {
                contextItem(
                    label: "Rythme",
                    value: profile.rhythm.label,
                    note: profile.lastSeen.map { "vu \(CadenceFormat.since($0))" }
                )
                if profile.outstandingCents > 0 {
                    contextItem(
                        label: "En attente",
                        value: Money(cents: profile.outstandingCents,
                                     currencyCode: model.settings.currencyCode).formatted(),
                        note: "règlement annoncé non reçu",
                        tone: Ink.warning
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .cadenceCard(padding: Space.xl)
    }

    private func contextItem(label: String, value: String, note: String?, tone: Color = Ink.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            SectionLabel(text: label)
            Text(value)
                .font(Typo.headingNumeric)
                .foregroundStyle(tone)
            if let note {
                Text(note)
                    .font(Typo.caption)
                    .foregroundStyle(Ink.textTertiary)
            }
        }
    }

    // MARK: Just finished

    private func finishedSession(_ item: DayItem) -> some View {
        VStack(spacing: Space.xxl) {
            Spacer(minLength: 0)

            VStack(spacing: Space.lg) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Ink.accent)
                Text("Séance terminée")
                    .font(Typo.display)
                    .foregroundStyle(Ink.textPrimary)
                Text(durationSummary(item))
                    .font(Typo.body)
                    .foregroundStyle(Ink.textSecondary)
            }

            VStack(alignment: .leading, spacing: Space.lg) {
                HStack(spacing: Space.lg) {
                    if let patient = item.patient { PatientAvatar(patient: patient, size: 32) }
                    Text(item.title)
                        .font(Typo.heading)
                        .foregroundStyle(Ink.textPrimary)
                    Spacer()
                }
                Hairline()
                PaymentStrip(item: item)
            }
            .frame(maxWidth: 620)
            .cadenceCard(padding: Space.xl)

            Button("Plus tard, revenir à la journée") {
                justEnded = nil
                model.destination = .today
            }
            .buttonStyle(.cadence(.ghost, size: .regular))

            Spacer(minLength: 0)
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func durationSummary(_ item: DayItem) -> String {
        guard let duration = item.consultation.actualDuration else { return item.title }
        let planned = item.consultation.scheduledDuration
        let delta = duration - planned
        if abs(delta) < 120 { return "\(CadenceFormat.duration(duration)) · comme prévu" }
        return delta > 0
            ? "\(CadenceFormat.duration(duration)) · \(CadenceFormat.duration(delta)) de plus que prévu"
            : "\(CadenceFormat.duration(duration)) · \(CadenceFormat.duration(-delta)) de moins que prévu"
    }

    // MARK: Idle

    private var idle: some View {
        VStack(spacing: Space.xxl) {
            EmptyState(
                symbol: "record.circle",
                title: "Aucune séance en cours",
                message: upcoming.isEmpty
                    ? "Démarrez une séance depuis la journée pour mesurer sa durée réelle."
                    : "Démarrez la prochaine séance ci-dessous, ou depuis la journée."
            )
            .frame(maxHeight: 260)

            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: Space.md) {
                    SectionLabel(text: "À venir aujourd'hui")
                    VStack(spacing: 0) {
                        ForEach(upcoming) { item in
                            HStack(spacing: Space.lg) {
                                Text(CadenceFormat.time(item.consultation.scheduledStart))
                                    .font(Typo.bodyNumeric)
                                    .foregroundStyle(Ink.textSecondary)
                                    .frame(width: 46, alignment: .leading)
                                if let patient = item.patient {
                                    PatientAvatar(patient: patient, size: 24)
                                } else {
                                    UnknownAvatar(size: 24)
                                }
                                Text(item.title)
                                    .font(Typo.bodyStrong)
                                    .foregroundStyle(Ink.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: Space.md)
                                Button("Démarrer") {
                                    model.startSession(item)
                                }
                                .buttonStyle(.cadence(.primary, size: .small))
                            }
                            .padding(.horizontal, Space.lg)
                            .padding(.vertical, Space.md)
                            if item.id != upcoming.last?.id { Hairline().padding(.leading, Space.lg) }
                        }
                    }
                    .cadenceCard(padding: 0)
                }
                .frame(maxWidth: 560)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var upcoming: [DayItem] {
        model.dayItems
            .filter { !$0.consultation.status.isResolved && $0.consultation.status != .inProgress }
            .prefix(4)
            .map { $0 }
    }

    // MARK: Notes

    private func loadNotes(_ item: DayItem) {
        guard loadedNotesFor != item.id else { return }
        loadedNotesFor = item.id
        notes = item.consultation.notes ?? ""
    }

    /// Saves a second after typing stops, rather than on every keystroke: each save
    /// is a transaction and a refresh, and neither belongs on the keyboard's path.
    private func scheduleNoteSave(_ item: DayItem) {
        noteSaver?.cancel()
        let text = notes
        noteSaver = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            model.saveSessionNotes(text, for: item.consultation)
        }
    }

    private func flushNotes() {
        noteSaver?.cancel()
        noteSaver = nil
        guard let id = loadedNotesFor,
              let item = model.dayItems.first(where: { $0.id == id }) else { return }
        model.saveSessionNotes(notes, for: item.consultation)
    }

    /// `mm:ss`, or `h:mm:ss` once a session runs past the hour.
    static func clock(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
