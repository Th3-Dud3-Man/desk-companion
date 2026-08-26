import XCTest
@testable import CadenceCoreTests

fileprivate extension AcceptanceScenarioTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__AcceptanceScenarioTests = [
        ("testScenario01_CreateAPatient", testScenario01_CreateAPatient),
        ("testScenario02_CreateAnAppointment", testScenario02_CreateAnAppointment),
        ("testScenario02b_ImportingTheSameEventTwiceDoesNotDuplicate", testScenario02b_ImportingTheSameEventTwiceDoesNotDuplicate),
        ("testScenario03_MarkPresent", testScenario03_MarkPresent),
        ("testScenario04_RecordSeventyEurosByCard", testScenario04_RecordSeventyEurosByCard),
        ("testScenario05And06_DataSurvivesClosingAndReopening", testScenario05And06_DataSurvivesClosingAndReopening),
        ("testScenario07_TheHabitEmergesFromRepeatedPayments", testScenario07_TheHabitEmergesFromRepeatedPayments),
        ("testScenario08_AnAbsenceNeverAsksForAPayment", testScenario08_AnAbsenceNeverAsksForAPayment),
        ("testScenario09_StatisticsMatchTheRecordedData", testScenario09_StatisticsMatchTheRecordedData),
        ("testScenario09b_UnpaidAttendedConsultationsAreCounted", testScenario09b_UnpaidAttendedConsultationsAreCounted),
        ("testScenario10_EverythingWorksWithoutANetwork", testScenario10_EverythingWorksWithoutANetwork)
    ]
}

fileprivate extension BackupTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__BackupTests = [
        ("testOldSnapshotsArePruned", testOldSnapshotsArePruned),
        ("testOnlyOneSnapshotPerDay", testOnlyOneSnapshotPerDay),
        ("testRestoreSwapsTheLiveDatabaseAndKeepsASafetyCopy", testRestoreSwapsTheLiveDatabaseAndKeepsASafetyCopy),
        ("testSnapshotIsAUsableDatabase", testSnapshotIsAUsableDatabase)
    ]
}

fileprivate extension CalendarSyncTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__CalendarSyncTests = [
        ("testARenamedEventUpdatesTheTitle", testARenamedEventUpdatesTheTitle),
        ("testAnAbsenceIsAlsoProtected", testAnAbsenceIsAlsoProtected),
        ("testDeletingAnEventWithRecordedWorkKeepsTheRecord", testDeletingAnEventWithRecordedWorkKeepsTheRecord),
        ("testDeletingAnUntouchedEventRemovesItQuietly", testDeletingAnUntouchedEventRemovesItQuietly),
        ("testEventsAreImportedAndMatchedToPatients", testEventsAreImportedAndMatchedToPatients),
        ("testEventsFromCalendarsTheUserDidNotChooseAreIgnored", testEventsFromCalendarsTheUserDidNotChooseAreIgnored),
        ("testManualAppointmentsAreNeverTouchedBySynchronisation", testManualAppointmentsAreNeverTouchedBySynchronisation),
        ("testMovingAnAppointmentThatAlreadyHasAPaymentRaisesAConflict", testMovingAnAppointmentThatAlreadyHasAPaymentRaisesAConflict),
        ("testMovingAnUntouchedAppointmentUpdatesItInPlace", testMovingAnUntouchedAppointmentUpdatesItInPlace),
        ("testRecurringOccurrencesAreDistinctRowsNotDuplicates", testRecurringOccurrencesAreDistinctRowsNotDuplicates),
        ("testSynchronisingTwiceChangesNothing", testSynchronisingTwiceChangesNothing),
        ("testTheUserCanKeepEitherSideOfAConflict", testTheUserCanKeepEitherSideOfAConflict),
        ("testTurningACalendarOffRemovesOnlyUntouchedAppointments", testTurningACalendarOffRemovesOnlyUntouchedAppointments)
    ]
}

fileprivate extension DemoDataTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__DemoDataTests = [
        ("testDemoDataIsBelievableAndSelfContained", testDemoDataIsBelievableAndSelfContained),
        ("testDemoDataIsDeterministic", testDemoDataIsDeterministic),
        ("testRemovingDemoDataLeavesRealDataAlone", testRemovingDemoDataLeavesRealDataAlone)
    ]
}

fileprivate extension ExportReconciliationTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__ExportReconciliationTests = [
        ("testTheConsultationsExportCoversEverySlotInThePeriod", testTheConsultationsExportCoversEverySlotInThePeriod),
        ("testThePatientsExportReportsTheHabitsTheApplicationActsOn", testThePatientsExportReportsTheHabitsTheApplicationActsOn),
        ("testThePaymentsExportContainsEveryPaymentExactlyOnce", testThePaymentsExportContainsEveryPaymentExactlyOnce),
        ("testTheReportTotalEqualsTheSumOfItsOwnLines", testTheReportTotalEqualsTheSumOfItsOwnLines)
    ]
}

fileprivate extension ExportTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__ExportTests = [
        ("testActivityReportContainsTheRealFigures", testActivityReportContainsTheRealFigures),
        ("testConsultationsCSVCoversAttendanceAndPayment", testConsultationsCSVCoversAttendanceAndPayment),
        ("testEmptyPeriodStillProducesAValidFile", testEmptyPeriodStillProducesAValidFile),
        ("testFieldsContainingSeparatorsAreQuoted", testFieldsContainingSeparatorsAreQuoted),
        ("testPatientsCSVCarriesTheLearnedHabit", testPatientsCSVCarriesTheLearnedHabit),
        ("testPaymentsCSVIsExcelReadyFrench", testPaymentsCSVIsExcelReadyFrench),
        ("testReportEscapesUserText", testReportEscapesUserText)
    ]
}

fileprivate extension FormattingTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__FormattingTests = [
        ("testColourSeedIsStableAcrossRuns", testColourSeedIsStableAcrossRuns),
        ("testDayRangeIsHalfOpen", testDayRangeIsHalfOpen),
        ("testDurationsReadLikeSpeech", testDurationsReadLikeSpeech),
        ("testMoneyNeverUsesFloatingPoint", testMoneyNeverUsesFloatingPoint),
        ("testMonogramHandlesRealNames", testMonogramHandlesRealNames),
        ("testMonthAndPreviousPeriod", testMonthAndPreviousPeriod),
        ("testRelativeTimesReadLikeSpeech", testRelativeTimesReadLikeSpeech),
        ("testSearchIgnoresAccentsCaseAndPunctuation", testSearchIgnoresAccentsCaseAndPunctuation),
        ("testWeekStartsOnMonday", testWeekStartsOnMonday),
        ("testWholeAmountsDropTheDecimals", testWholeAmountsDropTheDecimals)
    ]
}

fileprivate extension HabitEngineTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__HabitEngineTests = [
        ("testARealChangeOfHabitTakesOver", testARealChangeOfHabitTakesOver),
        ("testASingleExceptionDoesNotDestroyTheHabit", testASingleExceptionDoesNotDestroyTheHabit),
        ("testAdviceIsDeterministicForATie", testAdviceIsDeterministicForATie),
        ("testDistributionsSummariseTheHistory", testDistributionsSummariseTheHistory),
        ("testDuringAChangeTheEngineStopsClaimingAHabitRatherThanGuessing", testDuringAChangeTheEngineStopsClaimingAHabitRatherThanGuessing),
        ("testFiveIdenticalPaymentsBecomeAHabit", testFiveIdenticalPaymentsBecomeAHabit),
        ("testFutureDatedPaymentIsNotAmplified", testFutureDatedPaymentIsNotAmplified),
        ("testHistoryIsCappedSoAncientPaymentsCannotOutvoteRecentOnes", testHistoryIsCappedSoAncientPaymentsCannotOutvoteRecentOnes),
        ("testMethodIsPartOfTheHabitNotJustTheAmount", testMethodIsPartOfTheHabitNotJustTheAmount),
        ("testNoHistoryFallsBackToPracticeTariff", testNoHistoryFallsBackToPracticeTariff),
        ("testPatientTariffBeatsPracticeTariffWhenThereIsNoHistory", testPatientTariffBeatsPracticeTariffWhenThereIsNoHistory),
        ("testThreeIdenticalPaymentsAreTheEarliestAHabitIsClaimed", testThreeIdenticalPaymentsAreTheEarliestAHabitIsClaimed),
        ("testTwoExceptionsAmongManyStillDoNotDestroyTheHabit", testTwoExceptionsAmongManyStillDoNotDestroyTheHabit)
    ]
}

fileprivate extension PatientMatcherTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__PatientMatcherTests = [
        ("testARememberedSpellingAlwaysWins", testARememberedSpellingAlwaysWins),
        ("testAccentsAndCaseAreIgnored", testAccentsAndCaseAreIgnored),
        ("testAmbiguousNamesAreNeverLinkedSilently", testAmbiguousNamesAreNeverLinkedSilently),
        ("testExactNameMatchesAutomatically", testExactNameMatchesAutomatically),
        ("testNoiseWordsAreStrippedFromTitles", testNoiseWordsAreStrippedFromTitles),
        ("testReversedNameOrderStillMatches", testReversedNameOrderStillMatches),
        ("testUnrelatedTitleMatchesNobody", testUnrelatedTitleMatchesNobody)
    ]
}

fileprivate extension PatientProfileTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__PatientProfileTests = [
        ("testAttendedButUnpaidSessionsAppearOnTheRecord", testAttendedButUnpaidSessionsAppearOnTheRecord),
        ("testProfileSummarisesEverythingTheRecordShows", testProfileSummarisesEverythingTheRecordShows)
    ]
}

fileprivate extension RhythmAnalyserTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__RhythmAnalyserTests = [
        ("testFortnightlyRhythmIsDetected", testFortnightlyRhythmIsDetected),
        ("testModeIsDeterministicOnTies", testModeIsDeterministicOnTies),
        ("testMonthlyRhythmIsDetected", testMonthlyRhythmIsDetected),
        ("testScatteredAppointmentsAreCalledIrregular", testScatteredAppointmentsAreCalledIrregular),
        ("testTooFewAppointmentsClaimNothing", testTooFewAppointmentsClaimNothing),
        ("testWeeklyRhythmIsDetected", testWeeklyRhythmIsDetected)
    ]
}

fileprivate extension StoreTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__StoreTests = [
        ("testArchivedPatientsAreHiddenButNotLost", testArchivedPatientsAreHiddenButNotLost),
        ("testAssigningAPatientRemembersTheCalendarWording", testAssigningAPatientRemembersTheCalendarWording),
        ("testAuditTrailRecordsTheDay", testAuditTrailRecordsTheDay),
        ("testBusyDaysAreReported", testBusyDaysAreReported),
        ("testCalendarSubscriptionsPreserveUserChoicesAcrossDiscovery", testCalendarSubscriptionsPreserveUserChoicesAcrossDiscovery),
        ("testDeletingAPatientRemovesTheirPaymentsButKeepsTheConsultationRecord", testDeletingAPatientRemovesTheirPaymentsButKeepsTheConsultationRecord),
        ("testFailedTransactionRollsEverythingBack", testFailedTransactionRollsEverythingBack),
        ("testForeignKeysAreEnforced", testForeignKeysAreEnforced),
        ("testMigrationIsIdempotentAndVersioned", testMigrationIsIdempotentAndVersioned),
        ("testNestedTransactionsCommitOnlyOnce", testNestedTransactionsCommitOnlyOnce),
        ("testSettingsRoundTrip", testSettingsRoundTrip),
        ("testStartingAndEndingASessionRecordsRealTimes", testStartingAndEndingASessionRecordsRealTimes),
        ("testUnassignedConsultationsAreSurfaced", testUnassignedConsultationsAreSurfaced),
        ("testWriteAheadLoggingIsOn", testWriteAheadLoggingIsOn)
    ]
}

fileprivate extension UndoStackTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__UndoStackTests = [
        ("testAFailedUndoLeavesTheStackIntact", testAFailedUndoLeavesTheStackIntact),
        ("testStackIsBoundedAndNewWorkClearsRedo", testStackIsBoundedAndNewWorkClearsRedo),
        ("testUndoAndRedoRestoreAPayment", testUndoAndRedoRestoreAPayment)
    ]
}
@available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
func __CadenceCoreTests__allTests() -> [XCTestCaseEntry] {
    return [
        testCase(AcceptanceScenarioTests.__allTests__AcceptanceScenarioTests),
        testCase(BackupTests.__allTests__BackupTests),
        testCase(CalendarSyncTests.__allTests__CalendarSyncTests),
        testCase(DemoDataTests.__allTests__DemoDataTests),
        testCase(ExportReconciliationTests.__allTests__ExportReconciliationTests),
        testCase(ExportTests.__allTests__ExportTests),
        testCase(FormattingTests.__allTests__FormattingTests),
        testCase(HabitEngineTests.__allTests__HabitEngineTests),
        testCase(PatientMatcherTests.__allTests__PatientMatcherTests),
        testCase(PatientProfileTests.__allTests__PatientProfileTests),
        testCase(RhythmAnalyserTests.__allTests__RhythmAnalyserTests),
        testCase(StoreTests.__allTests__StoreTests),
        testCase(UndoStackTests.__allTests__UndoStackTests)
    ]
}