import Foundation

/// Position d'une fenêtre relative à son écran, de 0 à 1.
public struct Unite: Equatable {
    public var x, y, w, h: Double
    public init(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
}

public enum Geometrie {
    /// Appuyer plusieurs fois sur la même direction fait défiler les tailles.
    static let cycles: [String: [Unite]] = [
        "gauche": [Unite(0, 0, 1 / 2, 1), Unite(0, 0, 1 / 3, 1), Unite(0, 0, 2 / 3, 1)],
        "droite": [Unite(1 / 2, 0, 1 / 2, 1), Unite(2 / 3, 0, 1 / 3, 1), Unite(1 / 3, 0, 2 / 3, 1)],
        "haut": [Unite(0, 0, 1, 1 / 2)],
        "bas": [Unite(0, 1 / 2, 1, 1 / 2)],
        "hg": [Unite(0, 0, 1 / 2, 1 / 2)],
        "hd": [Unite(1 / 2, 0, 1 / 2, 1 / 2)],
        "bg": [Unite(0, 1 / 2, 1 / 2, 1 / 2)],
        "bd": [Unite(1 / 2, 1 / 2, 1 / 2, 1 / 2)],
        "centre": [Unite(1 / 6, 0, 2 / 3, 1), Unite(1 / 4, 1 / 8, 1 / 2, 3 / 4)],
    ]

    public static func proche(_ a: Unite, _ b: Unite) -> Bool {
        abs(a.x - b.x) < 0.03 && abs(a.y - b.y) < 0.03 && abs(a.w - b.w) < 0.03 && abs(a.h - b.h) < 0.03
    }

    public static func suivante(_ actuelle: Unite, _ direction: String) -> Unite? {
        guard let liste = cycles[direction] else { return nil }
        for (i, u) in liste.enumerated() where proche(actuelle, u) { return liste[(i + 1) % liste.count] }
        return liste[0]
    }

    public static func estPlein(_ u: Unite) -> Bool { proche(u, Unite(0, 0, 1, 1)) }
}

public enum Divers {
    static let jours = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
    static let mois = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août",
                       "septembre", "octobre", "novembre", "décembre"]

    public static func dateLongue(_ date: Date, calendrier: Calendar = Calendar(identifier: .gregorian)) -> String {
        let c = calendrier.dateComponents([.weekday, .day, .month], from: date)
        return "\(jours[(c.weekday ?? 1) - 1]) \(c.day ?? 1) \(mois[(c.month ?? 1) - 1])"
    }

    /// minutes : nil ou négatif si inconnu
    public static func texteBatterie(pourcentage: Double?, minutes: Int?, secteur: Bool) -> String? {
        guard let pourcentage else { return nil }
        let t = "Batterie \(Int((pourcentage).rounded())) %"
        if secteur { return t + " · sur secteur" }
        if let minutes, minutes > 0 { return t + " · " + Journal.duree(minutes) + " restantes" }
        return t
    }

    /// Une lettre par fenêtre pour Hyper + J : la première lettre de l'app si elle est libre.
    public static func lettresIndices(_ noms: [String]) -> [String] {
        let reserve = Array("ASDFGHJKLQWERTYUIOPZXCVBNM").map(String.init)
        var prises = Set<String>()
        return noms.map { nom in
            let lettres = Texte.sansAccents(nom).uppercased().unicodeScalars
                .filter { $0 >= "A" && $0 <= "Z" }.map { String($0) }
            let choix = (lettres + reserve).first { !prises.contains($0) } ?? "?"
            prises.insert(choix)
            return choix
        }
    }
}
