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
            Task { @MainActor in
                do {
                    try await PDFRenderer.shared.write(html: html, to: url)
                    self.showToast("Rapport enregistré · \(url.lastPathComponent)", undoLabel: nil)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } catch {
                    self.failure = "Le rapport n'a pas pu être produit : \(error.localizedDescription)"
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

/// Turns the report's HTML into a paginated A4 PDF using the system print engine.
///
/// Nothing is downloaded and no network is touched: the HTML is fully self-contained
/// and is loaded from a string with no base URL.
@MainActor
final class PDFRenderer: NSObject, WKNavigationDelegate {
    static let shared = PDFRenderer()

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Error>?

    enum Failure: LocalizedError {
        case loadFailed(String)
        case printFailed
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .loadFailed(let reason): return "Mise en page impossible (\(reason))."
            case .printFailed: return "L'impression vers un fichier a échoué."
            case .emptyResult: return "Le fichier produit était vide."
            }
        }
    }

    func write(html: String, to url: URL) async throws {
        let configuration = WKWebViewConfiguration()
        // No JavaScript is needed to lay out the report; turning it off keeps the
        // rendering deterministic.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 595, height: 842), configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }

        // A beat for web fonts and layout to settle before the page is measured.
        try? await Task.sleep(nanoseconds: 250_000_000)

        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 595, height: 842)      // A4 in points
        printInfo.topMargin = 46
        printInfo.bottomMargin = 46
        printInfo.leftMargin = 40
        printInfo.rightMargin = 40
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.jobDisposition = .save
        printInfo.dictionary().setValue(url, forKey: NSPrintInfo.AttributeKey.jobSavingURL.rawValue)

        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.view?.frame = NSRect(x: 0, y: 0, width: 595 - 80, height: 842 - 92)

        let succeeded = operation.run()
        self.webView = nil

        guard succeeded else { throw Failure.printFailed }

        // Never claim success without checking: a zero-byte PDF is a failed export.
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else { throw Failure.emptyResult }
    }

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
