//
//  String+Citation.swift
//  AISDK
//
//  Safe substring extraction using UTF-16 code unit offsets
//  for citation position data from AI providers.
//

import Foundation

extension String {
    /// Extract substring using UTF-16 code unit offsets as returned by `AISource.startIndex`/`AISource.endIndex`.
    ///
    /// OpenAI returns UTF-16 offsets natively. Anthropic and Gemini offsets are converted to UTF-16
    /// at the adapter boundary. This method safely handles multi-byte characters (emoji, CJK, etc.).
    ///
    /// - Parameters:
    ///   - startIndex: UTF-16 code unit offset (inclusive) where the citation starts
    ///   - endIndex: UTF-16 code unit offset (exclusive) where the citation ends
    /// - Returns: The cited substring, or nil if offsets are out of bounds
    public func citedText(startIndex: Int, endIndex: Int) -> String? {
        let utf16 = self.utf16
        guard startIndex >= 0,
              endIndex >= startIndex,
              let start = utf16.index(utf16.startIndex, offsetBy: startIndex, limitedBy: utf16.endIndex),
              let end = utf16.index(utf16.startIndex, offsetBy: endIndex, limitedBy: utf16.endIndex) else {
            return nil
        }
        return String(utf16[start..<end])
    }

    /// Convert Unicode scalar (code point) offsets to UTF-16 code unit offsets.
    ///
    /// Anthropic's `char_location` citations use Unicode code point offsets.
    /// This converts them to UTF-16 for the normalized `AISource` representation.
    ///
    /// - Parameters:
    ///   - scalarStart: Unicode scalar offset (inclusive)
    ///   - scalarEnd: Unicode scalar offset (exclusive)
    /// - Returns: Tuple of (utf16Start, utf16End), or nil if offsets are out of bounds
    public func scalarOffsetsToUTF16(scalarStart: Int, scalarEnd: Int) -> (start: Int, end: Int)? {
        let scalars = self.unicodeScalars
        guard scalarStart >= 0, scalarEnd >= scalarStart else { return nil }

        guard let startScalarIndex = scalars.index(scalars.startIndex, offsetBy: scalarStart, limitedBy: scalars.endIndex),
              let endScalarIndex = scalars.index(scalars.startIndex, offsetBy: scalarEnd, limitedBy: scalars.endIndex) else {
            return nil
        }

        let utf16Start = startScalarIndex.utf16Offset(in: self)
        let utf16End = endScalarIndex.utf16Offset(in: self)
        return (utf16Start, utf16End)
    }

    /// Convert UTF-8 byte offsets to UTF-16 code unit offsets.
    ///
    /// Gemini's `groundingSupports.segment` uses UTF-8 byte offsets.
    /// This converts them to UTF-16 for the normalized `AISource` representation.
    ///
    /// - Parameters:
    ///   - utf8Start: UTF-8 byte offset (inclusive)
    ///   - utf8End: UTF-8 byte offset (exclusive)
    /// - Returns: Tuple of (utf16Start, utf16End), or nil if offsets are out of bounds
    public func utf8OffsetsToUTF16(utf8Start: Int, utf8End: Int) -> (start: Int, end: Int)? {
        let utf8View = self.utf8
        guard utf8Start >= 0, utf8End >= utf8Start else { return nil }

        guard let startUTF8Index = utf8View.index(utf8View.startIndex, offsetBy: utf8Start, limitedBy: utf8View.endIndex),
              let endUTF8Index = utf8View.index(utf8View.startIndex, offsetBy: utf8End, limitedBy: utf8View.endIndex) else {
            return nil
        }

        let utf16Start = startUTF8Index.utf16Offset(in: self)
        let utf16End = endUTF8Index.utf16Offset(in: self)
        return (utf16Start, utf16End)
    }
}
