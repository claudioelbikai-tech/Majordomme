import Foundation

/// Fichiers partagés avec le terminal (commandes focus, bilan, priorites, note) : mêmes formats.
public struct EtatFocus: Equatable {
    public var fin: Int
    public var min: Int
    public var tache: String
    public var distractions: Int

    public init(fin: Int, min: Int, tache: String, distractions: Int = 0) {
        self.fin = fin; self.min = min; self.tache = tache; self.distractions = distractions
    }

    public var debut: Int { fin - min * 60 }

    /// « fin|minutes|tâche|distractions » (fin en secondes depuis 1970)
    public static func lire(_ texte: String?) -> EtatFocus? {
        guard let texte else { return nil }
        let ligne = texte.drop(while: { $0.isWhitespace }).split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        var champs = ligne.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard champs.count >= 3, let fin = Int(champs[0]), let min = Int(champs[1]) else { return nil }
        var distractions = 0
        if champs.count >= 4, let d = Int(champs[champs.count - 1].trimmingCharacters(in: .whitespaces)) {
            distractions = d
            champs.removeLast()
        }
        return EtatFocus(fin: fin, min: min, tache: champs[2...].joined(separator: "|"), distractions: distractions)
    }

    public func ecrire() -> String { "\(fin)|\(min)|\(Journal.propre(tache))|\(distractions)\n" }
}

public struct Priorite: Equatable {
    public var texte: String
    public var fait: Bool
    public init(texte: String, fait: Bool = false) { self.texte = texte; self.fait = fait }
}

public struct StatsJour: Equatable {
    public var focus = 0, sessions = 0, distractions = 0, reunions = 0, nbReunions = 0
    public var apps: [(nom: String, minutes: Int)] = []
    public static func == (a: StatsJour, b: StatsJour) -> Bool {
        a.focus == b.focus && a.sessions == b.sessions && a.distractions == b.distractions
            && a.reunions == b.reunions && a.nbReunions == b.nbReunions
            && a.apps.map(\.nom) == b.apps.map(\.nom) && a.apps.map(\.minutes) == b.apps.map(\.minutes)
    }
}

public enum Journal {
    static func propre(_ s: String) -> String {
        s.replacingOccurrences(of: "[|\r\n]", with: " ", options: .regularExpression)
    }

    public static func ligne(debut: String, min: Int, tache: String, distractions: Int, prochaine: String) -> String {
        "\(debut)|\(min)|\(propre(tache))|\(distractions)|\(propre(prochaine))\n"
    }

    public static func ligneIdee(_ texte: String, quand: String) -> String {
        "- [ ] \(texte.replacingOccurrences(of: "[\r\n]+", with: " ", options: .regularExpression))  (\(quand))\n"
    }

    /// La dernière « prochaine étape » notée en fin de session.
    public static func derniereEtape(_ journal: String?) -> String? {
        var derniere: String?
        for ligne in (journal ?? "").split(separator: "\n") {
            let champs = ligne.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false)
            if champs.count == 5, champs[4].contains(where: { !$0.isWhitespace }) { derniere = String(champs[4]) }
        }
        return derniere
    }

    // MARK: Priorités « [ ] texte » / « [x] texte »

    public static func lirePriorites(_ texte: String?) -> [Priorite] {
        var liste: [Priorite] = []
        for brute in (texte ?? "").split(separator: "\n") {
            let ligne = String(brute)
            if ligne.hasPrefix("["), ligne.count >= 3, ligne[ligne.index(ligne.startIndex, offsetBy: 2)] == "]" {
                let coche = ligne[ligne.index(after: ligne.startIndex)]
                let t = ligne.dropFirst(3).trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { liste.append(Priorite(texte: t, fait: coche == "x" || coche == "X")) }
            } else if ligne.contains(where: { !$0.isWhitespace }) {
                liste.append(Priorite(texte: ligne.trimmingCharacters(in: .whitespaces)))
            }
        }
        return liste
    }

    public static func ecrirePriorites(_ liste: [Priorite]) -> String {
        liste.map { ($0.fait ? "[x] " : "[ ] ") + propre($0.texte) }.joined(separator: "\n") + "\n"
    }

    public static func prochainePriorite(_ liste: [Priorite]) -> (texte: String, numero: Int)? {
        for (i, p) in liste.enumerated() where !p.fait { return (p.texte, i + 1) }
        return nil
    }

    // MARK: Statistiques

    public static func stats(jour: String, focus: String?, reunions: String?, apps: String?) -> StatsJour {
        var st = StatsJour()
        for ligne in (focus ?? "").split(separator: "\n") {
            let c = ligne.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard c.count >= 2, c[0].hasPrefix(jour), let min = Int(c[1]) else { continue }
            st.focus += min
            st.sessions += 1
            if c.count >= 4, let d = Int(c[3]) { st.distractions += d }
        }
        for ligne in (reunions ?? "").split(separator: "\n") {
            let c = ligne.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard c.count >= 2, c[0].hasPrefix(jour), let min = Int(c[1]) else { continue }
            st.reunions += min
            st.nbReunions += 1
        }
        var parApp: [String: Int] = [:]
        for ligne in (apps ?? "").split(separator: "\n") {
            let c = ligne.split(separator: "\t", maxSplits: 1).map(String.init)
            guard c.count == 2, c[0].hasPrefix(jour) else { continue }
            parApp[c[1], default: 0] += 1
        }
        st.apps = parApp.map { (nom: $0.key, minutes: $0.value) }
            .sorted { $0.minutes > $1.minutes || ($0.minutes == $1.minutes && $0.nom < $1.nom) }
        return st
    }

    public static func duree(_ min: Int) -> String {
        min < 60 ? "\(min) min" : String(format: "%d h %02d", min / 60, min % 60)
    }

    public static func texteBilan(_ st: StatsJour, objectif: Int) -> String {
        let pct = objectif > 0 ? st.focus * 100 / objectif : 0
        var lignes = ["Concentration : \(duree(st.focus)) sur \(duree(objectif)) (\(pct) %)"]
        let s = st.sessions > 1 ? "s" : "", d = st.distractions > 1 ? "s" : ""
        lignes.append("\(st.sessions) session\(s) · \(st.distractions) distraction\(d) bloquée\(d)")
        if st.nbReunions > 0 { lignes.append("Réunions : \(duree(st.reunions)) (\(st.nbReunions))") }
        if !st.apps.isEmpty {
            lignes.append("Apps : " + st.apps.prefix(3).map { "\($0.nom) \(duree($0.minutes))" }.joined(separator: " · "))
        }
        return lignes.joined(separator: "\n")
    }

    /// Fenêtres sauvegardées → fenêtres ouvertes : même titre d'abord, puis dans l'ordre.
    public static func associer(sauvees: [String], actuelles: [String]) -> [(sauvee: Int, actuelle: Int)] {
        var prises = Set<Int>()
        var paires: [(Int, Int)] = []
        var restantes: [Int] = []
        for (i, titre) in sauvees.enumerated() {
            if let j = actuelles.indices.first(where: { !prises.contains($0) && !actuelles[$0].isEmpty && actuelles[$0] == titre }) {
                prises.insert(j)
                paires.append((i, j))
            } else {
                restantes.append(i)
            }
        }
        for i in restantes {
            if let j = actuelles.indices.first(where: { !prises.contains($0) }) {
                prises.insert(j)
                paires.append((i, j))
            }
        }
        return paires.map { (sauvee: $0.0, actuelle: $0.1) }
    }
}
