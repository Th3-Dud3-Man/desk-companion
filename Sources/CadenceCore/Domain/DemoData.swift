import Foundation

/// Installs a believable, self-contained sample practice.
///
/// Every row it writes carries `is_demo = 1`, so the whole set can be removed in one
/// action and can never be confused with real work. The generator is fully
/// deterministic — no randomness — so the same command always produces the same
/// practice, which makes it usable as a fixture in tests as well as a demo.
public enum DemoData {

    private struct Persona {
        let name: String
        let email: String?
        let phone: String?
        /// Days between appointments.
        let period: Int
        let weekday: Int          // 1 = Sunday … 7 = Saturday
        let hour: Int
        let minute: Int
        let amountCents: Int
        let methodID: String
        /// Indices of past sessions the patient missed.
        let missedSessions: Set<Int>
        /// Occasional different payments: session index → (amount, method).
        let exceptions: [Int: (Int, String)]
        let notes: String?
    }

    private static let personas: [Persona] = [
        Persona(name: "Jean Dupont", email: "jean.dupont@example.com", phone: "06 12 34 56 78",
                period: 7, weekday: 3, hour: 14, minute: 0,
                amountCents: 7_000, methodID: "card", missedSessions: [], exceptions: [:],
                notes: "Suivi hebdomadaire. Préfère le début d'après-midi."),

        Persona(name: "Camille Moreau", email: "camille.moreau@example.com", phone: "06 22 11 44 90",
                period: 7, weekday: 2, hour: 9, minute: 0,
                amountCents: 7_000, methodID: "card", missedSessions: [4], exceptions: [2: (7_000, "cash")],
                notes: nil),

        Persona(name: "Sofia Benali", email: nil, phone: "07 88 21 63 05",
                period: 14, weekday: 5, hour: 11, minute: 0,
                amountCents: 6_000, methodID: "cash", missedSessions: [], exceptions: [:],
                notes: "Séance toutes les deux semaines."),

        Persona(name: "Marc Lefèvre", email: "m.lefevre@example.com", phone: nil,
                period: 28, weekday: 4, hour: 18, minute: 30,
                amountCents: 8_000, methodID: "cheque", missedSessions: [1], exceptions: [:],
                notes: nil),

        Persona(name: "Élodie Rousseau", email: "elodie.r@example.com", phone: "06 45 78 12 33",
                period: 7, weekday: 6, hour: 16, minute: 0,
                amountCents: 7_500, methodID: "card",
                missedSessions: [], exceptions: [1: (7_000, "card"), 3: (7_500, "cash"), 5: (7_000, "cheque")],
                notes: "Montant variable selon la durée."),

        Persona(name: "Nadia Haddad", email: nil, phone: nil,
                period: 14, weekday: 3, hour: 10, minute: 0,
                amountCents: 9_000, methodID: "transfer", missedSessions: [], exceptions: [:],
                notes: "Règle par virement en fin de mois."),

        Persona(name: "Thomas Girard", email: "t.girard@example.com", phone: "06 90 55 32 18",
                period: 7, weekday: 5, hour: 17, minute: 0,
                amountCents: 7_000, methodID: "cash", missedSessions: [], exceptions: [:],
                notes: "Nouveau patient."),

        Persona(name: "Paul Mercier", email: nil, phone: "06 74 09 88 21",
                period: 30, weekday: 2, hour: 15, minute: 0,
                amountCents: 6_500, methodID: "cash", missedSessions: [2], exceptions: [:],
                notes: "Suivi espacé."),
    ]

    /// How many past sessions each persona gets, in order. Thomas is deliberately new.
    private static let sessionCounts = [10, 9, 6, 4, 8, 5, 1, 3]

    /// Writes the sample practice. Returns how many patients were created.
    @discardableResult
    public static func install(into store: CadenceStore, now: Date = Date(), calendar: Calendar = .cadence) throws -> Int {
        let settings = try store.settings()
        let duration = TimeInterval(settings.defaultDurationMinutes * 60)

        try store.write {
            for (index, persona) in personas.enumerated() {
                let patient = try store.createPatient(
                    displayName: persona.name,
                    firstName: persona.name.split(separator: " ").first.map(String.init),
                    lastName: persona.name.split(separator: " ").dropFirst().joined(separator: " "),
                    email: persona.email,
                    phone: persona.phone,
                    notes: persona.notes,
                    isDemo: true
                )
                if persona.name == "Paul Mercier" {
                    try store.setPatientArchived(patient.id, archived: true)
                }

                let count = sessionCounts[index % sessionCounts.count]
                try installHistory(
                    for: persona, patient: patient, sessions: count,
                    duration: duration, now: now, calendar: calendar, store: store
                )
            }

            try installUpcoming(store: store, duration: duration, now: now, calendar: calendar)
            try store.log(.demoDataInstalled, entityType: "app", entityID: nil,
                          detail: "\(personas.count) patients de démonstration")
        }
        return personas.count
    }

    // MARK: - Past sessions

    private static func installHistory(
        for persona: Persona,
        patient: Patient,
        sessions: Int,
        duration: TimeInterval,
        now: Date,
        calendar: Calendar,
        store: CadenceStore
    ) throws {
        // Session 0 is the most recent past appointment; higher indices go further back.
        for session in 0..<sessions {
            let daysBack = persona.period * (session + 1)
            guard let day = calendar.date(byAdding: .day, value: -daysBack, to: now),
                  let start = calendar.date(
                    bySettingHour: persona.hour, minute: persona.minute, second: 0, of: day
                  ) else { continue }

            let missed = persona.missedSessions.contains(session)
            let end = start.addingTimeInterval(duration)

            var consultation = Consultation(
                patientID: patient.id,
                title: persona.name,
                source: .manual,
                scheduledStart: start,
                scheduledEnd: end,
                status: missed ? .absent : .attended,
                syncState: .local,
                isDemo: true,
                createdAt: start,
                updatedAt: start
            )

            // A handful of sessions carry real measured times, so the "durée réelle"
            // statistics have something honest to work with.
            if !missed, session % 3 == 0 {
                consultation.actualStart = start.addingTimeInterval(Double((session % 4) - 1) * 60)
                consultation.actualEnd = consultation.actualStart?.addingTimeInterval(duration + Double((session % 3) - 1) * 120)
            }

            try store.upsertConsultationRow(consultation)

            guard !missed else { continue }

            let (amount, method) = persona.exceptions[session] ?? (persona.amountCents, persona.methodID)
            _ = try store.recordPayment(
                consultationID: consultation.id,
                patientID: patient.id,
                amountCents: amount,
                methodID: method,
                paidAt: end,
                isDemo: true
            )
        }
    }

    // MARK: - Today and the days ahead

    /// Builds a plausible working day around `now`: the morning already dealt with,
    /// the afternoon still to come.
    private static func installUpcoming(
        store: CadenceStore,
        duration: TimeInterval,
        now: Date,
        calendar: Calendar
    ) throws {
        let patients = try store.allPatients(includeArchived: false).filter(\.isDemo)
        guard !patients.isEmpty else { return }

        let today = calendar.startOfDay(for: now)
        // A full but realistic day: a morning block, lunch, an afternoon block.
        let slots: [(hour: Int, minute: Int)] = [(9, 0), (10, 0), (11, 0), (14, 0), (15, 0), (16, 0), (17, 0)]

        for (index, slot) in slots.enumerated() {
            guard let start = calendar.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: today) else { continue }
            let end = start.addingTimeInterval(duration)
            let patient = patients[index % patients.count]

            // Anything already over is resolved; one of them was a no-show.
            var status: ConsultationStatus = .scheduled
            if end <= now {
                status = (index == 1) ? .absent : .attended
            } else if start <= now && now < end {
                status = .inProgress
            }

            let consultation = Consultation(
                patientID: patient.id,
                title: patient.displayName,
                source: .manual,
                scheduledStart: start,
                scheduledEnd: end,
                actualStart: status == .inProgress ? start : nil,
                status: status,
                syncState: .local,
                isDemo: true
            )
            try store.upsertConsultationRow(consultation)

            if status == .attended {
                // Leave the last finished session unpaid so "reste à traiter" is not empty.
                let leaveUnpaid = (index == 2)
                if !leaveUnpaid {
                    let advice = HabitEngine.advise(
                        payments: try store.payments(forPatient: patient.id),
                        patient: patient,
                        settings: try store.settings(),
                        now: now
                    )
                    _ = try store.recordPayment(
                        consultationID: consultation.id,
                        patientID: patient.id,
                        amountCents: advice.primary.amountCents,
                        methodID: advice.primary.methodID,
                        paidAt: end,
                        isDemo: true
                    )
                }
            }
        }

        // The next few days, so the agenda is not a wall of empty space.
        for dayOffset in 1...5 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            guard weekday != 1 && weekday != 7 else { continue }   // no weekend clinic

            for (index, slot) in [(10, 0), (11, 0), (15, 0), (16, 0)].enumerated() {
                guard let start = calendar.date(bySettingHour: slot.0, minute: slot.1, second: 0, of: day) else { continue }
                let patient = patients[(dayOffset * 3 + index) % patients.count]
                let consultation = Consultation(
                    patientID: patient.id,
                    title: patient.displayName,
                    source: .manual,
                    scheduledStart: start,
                    scheduledEnd: start.addingTimeInterval(duration),
                    status: (dayOffset == 1 && index == 0) ? .confirmed : .scheduled,
                    syncState: .local,
                    isDemo: true
                )
                try store.upsertConsultationRow(consultation)
            }
        }
    }

    // MARK: - Removal

    /// Counts of what `remove` would delete, so the confirmation can be specific.
    public static func inventory(in store: CadenceStore) throws -> (patients: Int, consultations: Int, payments: Int) {
        (
            try store.database.scalarInt("SELECT COUNT(*) AS value FROM patient WHERE is_demo = 1;"),
            try store.database.scalarInt("SELECT COUNT(*) AS value FROM consultation WHERE is_demo = 1;"),
            try store.database.scalarInt("SELECT COUNT(*) AS value FROM payment WHERE is_demo = 1;")
        )
    }

    public static func isInstalled(in store: CadenceStore) throws -> Bool {
        try store.database.scalarInt("SELECT COUNT(*) AS value FROM patient WHERE is_demo = 1;") > 0
    }

    /// Removes every demonstration row and nothing else.
    public static func remove(from store: CadenceStore) throws {
        try store.write {
            try store.database.run("DELETE FROM payment WHERE is_demo = 1;")
            try store.database.run("DELETE FROM consultation WHERE is_demo = 1;")
            try store.database.run("DELETE FROM patient WHERE is_demo = 1;")
            try store.log(.demoDataRemoved, entityType: "app", entityID: nil,
                          detail: "Données de démonstration supprimées")
        }
    }
}
