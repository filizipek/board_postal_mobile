import Foundation
import WebKit
import UIKit

@MainActor
final class PDFGenerator: NSObject {

    private var webView: WKWebView?
    private var completion: ((Data?) -> Void)?
    private var navigationDelegate: NavDelegate?

    func generate(
        trip: Trip,
        days: [TripDay],
        places: [TripPlace],
        completion: @escaping (Data?) -> Void
    ) {
        self.completion = completion

        let html = Self.buildHTML(
            trip: trip,
            days: days,
            places: places)

        // A4 size in points (72 dpi)
        let a4 = CGRect(x: 0, y: 0,
                        width: 595, height: 842)
        let wv = WKWebView(frame: a4)

        // Must be in view hierarchy to render
        if let window = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first {
            window.addSubview(wv)
            wv.isHidden = true
        }

        self.webView = wv

        let delegate = NavDelegate { [weak self] in
            self?.exportPDF(rect: a4)
        }
        self.navigationDelegate = delegate
        wv.navigationDelegate = delegate

        wv.loadHTMLString(
            html,
            baseURL: URL(string:
                "https://fonts.googleapis.com"))
    }

    private func exportPDF(rect: CGRect) {
        guard let wv = webView else { return }
        let config = WKPDFConfiguration()
        config.rect = rect
        wv.createPDF(configuration: config) {
            [weak self] result in
            DispatchQueue.main.async {
                self?.webView?.removeFromSuperview()
                self?.webView = nil
                switch result {
                case .success(let data):
                    self?.completion?(data)
                case .failure:
                    self?.completion?(nil)
                }
                self?.completion = nil
            }
        }
    }

    // ── HTML Builder ──────────────────────────
    static func buildHTML(
        trip: Trip,
        days: [TripDay],
        places: [TripPlace]
    ) -> String {
        let dests = trip.destinations
            .map { $0.country }
            .filter { !$0.isEmpty }
            .removingDuplicates()
            .joined(separator: " · ")

        let destStr = dests.isEmpty
            ? (trip.country ?? "") : dests

        let dateRange: String = {
            let parts = [
                trip.plannedStartDate,
                trip.plannedEndDate
            ].compactMap { $0 }
            .map { Self.formatDate($0) }
            .filter { !$0.isEmpty }
            return parts.joined(separator: " – ")
        }()

        let eyebrow = [destStr, dateRange]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        let totalItems = days.reduce(0) {
            $0 + $1.items.count }

        let titleHtml: String = {
            let words = trip.title
                .components(separatedBy: " ")
            if words.count <= 1 {
                return "<em style=\"font-style:italic;color:#5B9BF5\">\(esc(trip.title))</em>"
            }
            let last = words.last ?? ""
            let leading = words.dropLast()
                .joined(separator: " ")
            return "\(esc(leading)) <em style=\"font-style:italic;color:#5B9BF5\">\(esc(last))</em>"
        }()

        let hasCover = trip.coverPhotoUrl != nil
        let coverBg = hasCover
            ? "background:#0F1E3A;background-image:url('\(trip.coverPhotoUrl!)');background-size:cover;background-position:center;"
            : "background:#0F1E3A;"
        let overlay = hasCover
            ? "<div style=\"position:absolute;inset:0;background:linear-gradient(135deg,rgba(15,30,58,0.92) 0%,rgba(10,22,40,0.85) 60%,rgba(27,58,107,0.88) 100%)\"></div>"
            : ""

        let now = Date()
        let monthYear = Self.formatMonthYear(now)
        let year = Calendar.current
            .component(.year, from: now)

        let coverHtml = """
        <div class="cover" style="\(coverBg)">
          \(overlay)
          <div style="position:relative;z-index:2;display:flex;flex-direction:column;justify-content:space-between;flex:1">
            <div class="cover-logo">board_postal</div>
            <div>
              \(eyebrow.isEmpty ? "" : "<div class=\"cover-eye\">\(esc(eyebrow))</div>")
              <div class="cover-title">\(titleHtml)</div>
              <div class="cover-sub">\(days.count) days · Travel guide</div>
              <div class="cover-stats">
                <div><div class="stat-num">\(days.count)</div><div class="stat-label">Days</div></div>
                <div><div class="stat-num">\(places.count)</div><div class="stat-label">Places</div></div>
                <div><div class="stat-num">\(totalItems)</div><div class="stat-label">Items</div></div>
              </div>
            </div>
            <div class="stamp"><div class="stamp-bp">bp</div><div class="stamp-year">\(year)</div></div>
          </div>
        </div>
        """

        let daysHtml: String = days.isEmpty ? "" : {
            let sorted = days.sorted {
                $0.dayNumber < $1.dayNumber }
            let rows = sorted.map { day -> String in
                let itemsHtml = day.items
                    .sorted { $0.orderIndex
                        < $1.orderIndex }
                    .map { item -> String in
                    let dot = Self.dotColor(
                        item.type)
                    let time = item.time ?? ""
                    return """
                    <div class="item">
                      <div class="item-time"\(time.isEmpty ? " style=\"color:transparent\"" : "")>\(time.isEmpty ? "—" : esc(time))</div>
                      <div class="item-dot" style="background:\(dot)"></div>
                      <div class="item-info">
                        <div class="item-title">\(esc(item.title))</div>
                        <div class="item-cat">\(Self.formatType(item.type))</div>
                        \(item.notes.map { "<div class=\"item-notes\">\(esc($0))</div>" } ?? "")
                      </div>
                    </div>
                    """
                }.joined()

                let dateStr = day.formattedDate ?? ""
                return """
                <div class="day">
                  <div class="day-num-col">
                    <div class="day-n">\(String(format: "%02d", day.dayNumber))</div>
                    \(dateStr.isEmpty ? "" : "<div class=\"day-abbr\">\(Self.dayAbbr(day.date))</div>")
                  </div>
                  <div class="day-body">
                    <div class="day-title">\(esc(day.title ?? "Day \(day.dayNumber)"))</div>
                    \(dateStr.isEmpty ? "" : "<div class=\"day-date\">\(esc(dateStr))</div>")
                    \(itemsHtml)
                  </div>
                </div>
                """
            }.joined()
            return """
            <div class="section-header">
              <span class="section-label">Itinerary</span>
              <span class="section-sub">board_postal travel guide</span>
            </div>
            \(rows)
            """
        }()

        let placesHtml: String = places.isEmpty
            ? "" : {
            let cards = places.map { p -> String in
                let city = [p.notes].compactMap { $0 }
                    .isEmpty
                    ? "" : ""
                _ = city
                return """
                <div class="place-card">
                  \(p.category.map { "<div class=\"place-cat\">\(esc($0))</div>" } ?? "")
                  <div class="place-name">\(esc(p.placeName))</div>
                  \(p.notes.map { "<div class=\"place-notes\">\(esc($0))</div>" } ?? "")
                </div>
                """
            }.joined()
            return """
            <div class="section-header">
              <span class="section-label">Places</span>
              <span class="section-sub">\(places.count) places</span>
            </div>
            <div class="places-grid">\(cards)</div>
            """
        }()

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <title>\(esc(trip.title)) — board_postal</title>
        <style>
        *{box-sizing:border-box;margin:0;padding:0;-webkit-print-color-adjust:exact!important}
        body{font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif}
        .cover{min-height:100vh;height:100vh;padding:48px;page-break-after:always;position:relative;overflow:hidden;display:flex;flex-direction:column}
        .cover-logo{font-family:Georgia,"Times New Roman",serif;font-size:14px;color:#E8A020;letter-spacing:.08em}
        .cover-eye{font-size:10px;letter-spacing:.2em;text-transform:uppercase;color:rgba(255,255,255,.4);margin-bottom:14px}
        .cover-title{font-family:Georgia,"Times New Roman",serif;font-size:56px;font-weight:900;color:#fff;line-height:1;margin-bottom:10px}
        .cover-sub{font-size:14px;color:rgba(255,255,255,.4);margin-bottom:40px}
        .cover-stats{display:flex;gap:32px}
        .stat-num{font-family:Georgia,"Times New Roman",serif;font-size:32px;font-weight:700;color:#E8A020}
        .stat-label{font-size:8px;letter-spacing:.14em;text-transform:uppercase;color:rgba(255,255,255,.3);margin-top:2px}
        .stamp{position:absolute;bottom:48px;right:48px;border:1px solid rgba(255,255,255,.15);padding:12px 18px;text-align:center}
        .stamp-bp{font-family:Georgia,"Times New Roman",serif;font-size:28px;font-weight:900;color:rgba(255,255,255,.12)}
        .stamp-year{font-size:8px;letter-spacing:.18em;text-transform:uppercase;color:rgba(255,255,255,.12)}
        .section-header{padding:12px 40px;background:#F0F2F5;border-bottom:1px solid #D4DAE8;display:flex;justify-content:space-between;align-items:baseline}
        .section-label{font-size:8px;letter-spacing:.2em;text-transform:uppercase;color:#5A6A7A;font-weight:500}
        .section-sub{font-size:8px;color:#5A6A7A}
        .day{display:flex;border-bottom:1px solid #E8EDF4}
        .day-num-col{background:#0F1E3A;width:64px;padding:16px 10px;display:flex;flex-direction:column;align-items:center;flex-shrink:0}
        .day-n{font-family:Georgia,"Times New Roman",serif;font-size:28px;font-weight:900;color:rgba(255,255,255,.12);line-height:1}
        .day-abbr{font-size:7px;letter-spacing:.15em;text-transform:uppercase;color:#E8A020;margin-top:4px}
        .day-body{flex:1;padding:14px 24px}
        .day-title{font-family:Georgia,"Times New Roman",serif;font-size:16px;font-weight:700;color:#0D1B2A;margin-bottom:2px}
        .day-date{font-size:9px;color:#5A6A7A;margin-bottom:10px}
        .item{display:flex;gap:10px;padding:5px 0;border-bottom:1px solid #F5F7FA;align-items:flex-start}
        .item:last-child{border-bottom:none}
        .item-time{font-size:9px;color:#5A6A7A;min-width:36px;font-weight:500;padding-top:1px;text-align:right}
        .item-dot{width:7px;height:7px;border-radius:50%;flex-shrink:0;margin-top:3px}
        .item-info{flex:1}
        .item-title{font-size:11px;font-weight:500;color:#0D1B2A}
        .item-cat{font-size:7px;letter-spacing:.1em;text-transform:uppercase;color:#1B4FDB;margin-top:1px}
        .item-notes{font-size:9px;color:#5A6A7A;font-style:italic;margin-top:1px}
        .places-grid{display:grid;grid-template-columns:1fr 1fr;gap:1px;background:#D4DAE8}
        .place-card{background:#fff;padding:12px 16px}
        .place-cat{font-size:7px;letter-spacing:.12em;text-transform:uppercase;color:#1B4FDB;margin-bottom:3px}
        .place-name{font-size:12px;font-weight:500;color:#0D1B2A;margin-bottom:2px}
        .place-notes{font-size:9px;color:#5A6A7A;font-style:italic;margin-top:2px}
        .footer{padding:10px 40px;border-top:1px solid #D4DAE8;display:flex;justify-content:space-between;align-items:center;background:#F0F2F5}
        .footer-logo{font-family:Georgia,"Times New Roman",serif;font-size:11px;color:#1B4FDB}
        .footer-meta{font-size:8px;color:#5A6A7A}
        </style>
        </head>
        <body>
        \(coverHtml)
        \(daysHtml)
        \(placesHtml)
        <div class="footer">
          <div class="footer-logo">board_postal</div>
          <div class="footer-meta">\(esc(trip.title)) · Generated \(monthYear)</div>
        </div>
        </body>
        </html>
        """
    }

    // ── Helpers ───────────────────────────────
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func formatDate(
        _ s: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        guard let d = parser.date(from: s) else {
            return ""
        }
        let f = DateFormatter()
        f.dateStyle = .long
        f.locale = Locale(identifier: "en_GB")
        return f.string(from: d)
    }

    private static func formatMonthYear(
        _ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: d)
    }

    private static func dayAbbr(
        _ s: String?) -> String {
        guard let s else { return "" }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        guard let d = parser.date(from: s) else {
            return ""
        }
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: d).uppercased()
    }

    private static func dotColor(
        _ type: String) -> String {
        switch type {
        case "place":         return "#1D9E75"
        case "transport":     return "#1B4FDB"
        case "accommodation": return "#E8A020"
        default:              return "#5A6A7A"
        }
    }

    private static func formatType(
        _ type: String) -> String {
        switch type {
        case "place":         return "Place"
        case "transport":     return "Transport"
        case "accommodation": return "Accommodation"
        default:              return "Note"
        }
    }
}

// Navigation delegate helper
private final class NavDelegate: NSObject,
    WKNavigationDelegate {
    let onLoad: () -> Void
    init(onLoad: @escaping () -> Void) {
        self.onLoad = onLoad
    }
    func webView(_ webView: WKWebView,
        didFinish navigation: WKNavigation!) {
        // Extra delay for fonts to load
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.5) {
            self.onLoad()
        }
    }
}

// Array helper
private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
