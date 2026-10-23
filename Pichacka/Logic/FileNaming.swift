import Foundation

enum FileNaming {
    /// "Digi správa & spol." → "digi-sprava-spol"
    static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ")).lowercased()
        var result = ""
        var pendingDash = false
        for scalar in folded.unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                if pendingDash, !result.isEmpty { result.append("-") }
                pendingDash = false
                result.unicodeScalars.append(scalar)
            } else {
                pendingDash = true
            }
        }
        return result.isEmpty ? "projekt" : result
    }

    static func reportFileName(month: ReportMonth, projectName: String) -> String {
        String(format: "%04d-%02d_%@.pdf", month.year, month.month, slug(projectName))
    }
}
