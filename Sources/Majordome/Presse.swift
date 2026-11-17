import AppKit
import MajordomeCore

/// Presse-papiers : liens nettoyés tout seuls, et transformations sur Hyper + V.
final class Presse {
    private var compteur = NSPasteboard.general.changeCount
    private var minuteur: Timer?

    /// macOS ne prévient pas quand on copie : un coup d'œil toutes les 2 s (une simple lecture de compteur),
    /// plus un à chaque changement d'app, juste avant que tu colles ailleurs.
    func demarrer() {
        minuteur = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.verifier() }
        minuteur?.tolerance = 0.5
    }

    func verifier() {
        let pb = NSPasteboard.general
        guard pb.changeCount != compteur else { return }
        compteur = pb.changeCount
        guard R.oui("nettoyerLiens"), let r = Liens.nettoyer(pb.string(forType: .string)) else { return }
        pb.clearContents()
        pb.setString(r.lien, forType: .string)
        compteur = pb.changeCount
        let n = r.retires.count
        Toast.afficher("Lien nettoyé : \(n) traqueur\(n > 1 ? "s" : "") retiré\(n > 1 ? "s" : "")", duree: 1.6)
    }

    private func coller(_ texte: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(texte, forType: .string)
        compteur = pb.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { Clavier.coller() }
    }

    func choix() -> [Choix] {
        let texte = NSPasteboard.general.string(forType: .string) ?? ""
        func transfo(_ titre: String, _ detail: String?, _ f: @escaping (String) -> String) -> Choix {
            Choix(titre: titre, detail: detail) { [weak self] in
                guard !texte.isEmpty else { Toast.afficher("Le presse-papiers ne contient pas de texte.", duree: 2); return }
                self?.coller(f(texte))
            }
        }
        return [
            transfo("Texte brut", "Retire gras, couleurs et liens, puis colle") { $0 },
            transfo("Nettoyer les espaces", "Espaces doubles et lignes vides en trop", Texte.espaces),
            transfo("MAJUSCULES", nil, Texte.majuscules),
            transfo("minuscules", nil, Texte.minuscules),
            transfo("Majuscule À Chaque Mot", nil, Texte.titre),
            transfo("nom-de-fichier-propre", "Sans accents ni espaces", Texte.slug),
            Choix(titre: "JSON lisible", detail: "Indente un JSON compact") { [weak self] in
                guard let donnees = texte.data(using: .utf8),
                      let objet = try? JSONSerialization.jsonObject(with: donnees, options: [.fragmentsAllowed]),
                      let joli = try? JSONSerialization.data(withJSONObject: objet, options: [.prettyPrinted, .sortedKeys]),
                      let resultat = String(data: joli, encoding: .utf8) else {
                    Toast.afficher("Ce n'est pas du JSON valide.", duree: 2)
                    return
                }
                self?.coller(resultat)
            },
            Choix(titre: "Compter mots et caractères", detail: nil) { Toast.afficher(Texte.compter(texte), duree: 4) },
            Choix(titre: "Taper le texte", detail: "Pour les champs qui interdisent de coller") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Clavier.ecrire(texte) }
            },
        ]
    }
}
