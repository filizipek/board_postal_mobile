import Foundation
import UIKit

/// Produces a deterministic, paginated travel document from data already loaded
/// by TripDetailView. The export contains the trip overview, itinerary, journal,
/// and saved places; it does not invent unavailable content or wait on remote images.
@MainActor
final class PDFGenerator {
    static let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842)

    func generate(
        trip: Trip,
        entries: [TripEntry],
        days: [TripDay],
        places: [TripPlace]
    ) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: trip.title,
            kCGPDFContextCreator as String: "BoardPostal"
        ]
        return UIGraphicsPDFRenderer(bounds: Self.pageBounds, format: format).pdfData { context in
            PDFDocumentLayout(context: context).render(
                trip: trip,
                entries: entries,
                days: days,
                places: places
            )
        }
    }
}

@MainActor
private final class PDFDocumentLayout {
    private let context: UIGraphicsPDFRendererContext
    private let pageBounds = PDFGenerator.pageBounds
    private let margin: CGFloat = 46
    private let footerHeight: CGFloat = 34
    private var cursorY: CGFloat = 0
    private var pageNumber = 0

    private var contentWidth: CGFloat { pageBounds.width - (margin * 2) }
    private var contentBottom: CGFloat { pageBounds.height - margin - footerHeight }

    init(context: UIGraphicsPDFRendererContext) {
        self.context = context
    }

    func render(trip: Trip, entries: [TripEntry], days: [TripDay], places: [TripPlace]) {
        beginPage()
        drawLabel("BOARD_POSTAL TRAVEL STORY")
        drawFlowing(trip.title, font: .systemFont(ofSize: 34, weight: .bold), spacingAfter: 12)

        let metadata = [destinationText(for: trip), dateText(for: trip)]
            .filter { !$0.isEmpty }
            .joined(separator: "  •  ")
        if !metadata.isEmpty {
            drawFlowing(metadata, font: .systemFont(ofSize: 12, weight: .medium), color: .darkGray, spacingAfter: 14)
        }

        if let description = trip.description?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            drawSection("TRIP OVERVIEW")
            drawFlowing(description, font: .systemFont(ofSize: 11), spacingAfter: 14)
        }

        if !days.isEmpty {
            drawSection("ITINERARY")
            for day in days.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                drawFlowing(
                    "Day \(day.dayNumber): \(day.title ?? "Plan")",
                    font: .systemFont(ofSize: 14, weight: .semibold),
                    spacingAfter: 3
                )
                if let date = day.formattedDate, !date.isEmpty {
                    drawFlowing(date, font: .systemFont(ofSize: 9), color: .darkGray, spacingAfter: 4)
                }
                for item in day.items.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                    let time = item.time.map { "\($0)  " } ?? ""
                    drawFlowing(
                        "\(time)\(item.title) [\(formatType(item.type))]",
                        font: .systemFont(ofSize: 10, weight: .medium),
                        leftInset: 12,
                        spacingAfter: 2
                    )
                    if let notes = item.notes, !notes.isEmpty {
                        drawFlowing(notes, font: .italicSystemFont(ofSize: 9), color: .darkGray, leftInset: 24, spacingAfter: 3)
                    }
                }
                cursorY += 7
            }
        }

        if !entries.isEmpty {
            drawSection("JOURNAL")
            for entry in entries.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                drawFlowing(entry.title ?? "Journal entry", font: .systemFont(ofSize: 14, weight: .semibold), spacingAfter: 3)
                let entryMetadata = [entry.entryDate, entry.placeName]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "  •  ")
                if !entryMetadata.isEmpty {
                    drawFlowing(entryMetadata, font: .systemFont(ofSize: 9), color: .darkGray, spacingAfter: 4)
                }
                drawFlowing(entry.content, font: .systemFont(ofSize: 10), spacingAfter: 10)
            }
        }

        if !places.isEmpty {
            drawSection("PLACES")
            for place in places.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                let category = place.category.map { " [\($0)]" } ?? ""
                drawFlowing("\(place.placeName)\(category)", font: .systemFont(ofSize: 11, weight: .semibold), spacingAfter: 2)
                if let notes = place.notes, !notes.isEmpty {
                    drawFlowing(notes, font: .systemFont(ofSize: 9), color: .darkGray, leftInset: 12, spacingAfter: 5)
                }
            }
        }

        drawFooter(tripTitle: trip.title)
    }

    private func beginPage() {
        if pageNumber > 0 { drawFooter(tripTitle: nil) }
        context.beginPage()
        pageNumber += 1
        cursorY = margin
    }

    private func ensureSpace(_ height: CGFloat) {
        if cursorY + height > contentBottom { beginPage() }
    }

    private func drawSection(_ title: String) {
        ensureSpace(34)
        cursorY += 10
        let rect = CGRect(x: margin, y: cursorY, width: contentWidth, height: 20)
        UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1).setFill()
        UIBezierPath(rect: rect).fill()
        (title as NSString).draw(
            in: rect.insetBy(dx: 8, dy: 5),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 8, weight: .bold),
                .foregroundColor: UIColor.darkGray
            ]
        )
        cursorY = rect.maxY + 8
    }

    private func drawLabel(_ text: String) {
        let blue = UIColor(red: 0.11, green: 0.31, blue: 0.86, alpha: 1)
        drawFlowing(text, font: .systemFont(ofSize: 9, weight: .bold), color: blue, spacingAfter: 8)
    }

    private func drawFlowing(
        _ text: String,
        font: UIFont,
        color: UIColor = .black,
        leftInset: CGFloat = 0,
        spacingAfter: CGFloat = 0
    ) {
        let availableWidth = contentWidth - leftInset
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let lineHeight = ceil(font.lineHeight * 1.18)

        for paragraphText in text.components(separatedBy: .newlines) {
            let words = paragraphText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if words.isEmpty {
                ensureSpace(lineHeight)
                cursorY += lineHeight
                continue
            }
            var line = ""
            for word in words {
                let candidate = line.isEmpty ? word : "\(line) \(word)"
                if (candidate as NSString).size(withAttributes: attributes).width > availableWidth,
                   !line.isEmpty {
                    drawLine(line, attributes: attributes, leftInset: leftInset, height: lineHeight)
                    line = word
                } else {
                    line = candidate
                }
            }
            if !line.isEmpty {
                drawLine(line, attributes: attributes, leftInset: leftInset, height: lineHeight)
            }
        }
        cursorY += spacingAfter
    }

    private func drawLine(
        _ line: String,
        attributes: [NSAttributedString.Key: Any],
        leftInset: CGFloat,
        height: CGFloat
    ) {
        ensureSpace(height)
        (line as NSString).draw(
            in: CGRect(x: margin + leftInset, y: cursorY, width: contentWidth - leftInset, height: height),
            withAttributes: attributes
        )
        cursorY += height
    }

    private func drawFooter(tripTitle: String?) {
        guard pageNumber > 0 else { return }
        let title = tripTitle.map { "\($0)  •  " } ?? ""
        ("\(title)BoardPostal  •  Page \(pageNumber)" as NSString).draw(
            in: CGRect(x: margin, y: pageBounds.height - margin, width: contentWidth, height: 14),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 8),
                .foregroundColor: UIColor.gray
            ]
        )
    }

    private func destinationText(for trip: Trip) -> String {
        let destinations = trip.destinations
            .sorted(by: { $0.orderIndex < $1.orderIndex })
            .map { "\($0.city), \($0.country)" }
        if !destinations.isEmpty { return destinations.joined(separator: " · ") }
        return [trip.city, trip.country].compactMap { $0 }.joined(separator: ", ")
    }

    private func dateText(for trip: Trip) -> String {
        [trip.plannedStartDate, trip.plannedEndDate]
            .compactMap { $0 }
            .joined(separator: " – ")
    }

    private func formatType(_ type: String) -> String {
        switch type {
        case "place": "Place"
        case "transport": "Transport"
        case "accommodation": "Accommodation"
        default: "Note"
        }
    }
}
