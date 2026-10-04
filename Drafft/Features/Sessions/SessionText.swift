import Foundation

extension String {
    /// First letter in capitals, the rest untouched: "lundi 5 octobre" becomes "Lundi 5 octobre".
    var sentenceCased: String { prefix(1).uppercased() + dropFirst() }
}
