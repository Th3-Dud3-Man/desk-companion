import SwiftUI
import CadenceCore

/// The end-of-month check.
///
/// Every transaction agreed in the period, narrowed to one payment method and one
/// settlement state, with the total for exactly what is on screen. This is where
/// you go through the transfers one by one, tick off what has landed, and delete
/// the line you entered twice.
@MainActor
struct TransactionsView: View {
    @EnvironmentObject private var model: AppModel

    let range: DateRange
    let periodLabel: String

    @State private var methodFilter: String?
    @State private var settlementFilter: CadenceStore.SettlementFilter = .all
    @State private var order: CadenceStore.LedgerOrder = .dateDescending
    @State private var rows: [Payment] = []
    @State private var methodsUsed: [String] = []
    @State private var patientNames: [UUID: String] = [:]
    @State private var confirmingDeletion: Payment?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            filters
            totals
            table
        }
        .onAppear(perform: load)
        .onChange(of: range) { _, _ in load() }
        .onChange(of: methodFilter) { _, _ in load() }
        .onChange(of: settlementFilter) { _, _ in load() }
        .onChange(of: order) { _, _ in load() }
        .onChange(of: model.dataRevision) { _, _ in load() }
        .alert(
            "Supprimer cette transaction ?",
            isPresented: Binding(
                get: { confirmingDeletion != nil },
                set: { if !$0 { confirmingDeletion = nil } }
            )
        ) {
            Button("Annuler", role: .cancel) { confirmingDeletion = nil }
            Button("Supprimer", role: .destructive) {
                if let payment = confirmingDeletion {
                    model.deletePayment(payment, patientName: patientNames[payment.patientID] ?? "")
                }
                confirmingDeletion = nil
            }
        } message: {
            if let payment = confirmingDeletion {
                Text("\(payment.money.formatted()) en \(model.settings.methodLabel(payment.methodID)) du \(CadenceFormat.numericDate(payment.paidAt)), pour \(patientNames[payment.patientID] ?? "ce patient"). La suppression est annulable avec ⌘Z.")
            }
        }
    }

    // MARK: Filters

    private var filters: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                FilterChip(title: "Tous les moyens", isActive: methodFilter == nil) { methodFilter = nil }
                ForEach(methodsUsed, id: \.self) { method in
                    FilterChip(
                        title: model.settings.methodLabel(method),
                        symbol: model.settings.methodSymbol(method),
                        isActive: methodFilter == method
                    ) {
                        methodFilter = methodFilter == method ? nil : method
                    }
                }
                Spacer(minLength: Space.md)
            }

            HStack(spacing: Space.md) {
                Picker("", selection: $settlementFilter) {
                    ForEach(CadenceStore.SettlementFilter.allCases, id: \.self) { state in
                        Text(state.label).tag(state)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)

                Menu {
                    ForEach(CadenceStore.LedgerOrder.allCases, id: \.self) { option in
                        Button(option.label) { order = option }
                    }
                } label: {
                    HStack(spacing: Space.sm) {
                        Image(systemName: "arrow.up.arrow.down").font(.system(size: 10, weight: .medium))
                        Text(order.label).font(Typo.caption)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer(minLength: Space.md)

                if settleableRows.count > 1 {
                    Button("Marquer les \(settleableRows.count) comme reçus") { settleAllVisible() }
                        .buttonStyle(.cadence(.secondary, size: .small))
                        .help("Encaisse d'un coup tout ce qui est affiché — annulable avec ⌘Z")
                }
            }
        }
    }

    // MARK: Totals

    private var totals: some View {
        HStack(spacing: Space.xxl) {
            totalItem("Total affiché", filteredTotal, Ink.textPrimary)
            totalItem("Reçu", settledTotal, Ink.accent)
            if pendingTotal > 0 { totalItem("En attente", pendingTotal, Ink.warning) }
            Spacer(minLength: 0)
            Text("\(rows.count) transaction\(rows.count > 1 ? "s" : "")")
                .font(Typo.caption)
                .foregroundStyle(Ink.textTertiary)
        }
        .cadenceCard(padding: Space.xl)
    }

    private func totalItem(_ label: String, _ cents: Int, _ tone: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            SectionLabel(text: label)
            Text(Money(cents: cents, currencyCode: model.settings.currencyCode).formatted())
                .font(Typo.titleNumeric)
                .foregroundStyle(tone)
        }
    }

    private var filteredTotal: Int { rows.reduce(0) { $0 + $1.amountCents } }
    private var settledTotal: Int { rows.filter { !$0.isPending }.reduce(0) { $0 + $1.amountCents } }
    private var pendingTotal: Int { rows.filter(\.isPending).reduce(0) { $0 + $1.amountCents } }
    private var settleableRows: [Payment] { rows.filter(\.isPending) }

    // MARK: Table

    @ViewBuilder
    private var table: some View {
        if rows.isEmpty {
            EmptyState(
                symbol: "tray",
                title: "Aucune transaction",
                message: methodFilter == nil && settlementFilter == .all
                    ? "Aucun paiement enregistré sur \(periodLabel.lowercased())."
                    : "Aucun paiement ne correspond à ce filtre."
            )
            .frame(height: 200)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: Space.lg) {
                    Text("").frame(width: 24)
                    Text("Date").frame(width: 78, alignment: .leading)
                    Text("Patient").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Moyen").frame(width: 110, alignment: .leading)
                    Text("Règlement").frame(width: 118, alignment: .leading)
                    Text("Montant").frame(width: 84, alignment: .trailing)
                    Text("").frame(width: 24)
                }
                .font(Typo.sectionLabel)
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(Ink.textTertiary)
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.md)
                .background(Ink.surfaceSunken)

                ForEach(rows) { payment in
                    TransactionRow(
                        payment: payment,
                        patientName: patientNames[payment.patientID] ?? "Patient supprimé",
                        settings: model.settings,
                        onToggleSettlement: {
                            payment.isPending ? model.settle(payment) : model.unsettle(payment)
                        },
                        onEdit: {
                            model.present(.editPayment(payment,
                                                       patientName: patientNames[payment.patientID] ?? ""))
                        },
                        onDelete: { confirmingDeletion = payment }
                    )
                    if payment.id != rows.last?.id { Hairline() }
                }
            }
            .cadenceCard(padding: 0)
        }
    }

    // MARK: Behaviour

    private func load() {
        do {
            rows = try model.store.ledger(
                in: range, methodID: methodFilter, settlement: settlementFilter, order: order
            )
            methodsUsed = try model.store.methodsUsed(in: range)
            patientNames = try model.store
                .patients(ids: Array(Set(rows.map(\.patientID))))
                .mapValues(\.displayName)
            // A filter that no longer matches anything in the period would strand the
            // user on an empty screen with no way to tell why.
            if let methodFilter, !methodsUsed.contains(methodFilter) { self.methodFilter = nil }
        } catch {
            model.report(error)
        }
    }

    private func settleAllVisible() {
        for payment in settleableRows { model.settle(payment) }
    }
}

@MainActor
private struct FilterChip: View {
    let title: String
    var symbol: String?
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .medium))
                }
                Text(title).font(Typo.captionStrong)
            }
            .foregroundStyle(isActive ? Ink.textOnAccent : Ink.textSecondary)
            .padding(.horizontal, Space.lg)
            .frame(height: 26)
            .background(
                Capsule().fill(isActive ? Ink.accent : (isHovering ? Ink.surfaceHover : Ink.surface))
            )
            .overlay(Capsule().strokeBorder(isActive ? .clear : Ink.hairlineStrong, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

@MainActor
private struct TransactionRow: View {
    let payment: Payment
    let patientName: String
    let settings: PracticeSettings
    let onToggleSettlement: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Space.lg) {
            SettlementTick(isSettled: !payment.isPending, action: onToggleSettlement)
                .frame(width: 24)

            Text(CadenceFormat.numericDate(payment.paidAt))
                .font(Typo.bodyNumeric)
                .foregroundStyle(Ink.textSecondary)
                .frame(width: 78, alignment: .leading)

            Text(patientName)
                .font(Typo.bodyStrong)
                .foregroundStyle(Ink.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Space.sm) {
                Image(systemName: settings.methodSymbol(payment.methodID))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Ink.textTertiary)
                Text(settings.methodLabel(payment.methodID))
                    .font(Typo.body)
                    .foregroundStyle(Ink.textSecondary)
            }
            .frame(width: 110, alignment: .leading)

            settlementLabel
                .frame(width: 118, alignment: .leading)

            Text(payment.money.formatted())
                .font(Typo.headingNumeric)
                .foregroundStyle(Ink.textPrimary)
                .frame(width: 84, alignment: .trailing)

            Menu {
                Button(payment.isPending ? "Marquer comme reçu" : "Remettre en attente", action: onToggleSettlement)
                Button("Modifier…", action: onEdit)
                Divider()
                Button("Supprimer…", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
            .opacity(isHovering ? 1 : 0.35)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .background(isHovering ? Ink.surfaceHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(payment.isPending ? "Marquer comme reçu" : "Remettre en attente", action: onToggleSettlement)
            Button("Modifier…", action: onEdit)
            Button("Supprimer…", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var settlementLabel: some View {
        if payment.isPending {
            let days = payment.daysOutstanding() ?? 0
            Text(days > 0 ? "en attente · \(days) j" : "en attente")
                .font(Typo.caption)
                .foregroundStyle(Ink.warning)
        } else if let settledAt = payment.settledAt {
            Text("reçu le \(CadenceFormat.numericDate(settledAt))")
                .font(Typo.caption)
                .foregroundStyle(Ink.textTertiary)
        }
    }
}
