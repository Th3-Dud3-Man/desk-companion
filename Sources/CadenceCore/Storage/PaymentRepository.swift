import Foundation

extension CadenceStore {

    // MARK: - Reading

    public func payments(forPatient patientID: UUID, limit: Int = 200) throws -> [Payment] {
        try database.query(
            "SELECT * FROM payment WHERE patient_id = ? ORDER BY paid_at DESC, rowid DESC LIMIT ?;",
            [.uuid(patientID), .int(limit)]
        ).compactMap(Self.decodePayment)
    }

    public func payments(in range: DateRange) throws -> [Payment] {
        try database.query(
            "SELECT * FROM payment WHERE paid_at >= ? AND paid_at < ? ORDER BY paid_at ASC;",
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
                                 paid_at, note, is_demo, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                consultation_id = excluded.consultation_id,
                patient_id = excluded.patient_id,
                amount_cents = excluded.amount_cents,
                currency = excluded.currency,
                method = excluded.method,
                paid_at = excluded.paid_at,
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
            note: row.string("note"),
            isDemo: row.bool("is_demo"),
            createdAt: row.date("created_at") ?? paidAt
        )
    }
}
