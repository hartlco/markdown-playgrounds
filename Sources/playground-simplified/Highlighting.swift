//
//  Highlighting.swift
//  CommonMark
//
//  Created by Chris Eidhof on 08.03.19.
//

import Foundation
import CommonMark
import Ccmark

extension String.UnicodeScalarView {
    var lineIndices: [String.Index] {
        var result = [startIndex]
        for i in indices {
            if self[i] == "\n" { // todo: should this be "\n" || "\r" ??
                result.append(self.index(after: i))
            }
        }
        return result
    }
}

import Cocoa

struct Attributes {
    var family: String
    var size: CGFloat
    var bold: Bool
    var italic: Bool
    var textColor: NSColor
    var backgroundColor: NSColor
    var firstlineHeadIndent: CGFloat
    var headIndent: CGFloat
    var tabStops: [CGFloat]
    var alignment: NSTextAlignment
    var lineHeightMultiple: CGFloat

    mutating func setIndent(_ value: CGFloat) {
        firstlineHeadIndent = value
        headIndent = value
    }

    var font: NSFont {
        var fontDescriptor = NSFontDescriptor(name: family, size: size)
        var traits = NSFontDescriptor.SymbolicTraits()
        if bold { traits.formUnion(.bold) }
        if italic { traits.formUnion(.italic )}
        if !traits.isEmpty { fontDescriptor = fontDescriptor.withSymbolicTraits(traits) }
        let font = NSFont(descriptor: fontDescriptor, size: size)!
        return font
    }

    var paragraphStyle: NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = firstlineHeadIndent
        paragraphStyle.headIndent = headIndent
        paragraphStyle.tabStops = tabStops.map { NSTextTab(textAlignment: .left, location: $0) }
        paragraphStyle.alignment = alignment
        paragraphStyle.lineHeightMultiple = lineHeightMultiple
        return paragraphStyle
    }
}

extension Attributes {
    var atts: [NSAttributedString.Key:Any] {
        return [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
            .backgroundColor: backgroundColor
        ]
    }
}

let defaultAttributes = Attributes(family: "Helvetica", size: fontSize, bold: false, italic: false, textColor: NSColor.textColor, backgroundColor: NSColor.textBackgroundColor, firstlineHeadIndent: 0, headIndent: 0, tabStops: [], alignment: NSTextAlignment.left, lineHeightMultiple: 1.1)
let fontSize: CGFloat = 18
let accentColors: [NSColor] = [
    // From: https://ethanschoonover.com/solarized/#the-values
    (181, 137,   0),
    (203,  75,  22),
    (220,  50,  47),
    (211,  54, 130),
    (108, 113, 196),
    ( 38, 139, 210),
    ( 42, 161, 152),
    (133, 153,   0)
].map { NSColor(calibratedRed: CGFloat($0.0) / 255, green: CGFloat($0.1) / 255, blue: CGFloat($0.2) / 255, alpha: 1)}

struct CodeBlock {
    let range: NSRange
    let fenceInfo: String?
    let text: String
}

extension CommonMark.Node {
    /// When visiting a node, you can modify the state, and the modified state gets passed on to all children.
    func visitAll<State>(_ initial: State, _ callback: (Node, inout State) -> ()) {
        for c in children {
            var copy = initial
            callback(c, &copy)
            c.visitAll(copy, callback)
        }
    }
}

extension NSMutableAttributedString {
    var range: NSRange { return NSMakeRange(0, length) }
    
    func highlight(_ swiftHighlighter: SwiftHighlighter) -> [CodeBlock] {
        setAttributes(defaultAttributes.atts, range: range)
        guard let parsed = Node(markdown: string) else { return [] }
        let scalars = string.unicodeScalars
        let lineNumbers = string.unicodeScalars.lineIndices
        var result: [CodeBlock] = []
        parsed.visitAll(defaultAttributes) { el, attributes in
            guard el.start.column > 0 && el.start.line > 0 else { return }
            let start = scalars.index(lineNumbers[Int(el.start.line-1)], offsetBy: Int(el.start.column-1))
            let end = scalars.index(lineNumbers[Int(el.end.line-1)], offsetBy: Int(el.end.column-1))
            guard start <= end, start >= string.startIndex, end < string.endIndex else { return } // todo should be error?
            let range = start...end
            let nsRange = NSRange(range, in: string)
            switch el.type {
            case CMARK_NODE_HEADING:
                attributes.textColor = accentColors[1]
                attributes.size = fontSize + 2 + (CGFloat(6-el.headerLevel)*1.7)
                addAttribute(.foregroundColor, value: attributes.textColor, range: nsRange)
                addAttribute(.font, value: attributes.font, range: nsRange)
            case CMARK_NODE_EMPH:
                attributes.italic = true
                addAttribute(.font, value: attributes.font, range: nsRange)
            case CMARK_NODE_STRONG:
                attributes.bold = true
                addAttribute(.font, value: attributes.font, range: nsRange)
            case CMARK_NODE_LINK:
                attributes.textColor = .linkColor
                addAttribute(.foregroundColor, value: attributes.textColor, range: nsRange)
                if let s = el.urlString, let u = URL(string: s) {
			addAttribute(.link, value: u, range: nsRange)
                }
            case CMARK_NODE_CODE:
                attributes.family = "Monaco"
                addAttribute(.font, value: attributes.font, range: nsRange)
            case CMARK_NODE_BLOCK_QUOTE:
                attributes.family = "Georgia"
                attributes.setIndent(fontSize)
                addAttribute(.font, value: attributes.font, range: nsRange)
                addAttribute(.paragraphStyle, value: attributes.paragraphStyle, range: nsRange)
            case CMARK_NODE_LIST:
                attributes.setIndent(fontSize)
                addAttribute(.paragraphStyle, value: attributes.paragraphStyle, range: nsRange)
            case CMARK_NODE_CODE_BLOCK:
                addAttribute(.backgroundColor, value: NSColor.underPageBackgroundColor, range: nsRange)
                addAttribute(.font, value: NSFont(name: "Monaco", size: fontSize)!, range: nsRange)
                let block = CodeBlock(range: nsRange, fenceInfo: el.fenceInfo, text: el.literal!)
                if let res = swiftHighlighter.cache[el.literal!] {
                    highlight(block: block, result: res)
                } else {
                	result.append(block)
                }
            default:
                ()
            }
        }
        return result
    }
}
