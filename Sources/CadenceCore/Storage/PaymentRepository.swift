import Foundation

extension CadenceStore {

    // MARK: - Reading

    public func payments(forPatient patientID: UUID, limit: Int = 200) throws -> [Payment] {
        try database.query(
            "SELECT * FROM payment WHERE patient_id = ? ORDER BY paid_at DESC, rowid DESC LIMIT ?;",
            [.uuid(patientID), .int(limit)]
        ).compactMap(Self.decodePayment)
    }

    /// Payments *agreed* in the period, whether or not the money has arrived.
    public func payments(in range: DateRange) throws -> [Payment] {
        try database.query(
            "SELECT * FROM payment WHERE paid_at >= ? AND paid_at < ? ORDER BY paid_at ASC;",
            [.int(range.startEpoch), .int(range.endEpoch)]
        ).compactMap(Self.decodePayment)
    }

    /// Payments *received* in the period. A transfer agreed in June and banked in
    /// August is June's consultation and August's takings, which is what a ledger
    /// should say.
    public func settledPayments(in range: DateRange) throws -> [Payment] {
        try database.query(
            "SELECT * FROM payment WHERE settled_at >= ? AND settled_at < ? ORDER BY settled_at ASC;",
            [.int(range.startEpoch), .int(range.endEpoch)]
        ).compactMap(Self.decodePayment)
    }

    public func payments(forConsultation id: UUID) throws -> [Payment] {
        try database.query(
            "SELECT * FROM payment WHERE consultation_id = ? ORDER BY paid_at ASC;",
            [.uuid(id)]
        ).compactMap(Self.decodePayment)
    }

    /// Payments indexed by consultation, for rendering a whole day in one query.
    public func paymentsByConsultation(in range: DateRange) throws -> [UUID: [Payment]] {
        let rows = try database.query(
            """
            SELECT p.* FROM payment p
            JOIN consultation c ON c.id = p.consultation_id
            WHERE c.scheduled_start >= ? AND c.scheduled_start < ?;
            """,
            [.int(range.startEpoch), .int(range.endEpoch)]
        )
        var result: [UUID: [Payment]] = [:]
        for payment in rows.compactMap(Self.decodePayment) {
            guard let consultationID = payment.consultationID else { continue }
            result[consultationID, default: []].append(payment)
        }
        return result
    }

    public func payment(id: UUID) throws -> Payment? {
        try database.query("SELECT * FROM payment WHERE id = ?;", [.uuid(id)])
            .first.flatMap(Self.decodePayment)
    }

    /// Which settlement states a ledger query should return.
    public enum SettlementFilter: String, CaseIterable, Sendable {
        case all, settled, pending

        public var label: String {
            switch self {
            case .all: return "Tous"
            case .settled: return "Reçus"
            case .pending: return "En attente"
            }
        }
    }

    /// How a ledger listing is ordered.
    public enum LedgerOrder: String, CaseIterable, Sendable {
        case dateDescending, dateAscending, amountDescending, amountAscending

        public var label: String {
            switch self {
            case .dateDescending: return "Date (récent → ancien)"
            case .dateAscending: return "Date (ancien → récent)"
            case .amountDescending: return "Montant (élevé → faible)"
            case .amountAscending: return "Montant (faible → élevé)"
            }
        }

        var clause: String {
            switch self {
            case .dateDescending: return "paid_at DESC, rowid DESC"
            case .dateAscending: return "paid_at ASC, rowid ASC"
            case .amountDescending: return "amount_cents DESC, paid_at DESC"
            case .amountAscending: return "amount_cents ASC, paid_at DESC"
            }
        }
    }

    /// The ledger behind the end-of-month check: every transaction agreed in the
    /// period, narrowed to one payment method and one settlement state.
    ///
    /// Keyed on when the payment was agreed, not when it arrived, so going through
    /// "all the transfers in August" shows the ones agreed in August whether or not
    /// the bank has caught up.
    public func ledger(
        in range: DateRange,
        methodID: String? = nil,
        settlement: SettlementFilter = .all,
        order: LedgerOrder = .dateDescending
    ) throws -> [Payment] {
        var sql = "SELECT * FROM payment WHERE paid_at >= ? AND paid_at < ?"
        var parameters: [SQLValue] = [.int(range.startEpoch), .int(range.endEpoch)]

        if let methodID {
            sql += " AND method = ?"
            parameters.append(.text(methodID))
        }
        switch settlement {
        case .all: break
        case .settled: sql += " AND settled_at IS NOT NULL"
        case .pending: sql += " AND settled_at IS NULL"
        }
        sql += " ORDER BY \(order.clause);"

        return try database.query(sql, parameters).compactMap(Self.decodePayment)
    }

    /// The payment methods that actually occur in the period, so the filter only
    /// offers what is there.
    public func methodsUsed(in range: DateRange) throws -> [String] {
        try database.query(
            """
            SELECT method, COUNT(*) AS n FROM payment
            WHERE paid_at >= ? AND paid_at < ?
            GROUP BY method ORDER BY n DESC;
            """,
            [.int(range.startEpoch), .int(range.endEpoch)]
        ).compactMap { $0.string("method") }
    }

    /// Everything still owed, oldest first — the list the user ticks off.
    public func pendingPayments(limit: Int = 200) throws -> [Payment] {
        try database.query(
            "SELECT * FROM payment WHERE settled_at IS NULL ORDER BY paid_at ASC LIMIT ?;",
            [.int(limit)]
        ).compactMap(Self.decodePayment)
    }

    /// Total still owed, across all time. Drives the badge in the sidebar.
    public func outstandingTotal() throws -> Int {
        try database.scalarInt(
            "SELECT COALESCE(SUM(amount_cents), 0) AS value FROM payment WHERE settled_at IS NULL;"
        )
    }

    public func outstandingCount() throws -> Int {
        try database.scalarInt("SELECT COUNT(*) AS value FROM payment WHERE settled_at IS NULL;")
    }

    /// Marks the money as arrived.
    public func settlePayment(_ id: UUID, at date: Date = Date()) throws {
        try write {
            try database.run(
                "UPDATE payment SET settled_at = ? WHERE id = ?;", [.date(date), .uuid(id)]
            )
            let payment = try payment(id: id)
            try log(.paymentSettled, entityType: "payment", entityID: id,
                    detail: payment.map { "\($0.money.formatted()) · \($0.methodID)" } ?? "")
        }
    }

    /// Puts it back on the outstanding list — for a mistaken tick, or a cheque returned.
    public func unsettlePayment(_ id: UUID) throws {
        try write {
            try database.run("UPDATE payment SET settled_at = NULL WHERE id = ?;", [.uuid(id)])
            let payment = try payment(id: id)
            try log(.paymentUnsettled, entityType: "payment", entityID: id,
                    detail: payment.map { "\($0.money.formatted()) · \($0.methodID)" } ?? "")
        }
    }

    public func paymentCount(forPatient patientID: UUID) throws -> Int {
        try database.scalarInt("SELECT COUNT(*) AS value FROM payment WHERE patient_id = ?;", [.uuid(patientID)])
    }

    public func totalCollected(forPatient patientID: UUID) throws -> Int {
        try database.scalarInt(
            "SELECT COALESCE(SUM(amount_cents), 0) AS value FROM payment WHERE patient_id = ?;",
            [.uuid(patientID)]
        )
    }

    // MARK: - Writing

    @discardableResult
    public func recordPayment(
        consultationID: UUID?,
        patientID: UUID,
        amountCents: Int,
        methodID: String,
        currencyCode: String = "EUR",
        paidAt: Date = Date(),
        isSettled: Bool = true,
        note: String? = nil,
        isDemo: Bool = false
    ) throws -> Payment {
        let payment = Payment(
            consultationID: consultationID,
            patientID: patientID,
            amountCents: amountCents,
            currencyCode: currencyCode,
            methodID: methodID,
            paidAt: paidAt,
            settledAt: isSettled ? paidAt : nil,
            note: note,
            isDemo: isDemo
        )
        try write {
            try insert(payment)
            let amount = Money(cents: amountCents, currencyCode: currencyCode).formatted()
            try log(.paymentRecorded, entityType: "payment", entityID: payment.id,
                    detail: "\(amount) · \(methodID)")
        }
        return payment
    }

    /// Records a payment the caller has already composed (a different amount, a
    /// late-cancellation charge). Same audit entry as the one-click path.
    @discardableResult
    public func recordPayment(_ payment: Payment) throws -> Payment {
        try write {
            try insert(payment)
            try log(.paymentRecorded, entityType: "payment", entityID: payment.id,
                    detail: "\(payment.money.formatted()) · \(payment.methodID)")
        }
        return payment
    }

    /// Re-inserts a payment exactly as given. Used by undo.
    public func restorePayment(_ payment: Payment) throws {
        try write { try insert(payment) }
    }

    public func updatePayment(_ payment: Payment) throws {
        try write {
            try insert(payment)
            try log(.paymentUpdated, entityType: "payment", entityID: payment.id,
                    detail: "\(payment.money.formatted()) · \(payment.methodID)")
        }
    }

    public func deletePayment(_ id: UUID) throws {
        try write {
            let payment = try payment(id: id)
            try database.run("DELETE FROM payment WHERE id = ?;", [.uuid(id)])
            try log(.paymentDeleted, entityType: "payment", entityID: id,
                    detail: payment.map { "\($0.money.formatted()) · \($0.methodID)" } ?? "")
        }
    }

    /// Deletes without logging — the undo path, which must not pollute the trail.
    public func deletePaymentSilently(_ id: UUID) throws {
        try database.run("DELETE FROM payment WHERE id = ?;", [.uuid(id)])
    }

    // MARK: - Internals

    private func insert(_ payment: Payment) throws {
        try database.run(
            """
            INSERT INTO payment (id, consultation_id, patient_id, amount_cents, currency, method,
                                 paid_at, settled_at, note, is_demo, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                consultation_id = excluded.consultation_id,
                patient_id = excluded.patient_id,
                amount_cents = excluded.amount_cents,
                currency = excluded.currency,
                method = excluded.method,
                paid_at = excluded.paid_at,
                settled_at = excluded.settled_at,
                note = excluded.note,
                is_demo = excluded.is_demo;
            """,
            [
                .uuid(payment.id),
                .optionalUUID(payment.consultationID),
                .uuid(payment.patientID),
                .int(payment.amountCents),
                .text(payment.currencyCode),
                .text(payment.methodID),
                .date(payment.paidAt),
                .optionalDate(payment.settledAt),
                .optionalText(payment.note),
                .bool(payment.isDemo),
                .date(payment.createdAt),
            ]
        )
    }

    static func decodePayment(_ row: Row) -> Payment? {
        guard let id = row.uuid("id"),
              let patientID = row.uuid("patient_id"),
              let paidAt = row.date("paid_at") else { return nil }
        return Payment(
            id: id,
            consultationID: row.uuid("consultation_id"),
            patientID: patientID,
            amountCents: row.intValue("amount_cents"),
            currencyCode: row.stringValue("currency", default: "EUR"),
            methodID: row.stringValue("method", default: "other"),
            paidAt: paidAt,
            settledAt: row.date("settled_at"),
            note: row.string("note"),
            isDemo: row.bool("is_demo"),
            createdAt: row.date("created_at") ?? paidAt
        )
    }
}
