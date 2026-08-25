import Foundation

/// An amount of money, always stored in minor units (cents).
///
/// Currency is never represented as a floating point number anywhere in Cadence:
/// `0.1 + 0.2 != 0.3` is not an acceptable property for a payment ledger.
public struct Money: Hashable, Comparable, Codable, Sendable {
    public var cents: Int
    public var currencyCode: String

    public init(cents: Int, currencyCode: String = "EUR") {
        self.cents = cents
        self.currencyCode = currencyCode
    }

    public static func euros(_ amount: Double) -> Money {
        Money(cents: Int((amount * 100).rounded()))
    }

    public static let zero = Money(cents: 0)

    public var isZero: Bool { cents == 0 }
    public var majorUnits: Double { Double(cents) / 100 }

    public static func < (lhs: Money, rhs: Money) -> Bool { lhs.cents < rhs.cents }

    public static func + (lhs: Money, rhs: Money) -> Money {
        Money(cents: lhs.cents + rhs.cents, currencyCode: lhs.currencyCode)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        Money(cents: lhs.cents - rhs.cents, currencyCode: lhs.currencyCode)
    }

    /// Localised currency string, e.g. `70 €`. Whole amounts drop the decimals —
    /// a column of `70 €` reads faster than a column of `70,00 €`, and consultations
    /// are almost always priced in round numbers.
    public func formatted(locale: Locale = Locale(identifier: "fr_FR"), forceDecimals: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currencyCode
        let hasFraction = cents % 100 != 0
        formatter.minimumFractionDigits = (hasFraction || forceDecimals) ? 2 : 0
        formatter.maximumFractionDigits = (hasFraction || forceDecimals) ? 2 : 0
        return formatter.string(from: NSNumber(value: majorUnits)) ?? "\(majorUnits)"
    }

    /// Plain decimal form for CSV files, using a comma as the French decimal mark.
    public var csvValue: String {
        let sign = cents < 0 ? "-" : ""
        let absolute = abs(cents)
        return "\(sign)\(absolute / 100),\(String(format: "%02d", absolute % 100))"
    }
}
