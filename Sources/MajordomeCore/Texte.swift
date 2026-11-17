import Foundation

/// Transformations du presse-papiers (Hyper + V).
public enum Texte {
    static let francais = Locale(identifier: "fr_FR")

    public static func majuscules(_ s: String) -> String { s.uppercased(with: francais) }

    public static func minuscules(_ s: String) -> String { s.lowercased(with: francais) }

    /// « Majuscule À Chaque Mot »
    public static func titre(_ s: String) -> String {
        var resultat = ""
        var debutMot = true
        for c in minuscules(s) {
            let ch = String(c)
            resultat += (debutMot && c.isLetter) ? ch.uppercased(with: francais) : ch
            debutMot = c.isWhitespace || "-(\"'«’".contains(c)
        }
        return resultat
    }

    public static func sansAccents(_ s: String) -> String {
        s.replacingOccurrences(of: "œ", with: "oe").replacingOccurrences(of: "Œ", with: "OE")
            .replacingOccurrences(of: "æ", with: "ae").replacingOccurrences(of: "Æ", with: "AE")
            .folding(options: .diacriticInsensitive, locale: francais)
    }

    /// « nom-de-fichier-propre »
    public static func slug(_ s: String) -> String {
        var resultat = ""
        var tiret = false
        for u in sansAccents(minuscules(s)).unicodeScalars {
            let estAlnum = (u >= "a" && u <= "z") || (u >= "0" && u <= "9")
            if estAlnum {
                resultat.unicodeScalars.append(u)
                tiret = false
            } else if !tiret && !resultat.isEmpty {
                resultat += "-"
                tiret = true
            }
        }
        while resultat.hasSuffix("-") { resultat.removeLast() }
        return resultat
    }

    /// Espaces doubles, espaces en bout de ligne et lignes vides en trop.
    public static func espaces(_ s: String) -> String {
        let lignes = s.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").map { ligne in
            ligne.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " "))
        }
        return lignes.joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
    }

    public static func compter(_ s: String) -> String {
        let mots = s.split(whereSeparator: { $0.isWhitespace }).count
        let caracteres = s.count
        let lignes = s.components(separatedBy: "\n").count
        func pluriel(_ n: Int) -> String { n > 1 ? "s" : "" }
        return "\(mots) mot\(pluriel(mots)) · \(caracteres) caractère\(pluriel(caracteres)) · \(lignes) ligne\(pluriel(lignes))"
    }

    public static func tronquer(_ s: String, _ n: Int) -> String {
        s.count <= n ? s : String(s.prefix(n - 1)) + "…"
    }
}
