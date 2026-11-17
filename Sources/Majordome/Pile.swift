import AppKit
import MajordomeCore

/// Pile de contexte : Hyper + P met de côté tes fenêtres et une phrase, Hyper + O remet tout en place.
final class Pile {
    struct FenetreSauvee: Codable {
        var bundle: String
        var app: String
        var titre: String
        var x, y, w, h: Double
    }

    struct Contexte: Codable {
        var note: String
        var quand: String
        var fenetres: [FenetreSauvee]
    }

    var changement: (() -> Void)?

    var taille: Int { lire().count }

    private func lire() -> [Contexte] {
        guard let donnees = try? Data(contentsOf: Chemins.pile),
              let pile = try? JSONDecoder().decode([Contexte].self, from: donnees) else { return [] }
        return pile
    }

    private func ecrire(_ pile: [Contexte]) {
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = [.prettyPrinted]
        try? encodeur.encode(pile).write(to: Chemins.pile)
    }

    private func capturer() -> [FenetreSauvee] {
        ListeFenetres.visibles().compactMap { f in
            guard let bundle = f.app.bundleIdentifier else { return nil }
            return FenetreSauvee(bundle: bundle, app: f.app.localizedName ?? bundle,
                                 titre: f.element.map(AX.titre) ?? "",
                                 x: f.bornes.minX, y: f.bornes.minY, w: f.bornes.width, h: f.bornes.height)
        }
    }

    func pousser(note imposee: String? = nil) {
        guard Systeme.accessibiliteOK() else { GestionFenetres().demanderAccessibilite(); return }
        let fenetres = capturer()
        var note = imposee ?? ""
        if imposee == nil {
            let r = Invite.demander(titre: "Mettre de côté", message: "Où en es-tu ? Une phrase suffit pour repartir vite.",
                                    bouton: "Mettre de côté", autre: "Annuler")
            guard r.premier else { return }
            note = r.texte
        }
        var pile = lire()
        pile.append(Contexte(note: note, quand: Format.date("yyyy-MM-dd HH:mm"), fenetres: fenetres))
        ecrire(pile)
        Toast.afficher("Mis de côté (\(pile.count) dans la pile)\nHyper + O pour y revenir", duree: 2.5)
        changement?()
    }

    var dessus: Contexte? { lire().last }

    func reprendre() {
        var pile = lire()
        guard let ctx = pile.popLast() else { Toast.afficher("Rien à reprendre : la pile est vide.", duree: 2); return }
        ecrire(pile)
        changement?()
        var ordre: [String] = []
        for f in ctx.fenetres where !ordre.contains(f.bundle) {
            ordre.append(f.bundle)
            if Systeme.appEnCours(f.bundle) == nil { Systeme.lancer(bundle: f.bundle) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            var placees: [Int: AXUIElement] = [:]
            for bundle in ordre {
                guard let app = Systeme.appEnCours(bundle) else { continue }
                app.unhide()
                let actuelles = AX.fenetres(pid: app.processIdentifier).filter(AX.estStandard)
                let indices = ctx.fenetres.indices.filter { ctx.fenetres[$0].bundle == bundle }
                let paires = Journal.associer(sauvees: indices.map { ctx.fenetres[$0].titre }, actuelles: actuelles.map(AX.titre))
                for p in paires {
                    let s = ctx.fenetres[indices[p.sauvee]]
                    let w = actuelles[p.actuelle]
                    if AX.estReduite(w) { AX.deReduire(w) }
                    AX.poser(w, CGRect(x: s.x, y: s.y, width: s.w, height: s.h))
                    placees[indices[p.sauvee]] = w
                }
            }
            // La première fenêtre sauvegardée finit devant.
            for i in ctx.fenetres.indices.reversed() {
                if let w = placees[i] { AX.lever(w) }
            }
            if let premiere = ctx.fenetres.first { Systeme.appEnCours(premiere.bundle)?.activate(options: []) }
            Toast.afficher("De retour : " + (ctx.note.isEmpty ? "contexte du \(ctx.quand)" : ctx.note), duree: 5)
        }
    }
}
