import SwiftUI

// MARK: - board_postal Typography System
// Playfair Display for editorial headings, Inter for body text.
// Playfair must be added via Info.plist + font files in the project bundle.

// MARK: - Font registration helper
// Variable fonts registered via Info.plist UIAppFonts. The base PostScript
// names ("PlayfairDisplay-Regular", "Inter-Regular") cover the entire weight
// axis through Font.weight(_:); italic variants are wired to the italic
// PostScript names directly so editorial italics render real glyphs rather
// than a synthesised oblique.
struct BPFont {
    private static let playfairRegular = "PlayfairDisplay-Regular"
    private static let playfairItalic  = "PlayfairDisplay-Italic"
    private static let interRegular    = "Inter-Regular"
    private static let interItalic     = "Inter-Italic"

    // Playfair Display — editorial headings
    static func playfair(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom(playfairRegular, size: size).weight(weight)
    }

    static func playfairItalic(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom(playfairItalic, size: size).weight(weight)
    }

    // Inter — body, UI, captions
    static func inter(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom(interRegular, size: size).weight(weight)
    }

    static func interItalic(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom(interItalic, size: size).weight(weight)
    }
}

// MARK: - Type scale
// Usage: Text("Destination").font(.bpHeadline)
extension Font {
    // Editorial — Playfair Display
    static let bpDisplay   = BPFont.playfair(size: 36, weight: .bold)   // Hero titles
    static let bpTitle     = BPFont.playfair(size: 28, weight: .bold)   // Page headers
    static let bpHeadline  = BPFont.playfair(size: 22, weight: .bold)   // Section headers
    static let bpSubhead   = BPFont.playfair(size: 18, weight: .regular) // Card titles

    // Body — Inter
    static let bpBody      = BPFont.inter(size: 16, weight: .regular)   // Body text
    static let bpBodyBold  = BPFont.inter(size: 16, weight: .semibold)  // Emphasised body
    static let bpCallout   = BPFont.inter(size: 14, weight: .regular)   // Secondary info
    static let bpCaption   = BPFont.inter(size: 12, weight: .regular)   // Timestamps, labels
    static let bpLabel     = BPFont.inter(size: 11, weight: .medium)    // Badges, tags (uppercase)
    static let bpButton    = BPFont.inter(size: 16, weight: .semibold)  // Button labels
    static let bpNavLabel  = BPFont.inter(size: 10, weight: .medium)    // Tab bar labels
}

// MARK: - Text style modifiers
struct BPEditorialStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.bpHeadline)
            .foregroundColor(.bpInk)
            .tracking(0.2)
    }
}

struct BPCaptionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.bpCaption)
            .foregroundColor(.bpTextMuted)
            .tracking(0.5)
            .textCase(.uppercase)
    }
}

extension View {
    func bpEditorialStyle() -> some View {
        modifier(BPEditorialStyle())
    }
    func bpCaptionStyle() -> some View {
        modifier(BPCaptionStyle())
    }
}

// MARK: - ItalicLastWord
// Brand signature: every editorial headline ends with the last word
// rendered in italic Playfair in bpAzure (#5B9BF5).
// Usage: ItalicLastWord(text: "Edinburgh Dream")
struct ItalicLastWord: View {
    let text: String
    var font: Font = .bpTitle
    var baseColor: Color = .white

    private var words: [String] {
        text.components(separatedBy: " ")
    }
    private var leadingText: String {
        words.dropLast().joined(separator: " ")
    }
    private var lastWord: String {
        words.last ?? text
    }

    var body: some View {
        if words.count >= 2 {
            (
                Text(leadingText + " ")
                    .font(font)
                    .foregroundColor(baseColor)
                +
                Text(lastWord)
                    .font(font)
                    .italic()
                    .foregroundColor(.bpAzure)
            )
        } else {
            Text(text)
                .font(font)
                .foregroundColor(baseColor)
        }
    }
}

// MARK: - Font installation instructions
/*
 To install Playfair Display and Inter:

 1. Download from Google Fonts:
    - https://fonts.google.com/specimen/Playfair+Display
    - https://fonts.google.com/specimen/Inter

 2. Add the .ttf files to your Xcode project:
    - PlayfairDisplay-Regular.ttf
    - PlayfairDisplay-Bold.ttf
    - PlayfairDisplay-SemiBold.ttf
    - Inter-Regular.ttf
    - Inter-Medium.ttf
    - Inter-SemiBold.ttf
    - Inter-Bold.ttf
    Make sure "Target Membership" is checked for BoardPostal.

 3. Register in Info.plist under "Fonts provided by application":
    - PlayfairDisplay-Regular.ttf
    - PlayfairDisplay-Bold.ttf
    - PlayfairDisplay-SemiBold.ttf
    - Inter-Regular.ttf
    - Inter-Medium.ttf
    - Inter-SemiBold.ttf
    - Inter-Bold.ttf

 4. Clean build (Cmd+Shift+K) and rebuild.

 Until fonts are installed, the system falls back to the default system font.
*/
