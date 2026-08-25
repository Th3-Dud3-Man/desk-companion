import Foundation

/// Practice-wide preferences. Small, flat, and stored as key/value pairs so adding
/// one never requires a migration.
public struct PracticeSettings: Hashable, Sendable {
    public var practiceName: String
    public var currencyCode: String
    /// Tariff proposed when a patient has no history at all.
    public var defaultAmountCents: Int
    public var defaultMethodID: String
    public var defaultDurationMinutes: Int
    public var paymentMethods: [PaymentMethod]
    /// Calendar window pulled on each synchronisation.
    public var syncPastDays: Int
    public var syncFutureDays: Int
    /// First and last hour shown on the day rail.
    public var dayStartHour: Int
    public var dayEndHour: Int
    public var hasCompletedOnboarding: Bool
    /// Blur the window content when the app loses focus, for consultations in the room.
    public var privacyBlurWhenInactive: Bool

    public static let `default` = PracticeSettings(
        practiceName: "Mon cabinet",
        currencyCode: "EUR",
        defaultAmountCents: 6_000,
        defaultMethodID: PaymentMethod.card.id,
        defaultDurationMinutes: 50,
        paymentMethods: PaymentMethod.builtIn,
        syncPastDays: 60,
        syncFutureDays: 180,
        dayStartHour: 8,
        dayEndHour: 20,
        hasCompletedOnboarding: false,
        privacyBlurWhenInactive: false
    )

    /// Enabled methods in display order; never empty, so the payment strip always
    /// has something to offer.
    public var activeMethods: [PaymentMethod] {
        let enabled = paymentMethods.filter(\.isEnabled)
        return enabled.isEmpty ? PaymentMethod.builtIn : enabled
    }

    public func method(withID id: String) -> PaymentMethod? {
        paymentMethods.first { $0.id == id }
    }

    /// Human label for a stored method id, degrading gracefully if the method was
    /// deleted after payments referenced it.
    public func methodLabel(_ id: String) -> String {
        method(withID: id)?.label ?? id.capitalized
    }

    public func methodSymbol(_ id: String) -> String {
        method(withID: id)?.symbol ?? "creditcard"
    }
}

extension CadenceStore {

    enum SettingKey {
        static let practiceName = "practice.name"
        static let currency = "practice.currency"
        static let defaultAmount = "practice.defaultAmountCents"
        static let defaultMethod = "practice.defaultMethod"
        static let defaultDuration = "practice.defaultDurationMinutes"
        static let paymentMethods = "practice.paymentMethods"
        static let syncPastDays = "sync.pastDays"
        static let syncFutureDays = "sync.futureDays"
        static let dayStartHour = "ui.dayStartHour"
        static let dayEndHour = "ui.dayEndHour"
        static let onboardingDone = "app.onboardingCompleted"
        static let privacyBlur = "privacy.blurWhenInactive"
        static let lastBackupDay = "backup.lastDay"
        static let schemaSeeded = "app.settingsSeeded"
    }

    // MARK: Raw access

    public func rawSetting(_ key: String) throws -> String? {
        try database.query("SELECT value FROM setting WHERE key = ?;", [.text(key)]).first?.string("value")
    }

    public func setRawSetting(_ key: String, _ value: String?) throws {
        if let value {
            try database.run(
                "INSERT INTO setting (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;",
                [.text(key), .text(value)]
            )
        } else {
            try database.run("DELETE FROM setting WHERE key = ?;", [.text(key)])
        }
    }

    func seedDefaultSettingsIfNeeded() throws {
        guard try rawSetting(SettingKey.schemaSeeded) == nil else { return }
        try write {
            try saveSettings(.default)
            try setRawSetting(SettingKey.schemaSeeded, "1")
        }
    }

    // MARK: Typed access

    public func settings() throws -> PracticeSettings {
        var settings = PracticeSettings.default
        let rows = try database.query("SELECT key, value FROM setting;")
        var values: [String: String] = [:]
        for row in rows {
            if let key = row.string("key"), let value = row.string("value") { values[key] = value }
        }

        settings.practiceName = values[SettingKey.practiceName] ?? settings.practiceName
        settings.currencyCode = values[SettingKey.currency] ?? settings.currencyCode
        settings.defaultAmountCents = values[SettingKey.defaultAmount].flatMap(Int.init) ?? settings.defaultAmountCents
        settings.defaultMethodID = values[SettingKey.defaultMethod] ?? settings.defaultMethodID
        settings.defaultDurationMinutes = values[SettingKey.defaultDuration].flatMap(Int.init) ?? settings.defaultDurationMinutes
        settings.syncPastDays = values[SettingKey.syncPastDays].flatMap(Int.init) ?? settings.syncPastDays
        settings.syncFutureDays = values[SettingKey.syncFutureDays].flatMap(Int.init) ?? settings.syncFutureDays
        settings.dayStartHour = values[SettingKey.dayStartHour].flatMap(Int.init) ?? settings.dayStartHour
        settings.dayEndHour = values[SettingKey.dayEndHour].flatMap(Int.init) ?? settings.dayEndHour
        settings.hasCompletedOnboarding = (values[SettingKey.onboardingDone] as NSString?)?.boolValue ?? false
        settings.privacyBlurWhenInactive = (values[SettingKey.privacyBlur] as NSString?)?.boolValue ?? false

        if let encoded = values[SettingKey.paymentMethods],
           let data = encoded.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([PaymentMethod].self, from: data),
           !decoded.isEmpty {
            settings.paymentMethods = decoded
        }
        return settings
    }

    public func saveSettings(_ settings: PracticeSettings) throws {
        try write {
            try setRawSetting(SettingKey.practiceName, settings.practiceName)
            try setRawSetting(SettingKey.currency, settings.currencyCode)
            try setRawSetting(SettingKey.defaultAmount, String(settings.defaultAmountCents))
            try setRawSetting(SettingKey.defaultMethod, settings.defaultMethodID)
            try setRawSetting(SettingKey.defaultDuration, String(settings.defaultDurationMinutes))
            try setRawSetting(SettingKey.syncPastDays, String(settings.syncPastDays))
            try setRawSetting(SettingKey.syncFutureDays, String(settings.syncFutureDays))
            try setRawSetting(SettingKey.dayStartHour, String(settings.dayStartHour))
            try setRawSetting(SettingKey.dayEndHour, String(settings.dayEndHour))
            try setRawSetting(SettingKey.onboardingDone, settings.hasCompletedOnboarding ? "true" : "false")
            try setRawSetting(SettingKey.privacyBlur, settings.privacyBlurWhenInactive ? "true" : "false")
            if let data = try? JSONEncoder().encode(settings.paymentMethods),
               let encoded = String(data: data, encoding: .utf8) {
                try setRawSetting(SettingKey.paymentMethods, encoded)
            }
        }
    }
}
