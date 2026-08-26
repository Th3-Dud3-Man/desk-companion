import SwiftUI
import CadenceCore

struct PaletteResult: Identifiable {
    let id: String
    let group: String
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil
    let run: () -> Void
}

/// ⌘K. One field that reaches every patient, every appointment, every payment and
/// every action in the application, so nothing is ever more than a few keystrokes
/// away — and so the menus never have to grow to accommodate rarely used commands.
@MainActor
struct CommandPaletteView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                field
                if !results.isEmpty {
                    Hairline()
                    resultList
                } else if !query.isEmpty {
                    Hairline()
                    Text("Aucun résultat pour « \(query) »")
                        .font(Typo.caption)
                        .foregroundStyle(Ink.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.xl)
                }
            }
            .frame(width: 560)
            .cadenceFloating(Radius.sheet)
            .padding(.top, 110)
        }
        .onAppear { isFieldFocused = true }
        .onChange(of: query) { _, _ in highlighted = 0 }
    }

    private var field: some View {
        HStack(spacing: Space.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Ink.textTertiary)
            TextField("Rechercher un patient, une consultation, une action…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isFieldFocused)
                .onSubmit(runHighlighted)
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.escape) { close(); return .handled }
            KeyHint(keys: "⎋")
        }
        .padding(.horizontal, Space.xl)
        .frame(height: 52)
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(grouped) { section in
                        Text(section.id)
                            .font(Typo.sectionLabel)
                            .tracking(0.7)
                            .textCase(.uppercase)
                            .foregroundStyle(Ink.textTertiary)
                            .padding(.horizontal, Space.xl)
                            .padding(.top, Space.lg)
                            .padding(.bottom, Space.xs)

                        ForEach(section.items) { result in
                            let index = results.firstIndex { $0.id == result.id } ?? 0
                            PaletteRow(result: result, isHighlighted: index == highlighted)
                                .id(result.id)
                                .onTapGesture { result.run(); close() }
                                .onHover { if $0 { highlighted = index } }
                        }
                    }
                }
                .padding(.bottom, Space.md)
                .onChange(of: highlighted) { _, index in
                    guard results.indices.contains(index) else { return }
                    withAnimation(Motion.respectful(Motion.instant, reduceMotion: reduceMotion)) {
                        proxy.scrollTo(results[index].id, anchor: .bottom)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxHeight: 380)
        }
    }

    // MARK: Behaviour

    private func move(_ offset: Int) {
        guard !results.isEmpty else { return }
        highlighted = min(max(0, highlighted + offset), results.count - 1)
    }

    private func runHighlighted() {
        guard results.indices.contains(highlighted) else { return }
        results[highlighted].run()
        close()
    }

    private func close() {
        model.isCommandPaletteVisible = false
        query = ""
    }

    struct ResultGroup: Identifiable {
        let id: String
        let items: [PaletteResult]
    }

    private var grouped: [ResultGroup] {
        var order: [String] = []
        var buckets: [String: [PaletteResult]] = [:]
        for result in results {
            if buckets[result.group] == nil { order.append(result.group) }
            buckets[result.group, default: []].append(result)
        }
        return order.map { ResultGroup(id: $0, items: buckets[$0] ?? []) }
    }

    // MARK: Results

    private var results: [PaletteResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var output = actions(matching: trimmed)
        if !trimmed.isEmpty {
            output += patients(matching: trimmed)
            output += consultations(matching: trimmed)
            output += payments(matching: trimmed)
        }
        return output
    }

    private func actions(matching query: String) -> [PaletteResult] {
        let all: [PaletteResult] = [
            PaletteResult(id: "action.today", group: "Aller à", symbol: "sun.horizon",
                          title: "Aujourd'hui", trailing: "⌘1") { model.destination = .today; model.goToToday() },
            PaletteResult(id: "action.agenda", group: "Aller à", symbol: "calendar",
                          title: "Agenda", trailing: "⌘2") { model.destination = .agenda },
            PaletteResult(id: "action.patients", group: "Aller à", symbol: "person.2",
                          title: "Patients", trailing: "⌘3") { model.destination = .patients },
            PaletteResult(id: "action.finances", group: "Aller à", symbol: "chart.bar",
                          title: "Finances", trailing: "⌘4") { model.destination = .finances },
            PaletteResult(id: "action.settings", group: "Aller à", symbol: "gearshape",
                          title: "Réglages", trailing: "⌘,") { model.destination = .settings },

            PaletteResult(id: "action.newConsultation", group: "Actions", symbol: "plus.circle",
                          title: "Nouveau rendez-vous", trailing: "⌘N") { model.requestNewConsultation(at: nil) },
            PaletteResult(id: "action.newPatient", group: "Actions", symbol: "person.badge.plus",
                          title: "Nouveau patient", trailing: "⇧⌘N") { model.requestNewPatient() },
            PaletteResult(id: "action.sync", group: "Actions", symbol: "arrow.triangle.2.circlepath",
                          title: "Synchroniser l'agenda", trailing: "⌘R") {
                Task { await model.calendarSync.synchronise(trigger: .userAction) }
            },
            PaletteResult(id: "action.exportPayments", group: "Actions", symbol: "square.and.arrow.up",
                          title: "Exporter les paiements du mois") { model.requestExport(.payments) },
            PaletteResult(id: "action.report", group: "Actions", symbol: "doc.richtext",
                          title: "Rapport d'activité en PDF") { model.requestReport() },
            PaletteResult(id: "action.shortcuts", group: "Actions", symbol: "keyboard",
                          title: "Raccourcis clavier", trailing: "⌘/") { model.present(.shortcuts) },
        ]
        guard !query.isEmpty else { return all }
        return all.filter { TextNormaliser.matches($0.title, query: query) }
    }

    private func patients(matching query: String) -> [PaletteResult] {
        let matches = (try? model.store.searchPatients(query, includeArchived: true)) ?? []
        return matches.prefix(6).map { patient in
            let profile = try? model.store.profile(forPatient: patient.id, settings: model.settings)
            return PaletteResult(
                id: "patient.\(patient.id)",
                group: "Patients",
                symbol: "person.crop.circle",
                title: patient.displayName,
                subtitle: profile.map { subtitle(for: $0) },
                trailing: profile.map { $0.advice.primary.money.formatted() }
            ) {
                model.destination = .patients
                model.selectPatient(patient.id)
            }
        }
    }

    private func subtitle(for profile: PatientProfile) -> String {
        var parts: [String] = ["\(profile.attended) consultation\(profile.attended > 1 ? "s" : "")"]
        if let last = profile.lastSeen { parts.append("vu \(CadenceFormat.since(last))") }
        if profile.advice.isHabit { parts.append("habitude établie") }
        return parts.joined(separator: " · ")
    }

    private func consultations(matching query: String) -> [PaletteResult] {
        let window = DateRange(
            start: Calendar.cadence.date(byAdding: .day, value: -120, to: Date()) ?? Date(),
            end: Calendar.cadence.date(byAdding: .day, value: 120, to: Date()) ?? Date()
        )
        let all = (try? model.store.consultations(in: window)) ?? []
        let patientsByID = (try? model.store.patients(ids: Array(Set(all.compactMap(\.patientID))))) ?? [:]

        let matching = all.filter { consultation in
            let name = consultation.patientID.flatMap { patientsByID[$0]?.displayName } ?? consultation.title
            return TextNormaliser.matches(name, query: query)
                || TextNormaliser.matches(CadenceFormat.numericDate(consultation.scheduledStart), query: query)
        }

        return matching
            .sorted { abs($0.scheduledStart.timeIntervalSinceNow) < abs($1.scheduledStart.timeIntervalSinceNow) }
            .prefix(5)
            .map { consultation in
                let name = consultation.patientID.flatMap { patientsByID[$0]?.displayName } ?? consultation.title
                return PaletteResult(
                    id: "consultation.\(consultation.id)",
                    group: "Rendez-vous",
                    symbol: "calendar.day.timeline.left",
                    title: "\(CadenceFormat.dayShort(consultation.scheduledStart)) · \(CadenceFormat.time(consultation.scheduledStart)) — \(name)",
                    subtitle: consultation.status.label,
                    trailing: nil
                ) {
                    model.select(day: consultation.scheduledStart)
                    model.destination = .today
                }
            }
    }
}

@MainActor
extension CommandPaletteView {

    /// Payments are searchable by patient and by amount, so "90" answers
    /// "who paid ninety euros, and when?" without leaving the keyboard.
    fileprivate func payments(matching query: String) -> [PaletteResult] {
        let window = DateRange(
            start: Calendar.cadence.date(byAdding: .month, value: -18, to: Date()) ?? Date(),
            end: Calendar.cadence.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        )
        let all = (try? model.store.payments(in: window)) ?? []
        guard !all.isEmpty else { return [] }
        let names = (try? model.store.patients(ids: Array(Set(all.map(\.patientID))))) ?? [:]

        let digits = query.filter { $0.isNumber }
        let matching = all.filter { payment in
            let name = names[payment.patientID]?.displayName ?? ""
            if TextNormaliser.matches(name, query: query) { return true }
            if TextNormaliser.matches(CadenceFormat.numericDate(payment.paidAt), query: query) { return true }
            // An amount typed without decimals should find 70 € as readily as 70,00 €.
            if !digits.isEmpty, String(payment.amountCents / 100).hasPrefix(digits) { return true }
            return false
        }

        return matching
            .sorted { $0.paidAt > $1.paidAt }
            .prefix(4)
            .map { payment in
                let name = names[payment.patientID]?.displayName ?? "Patient supprimé"
                return PaletteResult(
                    id: "payment.\(payment.id)",
                    group: "Paiements",
                    symbol: model.settings.methodSymbol(payment.methodID),
                    title: "\(payment.money.formatted()) · \(name)",
                    subtitle: "\(model.settings.methodLabel(payment.methodID)) · \(CadenceFormat.numericDate(payment.paidAt))"
                ) {
                    model.select(day: payment.paidAt)
                    model.destination = .today
                }
            }
    }
}

@MainActor
private struct PaletteRow: View {
    let result: PaletteResult
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: Space.lg) {
            Image(systemName: result.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHighlighted ? Ink.accent : Ink.textSecondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(Typo.body)
                    .foregroundStyle(Ink.textPrimary)
                    .lineLimit(1)
                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(Typo.caption)
                        .foregroundStyle(Ink.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Space.md)
            if let trailing = result.trailing {
                Text(trailing)
                    .font(Typo.captionNumeric)
                    .foregroundStyle(Ink.textTertiary)
            }
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.md)
        .background(isHighlighted ? Ink.accentSoft : Color.clear)
        .contentShape(Rectangle())
    }
}
