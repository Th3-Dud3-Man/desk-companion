import Foundation

/// Outcome of trying to attach a calendar event to a patient.
public struct PatientMatch: Sendable {
    public enum Confidence: Sendable, Equatable {
        /// The exact wording has been seen before and confirmed — link it silently.
        case remembered
        /// The name matches closely enough to link without asking.
        case strong(score: Double)
        /// Plausible, but the user should confirm.
        case suggested(score: Double)
        /// Nothing convincing.
        case none

        public var linksAutomatically: Bool {
            switch self {
            case .remembered, .strong: return true
            case .suggested, .none: return false
            }
        }
    }

    public let patientID: UUID?
    public let confidence: Confidence
    /// Ranked candidates for the "associer à…" menu, best first.
    public let candidates: [UUID]
}

/// Attaches calendar event titles to patients.
///
/// The first pass is an exact lookup on remembered spellings, which is what makes a
/// weekly appointment match by itself forever after the first reconciliation. Only
/// when that misses does it fall back to fuzzy name comparison — and it refuses to
/// link automatically when two patients are similarly close, because silently
/// filing a session under the wrong person is far worse than asking.
public enum PatientMatcher {

    /// Above this, and clearly ahead of the runner-up, Cadence links on its own.
    public static let automaticThreshold = 0.90
    /// Above this, the patient is offered as a suggestion.
    public static let suggestionThreshold = 0.62
    /// The leader must beat the runner-up by this much to be trusted.
    public static let ambiguityMargin = 0.08

    public static func match(
        title: String,
        patients: [Patient],
        rememberedPatientID: UUID?
    ) -> PatientMatch {
        if let rememberedPatientID {
            return PatientMatch(patientID: rememberedPatientID, confidence: .remembered, candidates: [rememberedPatientID])
        }

        let candidateName = TextNormaliser.candidateName(fromEventTitle: title)
        guard candidateName.count >= 3, !patients.isEmpty else {
            return PatientMatch(patientID: nil, confidence: .none, candidates: [])
        }

        let scored = patients
            .map { (patient: $0, score: score(candidateName: candidateName, patient: $0)) }
            .filter { $0.score >= suggestionThreshold }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.patient.sortKey < rhs.patient.sortKey
            }

        guard let best = scored.first else {
            return PatientMatch(patientID: nil, confidence: .none, candidates: [])
        }

        let runnerUp = scored.dropFirst().first?.score ?? 0
        let isUnambiguous = best.score - runnerUp >= ambiguityMargin

        let confidence: PatientMatch.Confidence
        if best.score >= automaticThreshold && isUnambiguous {
            confidence = .strong(score: best.score)
        } else {
            confidence = .suggested(score: best.score)
        }

        return PatientMatch(
            patientID: confidence.linksAutomatically ? best.patient.id : nil,
            confidence: confidence,
            candidates: scored.prefix(5).map(\.patient.id)
        )
    }

    /// Similarity between a cleaned-up event title and a patient, taking the best of
    /// the whole name and the surname alone — calendars often hold only one of them.
    static func score(candidateName: String, patient: Patient) -> Double {
        var best = TextNormaliser.similarity(candidateName, patient.displayName)

        // A title that contains the full name outright is a match, whatever else it says.
        let normalisedPatient = TextNormaliser.normalise(patient.displayName)
        if !normalisedPatient.isEmpty, candidateName.contains(normalisedPatient) {
            best = max(best, 0.97)
        }

        // Same words in a different order: "Dupont Jean" vs "Jean Dupont".
        let candidateWords = Set(candidateName.split(separator: " ").map(String.init))
        let patientWords = Set(normalisedPatient.split(separator: " ").map(String.init))
        if !patientWords.isEmpty, patientWords == candidateWords {
            best = max(best, 0.98)
        } else if !patientWords.isEmpty, patientWords.isSubset(of: candidateWords) {
            best = max(best, 0.93)
        }

        if let lastName = patient.lastName, lastName.count >= 3 {
            best = max(best, TextNormaliser.similarity(candidateName, lastName) * 0.95)
        }
        return best
    }
}

extension CadenceStore {

    /// Convenience wrapper that consults the remembered-alias table first.
    public func matchPatient(forTitle title: String, among patients: [Patient]? = nil) throws -> PatientMatch {
        let remembered = try patientID(forAlias: title)
        let pool = try patients ?? allPatients(includeArchived: true)
        return PatientMatcher.match(title: title, patients: pool, rememberedPatientID: remembered)
    }
}
