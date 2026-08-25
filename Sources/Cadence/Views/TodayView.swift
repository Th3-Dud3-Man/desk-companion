import SwiftUI
import CadenceCore

/// The screen the day is spent in.
///
/// It is a chronological rail rather than a proportional calendar grid: a scaled
/// grid spends most of its height on the gaps between appointments, and a working
/// day should fit on one screen. Everything the user needs to *do* is reachable
/// without leaving this view.
@MainActor
struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selection: UUID?
    @State private var hovered: UUID?
    @FocusState private var isRailFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let showsRail = geometry.size.width >= 1_000

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    DayHeader()
                    Hairline()
                    dayBody
                }
                .frame(maxWidth: .infinity)

                if showsRail {
                    Hairline().frame(width: 1).frame(maxHeight: .infinity)
                    DaySummaryRail()
                        .frame(width: Metrics.inspectorWidth)
                }
            }
        }
        .onAppear { isRailFocused = true }
        .onChange(of: model.selectedDay) { _, _ in selection = nil }
    }

    // MARK: Body

    @ViewBuilder
    private var dayBody: some View {
        if model.dayItems.isEmpty {
            EmptyState(
                symbol: model.isShowingToday ? "cup.and.saucer" : "calendar",
                title: model.isShowingToday ? "Rien de prévu aujourd'hui" : "Rien de prévu ce jour-là",
                message: model.calendarSync.hasEnabledCalendars
                    ? "Les rendez-vous de vos calendriers apparaîtront ici automatiquement."
                    : "Connectez votre agenda dans les Réglages, ou ajoutez un rendez-vous à la main.",
                actionTitle: "Nouveau rendez-vous",
                action: { model.requestNewConsultation(at: nil) }
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        ForEach(Array(model.dayItems.enumerated()), id: \.element.id) { index, item in
                            if shouldShowNowSeparator(before: index) {
                                NowSeparator(now: model.now)
                                    .id("now")
                            }
                            ConsultationRow(
                                item: item,
                                isSelected: selection == item.id,
                                isHovered: hovered == item.id,
                                isNext: model.nextItem?.id == item.id,
                                onSelect: { selection = item.id }
                            )
                            .id(item.id)
                            .onHover { inside in
                                hovered = inside ? item.id : (hovered == item.id ? nil : hovered)
                            }
                            if index < model.dayItems.count - 1 {
                                Hairline().padding(.leading, Metrics.timeGutter + Space.xl)
                            }
                        }
                    }
                    .padding(.vertical, Space.md)
                }
                .scrollContentBackground(.hidden)
                .focusable()
                .focusEffectDisabled()
                .focused($isRailFocused)
                .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                .onKeyPress(.escape) { selection = nil; return .handled }
                .onKeyPress(.return) { confirmSelection(); return .handled }
                .onKeyPress(KeyEquivalent("p")) { applyToSelection(.attended); return .handled }
                .onKeyPress(KeyEquivalent("a")) { applyToSelection(.absent); return .handled }
                .onAppear {
                    guard model.isShowingToday else { return }
                    let target = model.runningItem?.id ?? model.nextItem?.id
                    if let target {
                        DispatchQueue.main.async {
                            withAnimation(Motion.respectful(Motion.standard, reduceMotion: reduceMotion)) {
                                proxy.scrollTo(target, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The "maintenant" line sits between the last finished slot and the next one.
    private func shouldShowNowSeparator(before index: Int) -> Bool {
        guard model.isShowingToday else { return false }
        let item = model.dayItems[index]
        guard item.consultation.scheduledStart > model.now else { return false }
        if index == 0 { return true }
        return model.dayItems[index - 1].consultation.scheduledStart <= model.now
    }

    // MARK: Keyboard

    private func moveSelection(_ offset: Int) {
        guard !model.dayItems.isEmpty else { return }
        guard let current = selection,
              let index = model.dayItems.firstIndex(where: { $0.id == current }) else {
            selection = offset > 0 ? model.dayItems.first?.id : model.dayItems.last?.id
            return
        }
        let next = min(max(0, index + offset), model.dayItems.count - 1)
        selection = model.dayItems[next].id
    }

    private func applyToSelection(_ status: ConsultationStatus) {
        guard let id = selection, let item = model.dayItems.first(where: { $0.id == id }) else { return }
        model.mark(status, for: item)
    }

    /// Enter records the suggested payment when one is waiting, otherwise marks present.
    private func confirmSelection() {
        guard let id = selection, let item = model.dayItems.first(where: { $0.id == id }) else { return }
        if item.awaitsPayment {
            model.recordPayment(item.advice.primary, for: item)
        } else if !item.consultation.status.isResolved {
            model.mark(.attended, for: item)
        }
    }
}

// MARK: - Header

@MainActor
struct DayHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(CadenceFormat.dayLong(model.selectedDay).capitalizedFirst)
                        .font(Typo.display)
                        .foregroundStyle(Ink.textPrimary)
                    Text(headline)
                        .font(Typo.body)
                        .foregroundStyle(headlineTone)
                        .contentTransition(.opacity)
                }

                Spacer(minLength: Space.lg)

                HStack(spacing: Space.xs) {
                    Button { model.shiftDay(by: -1) } label: {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.cadence(.ghost, size: .small))
                    .help("Jour précédent (⌥⌘←)")

                    Button("Aujourd'hui") { model.goToToday() }
                        .buttonStyle(.cadence(.secondary, size: .small))
                        .disabled(model.isShowingToday)
                        .help("Revenir à aujourd'hui (⌘T)")

                    Button { model.shiftDay(by: 1) } label: {
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.cadence(.ghost, size: .small))
                    .help("Jour suivant (⌥⌘→)")

                    Divider().frame(height: 16).padding(.horizontal, Space.xs)

                    Button {
                        model.requestNewConsultation(at: nil)
                    } label: {
                        Label("Rendez-vous", systemImage: "plus")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.cadence(.primary, size: .small))
                    .help("Nouveau rendez-vous (⌘N)")
                }
            }

            if !model.unassignedToday.isEmpty {
                UnassignedBanner(items: model.unassignedToday)
            }

            if let failure = model.failure {
                InlineError(message: failure, retryTitle: "Fermer") { model.failure = nil }
            }
        }
        .padding(.horizontal, Space.xxl)
        .padding(.top, Space.xl)
        .padding(.bottom, Space.lg)
    }

    /// One line that answers "where am I in my day?".
    private var headline: String {
        guard model.isShowingToday else {
            let count = model.dayItems.filter { $0.consultation.status != .cancelled }.count
            return count == 0 ? "Aucun rendez-vous" : "\(count) rendez-vous"
        }
        if let running = model.runningItem {
            let elapsed = running.consultation.actualStart.map { CadenceFormat.duration(model.now.timeIntervalSince($0)) }
            return "En consultation · \(running.title)" + (elapsed.map { " · depuis \($0)" } ?? "")
        }
        if let next = model.nextItem {
            return "Prochain · \(CadenceFormat.time(next.consultation.scheduledStart)) \(next.title) · \(CadenceFormat.relative(next.consultation.scheduledStart, from: model.now))"
        }
        let waiting = model.itemsAwaitingPayment.count
        if waiting > 0 { return "Journée terminée · \(waiting) paiement(s) à enregistrer" }
        return model.dayItems.isEmpty ? "Aucun rendez-vous" : "Journée terminée"
    }

    private var headlineTone: Color {
        if model.runningItem != nil { return Ink.accent }
        if model.isShowingToday && !model.itemsAwaitingPayment.isEmpty && model.nextItem == nil { return Ink.warning }
        return Ink.textSecondary
    }
}

/// Calendar events that could not be attached to a patient. Shown, never ignored.
@MainActor
struct UnassignedBanner: View {
    @EnvironmentObject private var model: AppModel
    let items: [DayItem]

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Ink.warning)
            Text(items.count == 1
                 ? "Un rendez-vous n'est rattaché à aucun patient."
                 : "\(items.count) rendez-vous ne sont rattachés à aucun patient.")
                .font(Typo.caption)
                .foregroundStyle(Ink.textPrimary)
            Spacer(minLength: Space.md)
            Text("Utilisez le menu ··· sur la ligne concernée")
                .font(Typo.caption)
                .foregroundStyle(Ink.textTertiary)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Ink.warningSoft))
    }
}

/// The line that separates what has happened from what is still to come.
@MainActor
struct NowSeparator: View {
    let now: Date

    var body: some View {
        HStack(spacing: Space.md) {
            Text(CadenceFormat.time(now))
                .font(Typo.captionNumeric)
                .foregroundStyle(Ink.accent)
                .frame(width: Metrics.timeGutter, alignment: .leading)
            Circle()
                .fill(Ink.accent)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(Ink.accent.opacity(0.35))
                .frame(height: 1)
        }
        .padding(.horizontal, Space.xxl)
        .padding(.vertical, Space.md)
        .accessibilityLabel("Maintenant, \(CadenceFormat.time(now))")
    }
}

extension String {
    /// French dates come back lowercase from the formatter; headings want a capital.
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
