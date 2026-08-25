import Foundation

/// Text folding used for search and for matching calendar titles to patients.
///
/// Every comparison in Cadence goes through here, so `Chloé Müller`, `chloe muller`
/// and `CHLOE   MULLER` are the same string as far as the application is concerned.
public enum TextNormaliser {

    /// Lowercased, unaccented, punctuation-free, single-spaced.
    public static func normalise(_ input: String) -> String {
        let folded = input.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                                   locale: Locale(identifier: "fr_FR"))
        var output = String()
        output.reserveCapacity(folded.count)
        var lastWasSpace = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                output.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                output.append(" ")
                lastWasSpace = true
            }
        }
        while output.hasSuffix(" ") { output.removeLast() }
        return output
    }

    /// Words that appear in appointment titles but say nothing about *who* it is.
    private static let noiseWords: Set<String> = [
        "rdv", "rv", "seance", "séance", "consultation", "consult", "cs", "psy",
        "patient", "patiente", "suivi", "entretien", "bilan", "visio", "tel",
        "telephone", "cabinet", "rendez", "vous", "rendezvous", "th", "therapie",
        "1ere", "1er", "premiere", "premier", "nouveau", "nouvelle"
    ]

    /// Strips scheduling noise from a calendar event title to leave, as far as
    /// possible, just the person's name.
    ///
    /// `"RDV Séance - Jean Dupont (visio)"` → `"jean dupont"`
    public static func candidateName(fromEventTitle title: String) -> String {
        // Drop anything in brackets: they hold rooms, notes, "(visio)", "(annulé)"…
        var stripped = ""
        var depth = 0
        for character in title {
            if character == "(" || character == "[" || character == "{" {
                depth += 1
            } else if character == ")" || character == "]" || character == "}" {
                depth = max(0, depth - 1)
            } else if depth == 0 {
                stripped.append(character)
            }
        }

        let normalised = normalise(stripped)
        let words = normalised.split(separator: " ").map(String.init)

        // Remove noise words and bare numbers (times, durations, session counts).
        let meaningful = words.filter { word in
            if noiseWords.contains(word) { return false }
            if word.allSatisfy(\.isNumber) { return false }
            if word.count == 1 { return false }
            return true
        }

        return meaningful.isEmpty ? normalised : meaningful.joined(separator: " ")
    }

    /// Sub-string match on the folded forms.
    public static func matches(_ haystack: String, query: String) -> Bool {
        let normalisedQuery = normalise(query)
        guard !normalisedQuery.isEmpty else { return true }
        return normalise(haystack).contains(normalisedQuery)
    }

    /// Initials match, so `jd` finds `Jean Dupont`.
    public static func matchesInitials(_ haystack: String, query: String) -> Bool {
        let normalisedQuery = normalise(query).replacingOccurrences(of: " ", with: "")
        guard normalisedQuery.count >= 2 else { return false }
        let initials = normalise(haystack)
            .split(separator: " ")
            .compactMap { $0.first }
            .map(String.init)
            .joined()
        return initials.hasPrefix(normalisedQuery)
    }

    /// Levenshtein distance, iterative with two rows.
    public static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs.unicodeScalars)
        let b = Array(rhs.unicodeScalars)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// Similarity in `0...1`, where 1 means identical after normalisation.
    public static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let a = normalise(lhs)
        let b = normalise(rhs)
        if a == b { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        let distance = editDistance(a, b)
        let longest = max(a.count, b.count)
        return 1 - (Double(distance) / Double(longest))
    }
}
