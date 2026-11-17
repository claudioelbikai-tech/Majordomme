import AppKit
import CoreMediaIO
import MajordomeCore

/// Captures d'écran renommées d'après l'app affichée.
final class Captures {
    private var surveillant: Surveillant?
    var derniereApp: String?

    func demarrer() {
        Disque.creerDossier(Chemins.captures)
        surveillant = Surveillant(Chemins.captures) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.renommer() }
        }
    }

    private func renommer() {
        guard R.oui("nommerCaptures"),
              let noms = try? FileManager.default.contentsOfDirectory(atPath: Chemins.captures.path) else { return }
        for nom in noms where Rangement.estCaptureBrute(nom) {
            guard let nouveau = Rangement.nomCapture(nom, app: derniereApp),
                  let cible = Rangement.nomLibre(Chemins.captures.path, nouveau, existe: Disque.existe) else { continue }
            try? FileManager.default.moveItem(atPath: Chemins.captures.path + "/" + nom, toPath: cible)
        }
    }
}

/// Téléchargements rangés par type après quelques jours. Rien n'est jamais supprimé.
final class Telechargements {
    private var dernier = Date.distantPast

    /// Au plus une fois toutes les 6 heures, au réveil du Mac : aucune minuterie.
    func rangerSiBesoin() {
        guard Date().timeIntervalSince(dernier) >= 6 * 3600 else { return }
        dernier = Date()
        ranger(manuel: false)
    }

    func ranger(manuel: Bool) {
        guard R.oui("rangerTelechargements") || manuel else { return }
        let dossier = Chemins.telechargements.path
        let limite = Date().addingTimeInterval(-Double(R.joursAvantRangement) * 86400)
        guard let noms = try? FileManager.default.contentsOfDirectory(atPath: dossier) else { return }
        var n = 0
        for nom in noms where nom != "Rangé" {
            let chemin = dossier + "/" + nom
            guard let categorie = Rangement.categorie(nom),
                  let attributs = try? FileManager.default.attributesOfItem(atPath: chemin),
                  (attributs[.type] as? FileAttributeType) == .typeRegular else { continue }
            let dates = [attributs[.modificationDate], attributs[.creationDate]].compactMap { $0 as? Date }
            guard let recente = dates.max(), recente < limite else { continue }
            let destination = dossier + "/Rangé/" + categorie
            try? FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
            if let cible = Rangement.nomLibre(destination, nom, existe: Disque.existe),
               (try? FileManager.default.moveItem(atPath: chemin, toPath: cible)) != nil {
                n += 1
            }
        }
        if n > 0 || manuel {
            Toast.afficher(n > 0 ? "Téléchargements : \(n) fichier\(n > 1 ? "s" : "") rangé\(n > 1 ? "s" : "") dans « Rangé »"
                                 : "Téléchargements : rien à ranger", duree: 2.5)
        }
    }
}

/// Réunions comptées : macOS prévient quand une caméra s'allume ou s'éteint.
final class Reunions {
    private(set) var debut: Date?
    private var ecoutes: [(CMIOObjectID, CMIOObjectPropertyAddress, CMIOObjectPropertyListenerBlock)] = []
    private var minuteurMenu: Timer?
    var changement: (() -> Void)?

    var minutes: Int { debut.map { Int(Date().timeIntervalSince($0) / 60) } ?? 0 }

    private static func adresse<A: BinaryInteger, B: BinaryInteger, C: BinaryInteger>(_ selecteur: A, _ portee: B, _ element: C) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(selecteur),
                                  mScope: CMIOObjectPropertyScope(portee),
                                  mElement: CMIOObjectPropertyElement(element))
    }

    private func cameras() -> [CMIOObjectID] {
        var adr = Reunions.adresse(kCMIOHardwarePropertyDevices, kCMIOObjectPropertyScopeGlobal, kCMIOObjectPropertyElementMain)
        let systeme = CMIOObjectID(kCMIOObjectSystemObject)
        var taille: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(systeme, &adr, 0, nil, &taille) == noErr, taille > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(taille) / MemoryLayout<CMIOObjectID>.size)
        var utilise: UInt32 = 0
        guard CMIOObjectGetPropertyData(systeme, &adr, 0, nil, taille, &utilise, &ids) == noErr else { return [] }
        return ids
    }

    private func enMarche(_ id: CMIOObjectID) -> Bool {
        var adr = Reunions.adresse(kCMIODevicePropertyDeviceIsRunningSomewhere, kCMIOObjectPropertyScopeWildcard, kCMIOObjectPropertyElementWildcard)
        var valeur: UInt32 = 0
        var utilise: UInt32 = 0
        guard CMIOObjectGetPropertyData(id, &adr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &utilise, &valeur) == noErr else { return false }
        return valeur != 0
    }

    func demarrer() {
        arreter()
        guard R.oui("suivreReunions") else { return }
        for id in cameras() {
            var adr = Reunions.adresse(kCMIODevicePropertyDeviceIsRunningSomewhere, kCMIOObjectPropertyScopeWildcard, kCMIOObjectPropertyElementWildcard)
            let bloc: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.verifier() }
            }
            if CMIOObjectAddPropertyListenerBlock(id, &adr, DispatchQueue.main, bloc) == noErr {
                ecoutes.append((id, adr, bloc))
            }
        }
        verifier()
    }

    func arreter() {
        for (id, adresse, bloc) in ecoutes {
            var adr = adresse
            CMIOObjectRemovePropertyListenerBlock(id, &adr, DispatchQueue.main, bloc)
        }
        ecoutes = []
    }

    private func verifier() {
        let enCours = cameras().contains(where: enMarche)
        if enCours, debut == nil {
            debut = Date()
            minuteurMenu = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.changement?() }
            Toast.afficher("Réunion détectée : Majordome compte le temps", duree: 2)
        } else if !enCours, let d = debut {
            minuteurMenu?.invalidate()
            let min = Int((Date().timeIntervalSince(d) / 60).rounded())
            if min >= 2 {
                Disque.ajouter(Chemins.reunions, Format.date("yyyy-MM-dd HH:mm", d) + "|\(min)\n")
                Toast.afficher("Réunion terminée : " + Journal.duree(min), duree: 3)
            }
            debut = nil
        }
        changement?()
    }
}

/// Temps par app : noté une fois par minute si tu es actif, écrit sur le disque par paquets de 5.
final class JournalApps {
    private var tampon: [String] = []
    private var minuteur: Timer?

    func demarrer() {
        minuteur = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.noter() }
        minuteur?.tolerance = 10
    }

    private func noter() {
        guard R.oui("journalApps"), Systeme.inactivite < 120,
              let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        tampon.append(Format.date("yyyy-MM-dd HH:mm") + "\t" + (app.localizedName ?? "?") + "\n")
        if tampon.count >= 5 { vider() }
    }

    func vider() {
        guard !tampon.isEmpty else { return }
        Disque.ajouter(Chemins.temps(), tampon.joined())
        tampon = []
    }
}

/// Voile de confidentialité : écran noir et son coupé, sur tous les écrans.
final class Voile {
    private var fenetres: [NSWindow] = []
    private var sonCoupeAvant = false

    var actif: Bool { !fenetres.isEmpty }

    func basculer() {
        if actif {
            fenetres.forEach { $0.orderOut(nil) }
            fenetres = []
            if !sonCoupeAvant { Systeme.couperSon(false) }
            return
        }
        sonCoupeAvant = Systeme.sonCoupe
        Systeme.couperSon(true)
        for ecran in NSScreen.screens {
            let w = NSWindow(contentRect: ecran.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.backgroundColor = .black
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            let texte = NSTextField(labelWithString: "Hyper + L pour revenir")
            texte.textColor = NSColor.white.withAlphaComponent(0.22)
            texte.font = .systemFont(ofSize: 13)
            texte.alignment = .center
            texte.frame = NSRect(x: 0, y: 40, width: ecran.frame.width, height: 20)
            w.contentView?.addSubview(texte)
            w.orderFrontRegardless()
            fenetres.append(w)
        }
    }
}
