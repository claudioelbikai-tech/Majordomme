import AppKit
import MajordomeCore

/// Session de focus : ligne de temps, fond d'écran sombre, bouclier anti-distraction.
/// L'état vit dans ~/.majordome/focus, partagé avec la commande « focus » du terminal.
final class Focus {
    private(set) var etat: EtatFocus?
    private var insiste: (cle: String, quand: Date)?
    private var minuteurFin: Timer?
    private var minuteurAffichage: Timer?
    private var minuteurSite: Timer?
    private let barres = Barres()

    var changement: (() -> Void)?
    var avantStatistiques: (() -> Void)?

    var minutesRestantes: Int {
        guard let etat else { return 0 }
        return max(0, Int(ceil(Double(etat.fin - Int(Date().timeIntervalSince1970)) / 60)))
    }

    // MARK: Commandes

    func demarrer(minutes: Int, tache: String) {
        let maintenant = Int(Date().timeIntervalSince1970)
        Disque.ecrire(Chemins.focus, EtatFocus(fin: maintenant + minutes * 60, min: minutes, tache: tache).ecrire())
        rafraichir()
    }

    func arreter() {
        Disque.supprimer(Chemins.focus)
        rafraichir()
    }

    func ajouter10() {
        guard var e = etat else { return }
        e.fin += 600
        e.min += 10
        etat = e
        Disque.ecrire(Chemins.focus, e.ecrire())
        planifierFin()
        barres.mettreAJour(etat: e)
        Toast.afficher("10 minutes de plus", duree: 1.5)
        changement?()
    }

    /// Relit le fichier d'état (appelé quand le dossier ~/.majordome change, et au réveil).
    func rafraichir() {
        let lu = EtatFocus.lire(Disque.lire(Chemins.focus))
        switch (lu, etat) {
        case let (nouveau?, nil):
            commencer(nouveau)
        case let (nouveau?, actuel?):
            if nouveau.fin != actuel.fin || nouveau.min != actuel.min || nouveau.tache != actuel.tache {
                var e = nouveau
                e.distractions = max(nouveau.distractions, actuel.distractions)
                etat = e
                planifierFin()
                barres.mettreAJour(etat: e)
            }
        case (nil, _?):
            terminerEffets()
            etat = nil
            Toast.afficher("Session arrêtée", duree: 1.5)
        case (nil, nil):
            break
        }
        changement?()
    }

    // MARK: Bouclier

    /// Appelé à chaque changement d'app. Renvoie true si l'app a été cachée.
    @discardableResult
    func surActivation(_ app: NSRunningApplication) -> Bool {
        guard etat != nil else { return false }
        if let bid = app.bundleIdentifier, R.distractions.contains(bid) {
            return bouclier(cle: bid, nom: app.localizedName ?? bid) { app.hide() }
        }
        surveillerNavigateur(app)
        return false
    }

    @discardableResult
    private func bouclier(cle: String, nom: String, cacher: () -> Void) -> Bool {
        guard var e = etat else { return false }
        if let insiste, insiste.cle == cle, Date().timeIntervalSince(insiste.quand) <= 8 {
            self.insiste = nil
            Toast.afficher("D'accord, \(nom) reste ouvert.", duree: 2)
            return false
        }
        insiste = (cle, Date())
        e.distractions += 1
        etat = e
        Disque.ecrire(Chemins.focus, e.ecrire())
        cacher()
        Toast.afficher("Pas maintenant : \(e.tache) · encore \(minutesRestantes) min\nInsiste dans les 8 secondes pour l'ouvrir quand même.", duree: 3)
        return true
    }

    private static let scriptsURL = [
        "com.apple.Safari": #"tell application "Safari" to return URL of current tab of front window"#,
        "com.google.Chrome": #"tell application "Google Chrome" to return URL of active tab of front window"#,
    ]

    /// Le site affiché n'est vérifié que pendant un focus, quand le navigateur est devant.
    private func surveillerNavigateur(_ app: NSRunningApplication) {
        minuteurSite?.invalidate()
        minuteurSite = nil
        guard etat != nil, R.oui("bouclierSites"), let bid = app.bundleIdentifier, Focus.scriptsURL[bid] != nil else { return }
        verifierSite(app)
        minuteurSite = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] t in
            guard let self, self.etat != nil, NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                t.invalidate()
                return
            }
            self.verifierSite(app)
        }
    }

    private func verifierSite(_ app: NSRunningApplication) {
        guard let bid = app.bundleIdentifier, let script = Focus.scriptsURL[bid], let url = Script.executer(script) else { return }
        let hote = Liens.hote(url)
        if let hote, Liens.estSiteDistraction(hote, R.sitesDistraction) {
            bouclier(cle: hote, nom: hote) { app.hide() }
        }
    }

    // MARK: Déroulé de la session

    private func commencer(_ e: EtatFocus) {
        etat = e
        insiste = nil
        barres.afficher(etat: e)
        Fond.poser()
        planifierFin()
        minuteurAffichage?.invalidate()
        minuteurAffichage = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self, let e = self.etat else { return }
            self.barres.mettreAJour(etat: e)
            self.changement?()
        }
        var message = "Focus : \(e.tache) · \(minutesRestantes) min\nBouclier activé"
        if let etape = Journal.derniereEtape(Disque.lire(Chemins.journal)) { message += "\nLa dernière fois, tu avais noté : \(etape)" }
        Toast.afficher(message, duree: 4)
        if let devant = NSWorkspace.shared.frontmostApplication { surveillerNavigateur(devant) }
    }

    private func planifierFin() {
        minuteurFin?.invalidate()
        guard let e = etat else { return }
        let delai = max(0, Double(e.fin) - Date().timeIntervalSince1970)
        minuteurFin = Timer.scheduledTimer(withTimeInterval: delai, repeats: false) { [weak self] _ in self?.terminer() }
    }

    private func terminerEffets() {
        minuteurFin?.invalidate()
        minuteurAffichage?.invalidate()
        minuteurSite?.invalidate()
        minuteurFin = nil
        minuteurAffichage = nil
        minuteurSite = nil
        barres.masquer()
        Fond.restaurer()
    }

    private func terminer() {
        guard let e = etat else { return }
        if let lu = EtatFocus.lire(Disque.lire(Chemins.focus)), lu.fin > Int(Date().timeIntervalSince1970) {
            etat = lu  // prolongée entre-temps
            planifierFin()
            return
        }
        etat = nil
        terminerEffets()
        Disque.supprimer(Chemins.focus)
        changement?()
        Systeme.notifier("Session terminée", "\(e.tache) · \(e.min) min")
        let debut = Format.date("yyyy-MM-dd HH:mm", Date(timeIntervalSince1970: TimeInterval(e.debut)))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            let r = Invite.demander(titre: "Session terminée : \(e.tache)",
                                    message: "Note la prochaine étape : la prochaine fois, tu repartiras en cinq secondes.",
                                    bouton: "Enregistrer", autre: "Passer")
            Disque.ajouter(Chemins.journal, Journal.ligne(debut: debut, min: e.min, tache: e.tache,
                                                           distractions: e.distractions, prochaine: r.premier ? r.texte : ""))
            self?.avantStatistiques?()
            let st = Journal.stats(jour: Format.jour, focus: Disque.lire(Chemins.journal), reunions: nil, apps: nil)
            Toast.afficher("Aujourd'hui : \(Journal.duree(st.focus)) de concentration sur \(Journal.duree(R.objectifMinutes))", duree: 3)
        }
    }
}

// MARK: - Ligne de temps en haut de chaque écran

final class Barres {
    private var fenetres: [(fenetre: NSWindow, remplissage: CALayer, largeur: CGFloat)] = []

    func afficher(etat: EtatFocus) {
        masquer()
        for ecran in NSScreen.screens {
            let f = ecran.frame
            let cadre = NSRect(x: f.minX, y: f.maxY - 3, width: f.width, height: 3)
            let w = NSWindow(contentRect: cadre, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = NSColor.black.withAlphaComponent(0.25)
            w.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            let vue = NSView(frame: NSRect(origin: .zero, size: cadre.size))
            vue.wantsLayer = true
            let remplissage = CALayer()
            remplissage.backgroundColor = NSColor(calibratedRed: 0.94, green: 0.68, blue: 0.24, alpha: 1).cgColor
            remplissage.frame = NSRect(x: 0, y: 0, width: 0, height: 3)
            vue.layer?.addSublayer(remplissage)
            w.contentView = vue
            w.orderFrontRegardless()
            fenetres.append((w, remplissage, f.width))
        }
        mettreAJour(etat: etat)
    }

    func mettreAJour(etat: EtatFocus) {
        let total = Double(max(1, etat.fin - etat.debut))
        let ratio = min(1, max(0, (Date().timeIntervalSince1970 - Double(etat.debut)) / total))
        CATransaction.begin()
        CATransaction.setAnimationDuration(1)
        for f in fenetres { f.remplissage.frame = NSRect(x: 0, y: 0, width: f.largeur * CGFloat(ratio), height: 3) }
        CATransaction.commit()
    }

    func masquer() {
        fenetres.forEach { $0.fenetre.orderOut(nil) }
        fenetres = []
    }
}

// MARK: - Fond d'écran de concentration

enum Fond {
    private static let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff"]

    private static func cle(_ ecran: NSScreen) -> String {
        (ecran.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? ecran.localizedName
    }

    /// Les fonds animés ou système ne sont jamais touchés : on ne pourrait pas les remettre à l'identique.
    private static func restaurable(_ url: URL) -> Bool {
        url.isFileURL && extensions.contains(url.pathExtension.lowercased())
            && !url.path.contains("/.thumbnails/") && !url.path.contains("Aerial") && Disque.existe(url)
    }

    private static func image() -> URL? {
        if !Disque.existe(Chemins.fondImage) {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0)
            if let rep {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.1, alpha: 1).setFill()
                NSRect(x: 0, y: 0, width: 64, height: 64).fill()
                NSGraphicsContext.restoreGraphicsState()
                try? rep.representation(using: .png, properties: [:])?.write(to: Chemins.fondImage)
            }
        }
        return Disque.existe(Chemins.fondImage) ? Chemins.fondImage : nil
    }

    static func poser() {
        guard R.oui("fondFocus"), let image = image() else { return }
        var avant: [String: String] = [:]
        for ecran in NSScreen.screens {
            guard let actuel = NSWorkspace.shared.desktopImageURL(for: ecran), restaurable(actuel) else { continue }
            avant[cle(ecran)] = actuel.absoluteString
            try? NSWorkspace.shared.setDesktopImageURL(image, for: ecran, options: [:])
        }
        if !avant.isEmpty, let donnees = try? JSONSerialization.data(withJSONObject: avant) {
            try? donnees.write(to: Chemins.fonds)
        }
    }

    static func restaurer() {
        guard let donnees = try? Data(contentsOf: Chemins.fonds),
              let avant = try? JSONSerialization.jsonObject(with: donnees) as? [String: String] else { return }
        for ecran in NSScreen.screens {
            if let texte = avant[cle(ecran)], let url = URL(string: texte) {
                try? NSWorkspace.shared.setDesktopImageURL(url, for: ecran, options: [:])
            }
        }
        Disque.supprimer(Chemins.fonds)
    }
}
