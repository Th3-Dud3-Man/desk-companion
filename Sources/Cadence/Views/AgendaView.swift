import SwiftUI
import CadenceCore

/// The week at a glance.
///
/// Seven columns of what is actually booked, rather than a proportional grid: a
/// psychologist's week is a list of slots, and the empty stretches between them do
/// not need to be drawn to scale to be understood.
struct AgendaView: View {
    @EnvironmentObject private var model: AppModel
    @State private var anchor = Date()
    @State private var consultationsByDay: [Date: [Consultation]] = [:]
    @State private var patientsByID: [UUID: Patient] = [:]
    @State private var paidConsultationIDs: Set<UUID> = []

    private var week: DateRange { .week(containing: anchor) }

    private var days: [Date] {
        (0..<7).compactMap { Calendar.cadence.date(byAdding: .day, value: $0, to: week.start) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView {
                HStack(alignment: .top, spacing: Space.lg) {
                    ForEach(days, id: \.self) { day in
                        DayColumn(
                            day: day,
                            consultations: consultationsByDay[day] ?? [],
                            patientsByID: patientsByID,
                            paidConsultationIDs: paidConsultationIDs,
                            isToday: Calendar.cadence.isDateInToday(day)
                        )
                    }
                }
                .padding(Space.xxl)
            }
            .scrollContentBackground(.hidden)
        }
        .onAppear { anchor = model.selectedDay; load() }
        .onChange(of: anchor) { _, _ in load() }
        .onChange(of: model.undoRevision) { _, _ in load() }
        .onChange(of: model.selectedDay) { _, newValue in
            if !week.contains(newValue) { anchor = newValue }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: 1) {
                Text(weekTitle)
                    .font(Typo.display)
                    .foregroundStyle(Ink.textPrimary)
                Text(summary)
                    .font(Typo.body)
                    .foregroundStyle(Ink.textSecondary)
            }
            Spacer(minLength: Space.lg)
            HStack(spacing: Space.xs) {
                Button { shift(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.cadence(.ghost, size: .small))
                Button("Cette semaine") { anchor = Date() }
                    .buttonStyle(.cadence(.secondary, size: .small))
                    .disabled(week.contains(Date()))
                Button { shift(1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.cadence(.ghost, size: .small))
            }
        }
        .padding(.horizontal, Space.xxl)
        .padding(.vertical, Space.xl)
    }

    private var weekTitle: String {
        let end = Calendar.cadence.date(byAdding: .day, value: 6, to: week.start) ?? week.start
        return "\(CadenceFormat.dayShort(week.start)) – \(CadenceFormat.dayShort(end))"
    }

    private var summary: String {
        let all = consultationsByDay.values.flatMap { $0 }.filter { $0.status != .cancelled }
        let attended = all.filter { $0.status == .attended }.count
        if all.isEmpty { return "Aucun rendez-vous cette semaine" }
        return "\(all.count) rendez-vous · \(attended) honoré\(attended > 1 ? "s" : "")"
    }

    private func shift(_ weeks: Int) {
        guard let next = Calendar.cadence.date(byAdding: .weekOfYear, value: weeks, to: anchor) else { return }
        anchor = next
    }

    private func load() {
        do {
            let consultations = try model.store.consultations(in: week)
            var grouped: [Date: [Consultation]] = [:]
            for consultation in consultations {
                let day = Calendar.cadence.startOfDay(for: consultation.scheduledStart)
                grouped[day, default: []].append(consultation)
            }
            consultationsByDay = grouped
            patientsByID = try model.store.patients(ids: Array(Set(consultations.compactMap(\.patientID))))
            paidConsultationIDs = Set(try model.store.paymentsByConsultation(in: week).keys)
        } catch {
            model.report(error)
        }
    }
}

private struct DayColumn: View {
    @EnvironmentObject private var model: AppModel
    let day: Date
    let consultations: [Consultation]
    let patientsByID: [UUID: Patient]
    let paidConsultationIDs: Set<UUID>
    let isToday: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Button {
                model.select(day: day)
                model.destination = .today
            } label: {
                HStack(spacing: Space.sm) {
                    Text(CadenceFormat.weekdayCompact(day).capitalizedFirst)
                        .font(Typo.captionStrong)
                        .foregroundStyle(isToday ? Ink.accent : Ink.textSecondary)
                    Spacer(minLength: 0)
                    if !active.isEmpty {
                        Text("\(active.count)")
                            .font(Typo.captionNumeric)
                            .foregroundStyle(Ink.textTertiary)
                    }
                }
                .padding(.horizontal, Space.md)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                        .fill(isToday ? Ink.accentSoft : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ouvrir \(CadenceFormat.dayLong(day))")

            if active.isEmpty {
                Text("—")
                    .font(Typo.caption)
                    .foregroundStyle(Ink.textTertiary.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Space.lg)
            } else {
                VStack(spacing: Space.sm) {
                    ForEach(active) { consultation in
                        AgendaCard(
                            consultation: consultation,
                            patient: consultation.patientID.flatMap { patientsByID[$0] },
                            isPaid: paidConsultationIDs.contains(consultation.id)
                        )
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var active: [Consultation] {
        consultations.filter { $0.status != .cancelled }
    }
}

private struct AgendaCard: View {
    @EnvironmentObject private var model: AppModel
    let consultation: Consultation
    let patient: Patient?
    let isPaid: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            model.select(day: consultation.scheduledStart)
            model.destination = .today
        } label: {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.sm) {
                    Text(CadenceFormat.time(consultation.scheduledStart))
                        .font(Typo.captionNumeric)
                        .foregroundStyle(Ink.textSecondary)
                    Spacer(minLength: 0)
                    Image(systemName: ConsultationStatusPresentation.of(consultation.status).symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ConsultationStatusPresentation.of(consultation.status).foreground)
                }
                Text(patient?.displayName ?? consultation.title)
                    .font(Typo.captionStrong)
                    .foregroundStyle(Ink.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if consultation.status == .attended {
                    Text(isPaid ? "réglé" : "à régler")
                        .font(Typo.caption)
                        .foregroundStyle(isPaid ? Ink.accent : Ink.warning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(isHovered ? Ink.surfaceHover : Ink.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Ink.hairline, lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(ConsultationStatusPresentation.of(consultation.status).foreground.opacity(0.7))
                    .frame(width: 2.5)
                    .padding(.vertical, Space.sm)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Modifier…") { model.present(.editConsultation(consultation)) }
            Button("Supprimer") { model.deleteConsultation(consultation) }
        }
    }
}
