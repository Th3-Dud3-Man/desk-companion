import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers
import CadenceCore

/// Saving files. Every export here writes a real file and confirms it did; nothing
/// in Cadence offers a button that quietly does nothing.
extension AppModel {

    // MARK: CSV

    func requestExport(_ kind: ExportKind) {
        let range = DateRange.month(containing: selectedDay)
        requestExport(kind, range: range, rangeLabel: CadenceFormat.monthYear(selectedDay))
    }

    func requestExport(_ kind: ExportKind, range: DateRange, rangeLabel: String) {
        let panel = NSSavePanel()
        panel.title = "Exporter · \(kind.label)"
        panel.nameFieldStringValue = "\(kind.fileStem)-\(Self.fileStamp(range.start)).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.message = kind == .patients
            ? "Liste complète des patients"
            : "\(kind.label) · \(rangeLabel)"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try store.exportCSV(kind, range: range, settings: settings)
            try data.write(to: url, options: .atomic)
            let rows = max(0, (String(data: data, encoding: .utf8)?
                .components(separatedBy: "\r\n")
                .filter { !$0.isEmpty }
                .count ?? 1) - 1)
            showToast("\(rows) ligne\(rows > 1 ? "s" : "") exportée\(rows > 1 ? "s" : "") · \(url.lastPathComponent)", undoLabel: nil)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            report(error)
        }
    }

    // MARK: PDF report

    func requestReport() {
        let range = DateRange.month(containing: selectedDay)
        requestReport(range: range, title: "Activité · \(CadenceFormat.monthYear(selectedDay))")
    }

    func requestReport(range: DateRange, title: String) {
        let panel = NSSavePanel()
        panel.title = "Rapport d'activité"
        panel.nameFieldStringValue = "cadence-rapport-\(Self.fileStamp(range.start)).pdf"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.message = title

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let html = try store.activityReport(for: range, title: title, settings: settings)
            renderPDF(html: html, to: url, label: "Rapport")
        } catch {
            report(error)
        }
    }

    /// Writes a PDF and, if every direct route fails, falls back to the system print
    /// panel rather than leaving the user with nothing.
    func renderPDF(html: String, to url: URL, label: String) {
        Task { @MainActor in
            do {
                try await PDFRenderer.shared.write(html: html, to: url)
                self.showToast("\(label) enregistré · \(url.lastPathComponent)", undoLabel: nil)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                self.failure = error.localizedDescription
                // The panel is the one route that cannot fail: the user picks
                // "PDF ▸ Enregistrer au format PDF" and gets the same document.
                try? await PDFRenderer.shared.present(html: html)
            }
        }
    }

    /// The bank-facing summary. A separate document from the activity report, and a
    /// separate action: it counts only money that arrived, over a window long enough
    /// to show a pattern, and it is meant to be produced *after* the month has been
    /// checked over in the ledger.
    func requestIncomeReport(range: DateRange, label: String) {
        let panel = NSSavePanel()
        panel.title = "Synthèse de revenus"
        panel.nameFieldStringValue = "cadence-revenus-\(Self.fileStamp(range.start)).pdf"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.message = "Revenus encaissés · \(label)"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let html = try store.incomeReport(for: range, settings: settings)
            renderPDF(html: html, to: url, label: "Synthèse de revenus")
        } catch {
            report(error)
        }
    }

    /// Ready-made windows, because a lender almost always asks for one of these.
    enum IncomeWindow: String, CaseIterable, Identifiable {
        case trailingTwelveMonths, currentYear, previousYear

        var id: String { rawValue }

        var title: String {
            switch self {
            case .trailingTwelveMonths: return "12 derniers mois"
            case .currentYear: return "Année civile en cours"
            case .previousYear: return "Année précédente"
            }
        }

        func range(now: Date = Date(), calendar: Calendar = .cadence) -> DateRange {
            switch self {
            case .trailingTwelveMonths:
                let thisMonth = DateRange.month(containing: now, calendar: calendar)
                let start = calendar.date(byAdding: .month, value: -11, to: thisMonth.start) ?? thisMonth.start
                return DateRange(start: start, end: thisMonth.end)
            case .currentYear:
                return .year(containing: now, calendar: calendar)
            case .previousYear:
                let previous = calendar.date(byAdding: .year, value: -1, to: now) ?? now
                return .year(containing: previous, calendar: calendar)
            }
        }

        func label(now: Date = Date(), calendar: Calendar = .cadence) -> String {
            switch self {
            case .trailingTwelveMonths:
                let window = range(now: now, calendar: calendar)
                let last = calendar.date(byAdding: .day, value: -1, to: window.end) ?? window.end
                return "\(CadenceFormat.monthYear(window.start)) – \(CadenceFormat.monthYear(last))"
            case .currentYear:
                return String(calendar.component(.year, from: now))
            case .previousYear:
                return String(calendar.component(.year, from: now) - 1)
            }
        }
    }

    /// Straight to the print panel, for when the user would rather drive it.
    func printReport(range: DateRange, title: String) {
        do {
            let html = try store.activityReport(for: range, title: title, settings: settings)
            Task { @MainActor in
                do {
                    try await PDFRenderer.shared.present(html: html)
                } catch {
                    self.failure = error.localizedDescription
                }
            }
        } catch {
            report(error)
        }
    }

    static func fileStamp(_ date: Date) -> String {
        let components = Calendar.cadence.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }
}

/// Turns the report's HTML into a PDF.
///
/// Three attempts, in order, because a report that will be handed to a bank has to
/// come out one way or another:
///
/// 1. **The print engine**, which paginates properly onto A4. WebKit will print a
///    blank page from a view that is not in a window, so the view is put in an
///    offscreen one — that omission is why this used to produce nothing.
/// 2. **`createPDF`**, which returns the bytes directly with no print system
///    involved. Less control over pagination, but it does not depend on a run loop.
/// 3. **The system print panel**, where the user chooses “PDF ▸ Enregistrer au
///    format PDF”. Always available, and honest about needing one more click.
///
/// Whatever the path, the file is checked for being non-empty and a real PDF before
/// success is reported.
@MainActor
final class PDFRenderer: NSObject, WKNavigationDelegate {
    static let shared = PDFRenderer()

    /// Held for the lifetime of a render; releasing either mid-print loses the page.
    private var webView: WKWebView?
    private var window: NSWindow?
    private var continuation: CheckedContinuation<Void, Error>?

    /// A4 in points, and the margins the report is laid out for.
    private static let paper = NSSize(width: 595, height: 842)
    private static let horizontalMargin: CGFloat = 40
    private static let verticalMargin: CGFloat = 46

    enum Failure: LocalizedError {
        case loadFailed(String)
        case allStrategiesFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .loadFailed(let reason):
                return "La mise en page du rapport a échoué (\(reason))."
            case .allStrategiesFailed(let detail):
                return "Le PDF n'a pas pu être écrit (\(detail)). Utilisez « Imprimer… » puis « PDF ▸ Enregistrer au format PDF »."
            case .cancelled:
                return "Enregistrement annulé."
            }
        }
    }

    // MARK: - Public

    func write(html: String, to url: URL) async throws {
        try await load(html: html)
        defer { tearDown() }

        var problems: [String] = []

        if let error = attemptPrintToFile(url: url) {
            problems.append("impression : \(error)")
        } else if isValidPDF(at: url) {
            return
        } else {
            problems.append("impression : fichier vide")
        }

        do {
            let data = try await createPDFData()
            try data.write(to: url, options: .atomic)
            if isValidPDF(at: url) { return }
            problems.append("createPDF : fichier vide")
        } catch {
            problems.append("createPDF : \(error.localizedDescription)")
        }

        try? FileManager.default.removeItem(at: url)
        throw Failure.allStrategiesFailed(problems.joined(separator: " ; "))
    }

    /// The always-works path: the system print panel, from which the user saves a
    /// PDF wherever they like. Offered when the direct routes fail, and from the menu.
    func present(html: String) async throws {
        try await load(html: html)
        defer { tearDown() }

        guard let webView else { throw Failure.loadFailed("vue indisponible") }
        let operation = webView.printOperation(with: printInfo(savingTo: nil))
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        _ = operation.run()
    }

    // MARK: - Loading

    private func load(html: String) async throws {
        tearDown()

        let configuration = WKWebViewConfiguration()
        // The report is static HTML; no script has to run for it to lay out, and
        // turning it off keeps the rendering deterministic.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        // The frame must be the printable width, or WebKit scales the page to fit
        // and the type comes out the wrong size.
        let printableWidth = Self.paper.width - Self.horizontalMargin * 2
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: printableWidth, height: Self.paper.height),
            configuration: configuration
        )
        webView.navigationDelegate = self

        // WebKit prints a blank page from a view with no window behind it. An
        // offscreen window costs nothing and is what makes the print path work.
        let window = NSWindow(
            contentRect: webView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(webView)

        self.webView = webView
        self.window = window

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }

        // One beat for fonts and final layout before the page is measured.
        try? await Task.sleep(nanoseconds: 350_000_000)
    }

    private func tearDown() {
        continuation = nil
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        window?.orderOut(nil)
        window = nil
    }

    // MARK: - Strategies

    /// Returns a description of what went wrong, or nil when the job ran.
    private func attemptPrintToFile(url: URL) -> String? {
        guard let webView else { return "vue indisponible" }

        // A stale file at the destination makes the print job fail silently.
        try? FileManager.default.removeItem(at: url)

        let operation = webView.printOperation(with: printInfo(savingTo: url))
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false

        return operation.run() ? nil : "le travail d'impression a été refusé"
    }

    private func createPDFData() async throws -> Data {
        guard let webView else { throw Failure.loadFailed("vue indisponible") }
        return try await withCheckedThrowingContinuation { continuation in
            webView.createPDF(configuration: WKPDFConfiguration()) { result in
                continuation.resume(with: result)
            }
        }
    }

    // MARK: - Helpers

    private func printInfo(savingTo url: URL?) -> NSPrintInfo {
        let info = NSPrintInfo()
        info.paperSize = Self.paper
        info.topMargin = Self.verticalMargin
        info.bottomMargin = Self.verticalMargin
        info.leftMargin = Self.horizontalMargin
        info.rightMargin = Self.horizontalMargin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false

        if let url {
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url as NSURL
        }
        return info
    }

    /// A PDF that is empty, or that is not a PDF, is a failed export whatever the
    /// print system reported.
    private func isValidPDF(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let magic = handle.readData(ofLength: 5)
        guard magic == Data("%PDF-".utf8) else { return false }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)??.intValue ?? 0
        return size > 1_000
    }

    // MARK: - Navigation delegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            continuation?.resume()
            continuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: Failure.loadFailed(error.localizedDescription))
            continuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: Failure.loadFailed(error.localizedDescription))
            continuation = nil
        }
    }
}
