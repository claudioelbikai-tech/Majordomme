import AppKit
import Carbon.HIToolbox
import MajordomeCore
import SwiftUI

/// Le cœur de l'app : relie la barre des menus, la touche Hyper et tous les services.
/// Rien ne tourne en boucle : tout réagit à des événements de macOS.
final class Majordome: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let focus = Focus()
    let presse = Presse()
    let pile = Pile()
    let captures = Captures()
    let telechargements = Telechargements()
    let reunions = Reunions()
    let journal = JournalApps()
    let voile = Voile()
    let eveil = Eveil()
    let fenetres = GestionFenetres()
    let indices = Indices()
    let hyper = ToucheHyper()

    private var element: NSStatusItem?
    private var raccourcisFenetres: [Raccourci] = []
    private var surveillantDossier: Surveillant?
    private var minuteurRapport: Timer?
    private var reglagesEnAttente: DispatchWorkItem?
    private var monotache = false
    private var priorites: [Priorite] = []
    private var fenetreBienvenue: NSWindow?
    private var fenetreReglages: NSWindow?
    private let numeros = ["①", "②", "③", "④", "⑤"]

    // MARK: - Démarrage

    func applicationDidFinishLaunching(_ notification: Notification) {
        R.enregistrerDefauts()
        Disque.creerDossier(Chemins.dossier)
        priorites = Journal.lirePriorites(Disque.lire(Chemins.priorites))
        installerMenu()

        focus.changement = { [weak self] in self?.majTitre() }
        focus.avantStatistiques = { [weak self] in self?.journal.vider() }
        pile.changement = { [weak self] in self?.majTitre() }
        reunions.changement = { [weak self] in self?.majTitre() }

        // Le terminal et l'app partagent ~/.majordome : macOS prévient à chaque changement.
        surveillantDossier = Surveillant(Chemins.dossier) { [weak self] in self?.dossierChange() }
        presse.demarrer()
        journal.demarrer()
        captures.demarrer()
        reunions.demarrer()
        observer()
        appliquerClavier()

        if !Disque.existe(Chemins.focus) { Fond.restaurer() }  // fond resté en place après un arrêt brutal
        focus.rafraichir()
        planifierRapport()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.rituelSiBesoin() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.telechargements.rangerSiBesoin() }

        if !R.bienvenueVue || !Systeme.accessibiliteOK() {
            montrerBienvenue()
        } else {
            Toast.afficher("Majordome est prêt · Verr. Maj + Espace pour tout voir", duree: 2.5)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        journal.vider()
        Fond.restaurer()
    }

    private func observer() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            self.captures.derniereApp = app.localizedName
            self.presse.verifier()
            if self.focus.surActivation(app) { return }
            if self.monotache { self.cacherAutres(garder: [app.bundleIdentifier ?? ""]) }
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.reveil() }
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.journal.vider() }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"),
                                                            object: nil, queue: .main) { [weak self] _ in self?.reveil() }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reglagesChanges()
        }
    }

    private func reveil() {
        if R.oui("verrMajHyper") { Systeme.appliquerVerrMaj(true) }
        focus.rafraichir()
        rituelSiBesoin()
        telechargements.rangerSiBesoin()
    }

    private func dossierChange() {
        let lues = Journal.lirePriorites(Disque.lire(Chemins.priorites))
        if lues != priorites {
            priorites = lues
            majTitre()
        }
        focus.rafraichir()
    }

    /// Les réglages changent (fenêtre Réglages) : on réapplique, une demi-seconde après la dernière frappe.
    private func reglagesChanges() {
        reglagesEnAttente?.cancel()
        let travail = DispatchWorkItem { [weak self] in
            self?.appliquerClavier()
            self?.reunions.demarrer()
            self?.planifierRapport()
        }
        reglagesEnAttente = travail
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: travail)
    }

    // MARK: - Clavier

    private func appliquerClavier() {
        let d = UserDefaults.standard
        if R.oui("verrMajHyper") {
            Systeme.appliquerVerrMaj(true)
            if !d.bool(forKey: "verrMajAppliquee") { d.set(true, forKey: "verrMajAppliquee") }
        } else if d.bool(forKey: "verrMajAppliquee") {
            Systeme.appliquerVerrMaj(false)
            d.set(false, forKey: "verrMajAppliquee")
        }

        hyper.toutRetirer()
        raccourcisFenetres.forEach { $0.supprimer() }
        raccourcisFenetres = []

        hyper.lier(kVK_Space) { [weak self] in self?.palette() }
        hyper.lier(kVK_ANSI_G) { [weak self] in self?.ouvrirFocus() }
        hyper.lier(kVK_ANSI_I) { [weak self] in self?.ouvrirIdee() }
        hyper.lier(kVK_ANSI_P) { [weak self] in self?.pile.pousser() }
        hyper.lier(kVK_ANSI_O) { [weak self] in self?.pile.reprendre() }
        hyper.lier(kVK_ANSI_U) { [weak self] in self?.basculerMonotache() }
        hyper.lier(kVK_ANSI_L) { [weak self] in self?.voile.basculer() }
        hyper.lier(kVK_ANSI_V) { [weak self] in self?.ouvrirPresse() }
        hyper.lier(kVK_ANSI_H) { [weak self] in self?.tableauDeBord() }
        hyper.lier(kVK_ANSI_J) { [weak self] in self?.indices.afficher() }
        hyper.lier(kVK_ANSI_D) { [weak self] in self?.modeSombre() }
        hyper.lier(kVK_LeftArrow) { [weak self] in self?.fenetres.ecranVoisin(-1) }
        hyper.lier(kVK_RightArrow) { [weak self] in self?.fenetres.ecranVoisin(1) }
        for lettre in R.lettresApps {
            guard let bundle = R.app(lettre), let code = R.codes[lettre] else { continue }
            hyper.lier(code) { [weak self] in self?.basculerApp(lettre: lettre, bundle: bundle) }
        }
        hyper.demarrer()

        guard R.oui("fenetres") else { return }
        let directions: [(Int, String)] = [
            (kVK_LeftArrow, "gauche"), (kVK_RightArrow, "droite"), (kVK_UpArrow, "haut"), (kVK_DownArrow, "bas"),
            (kVK_Return, "plein"), (kVK_ANSI_C, "centre"), (kVK_ANSI_U, "hg"), (kVK_ANSI_I, "hd"),
            (kVK_ANSI_J, "bg"), (kVK_ANSI_K, "bd"),
        ]
        for (code, direction) in directions {
            if let r = Raccourci(code: code, modificateurs: Raccourci.ctrlAlt, action: { [weak self] appui in
                if appui { self?.fenetres.deplacer(direction) }
            }) {
                raccourcisFenetres.append(r)
            }
        }
    }

    /// Hyper + lettre : ouvre l'app, ou la cache si elle est déjà devant.
    private func basculerApp(lettre: String, bundle: String) {
        if lettre == "t", terminalIci() { return }
        if let app = Systeme.appEnCours(bundle), app.isActive {
            app.hide()
        } else {
            Systeme.lancer(bundle: bundle)
        }
    }

    /// Hyper + T depuis le Finder : le terminal s'ouvre dans le dossier affiché.
    private func terminalIci() -> Bool {
        guard R.oui("terminalIci"), NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
              let bundle = R.app("t"),
              let chemin = Script.executer(#"tell application "Finder" to if (count of Finder windows) > 0 then return POSIX path of (target of front Finder window as alias)"#),
              !chemin.isEmpty else { return false }
        Disque.ecrire(Chemins.ici, chemin)
        if let terminal = Systeme.appEnCours(bundle) {
            terminal.activate(options: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { Clavier.taper(kVK_ANSI_N, drapeaux: .maskCommand) }
        } else {
            Systeme.lancer(bundle: bundle)
        }
        Toast.afficher("Terminal ouvert dans " + ((chemin as NSString).lastPathComponent), duree: 1.5)
        return true
    }

    private func modeSombre() {
        if !Systeme.basculerModeSombre() {
            Toast.afficher("Autorise Majordome à contrôler « System Events » :\nRéglages Système → Confidentialité et sécurité → Automatisation", duree: 5)
        }
    }

    private func cacherAutres(garder: Set<String>) {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isHidden {
            guard let bid = app.bundleIdentifier, !garder.contains(bid), bid != Bundle.main.bundleIdentifier else { continue }
            app.hide()
        }
    }

    private func basculerMonotache() {
        monotache.toggle()
        if monotache {
            cacherAutres(garder: [NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""])
            Toast.afficher("Monotâche : une seule app visible à la fois", duree: 2)
        } else {
            Toast.afficher("Monotâche désactivé", duree: 1.5)
        }
        majTitre()
    }

    private func basculerEveil() {
        let actif = eveil.basculer()
        Toast.afficher(actif ? "Écran toujours allumé, jusqu'à ce que tu le recoupes" : "L'écran peut de nouveau se mettre en veille", duree: 2)
        majTitre()
    }

    // MARK: - Sélecteurs

    private func palette() {
        var liste: [Choix] = [
            Choix(titre: focus.etat == nil ? "Démarrer une session de focus" : "Arrêter ou prolonger la session", detail: "Hyper G") { [weak self] in self?.ouvrirFocus() },
            Choix(titre: "Noter une idée", detail: "Hyper I · va dans ~/Documents/inbox.md") { [weak self] in self?.ouvrirIdee() },
            Choix(titre: "Mettre de côté ce que je fais", detail: "Hyper P · sauve fenêtres et note") { [weak self] in self?.pile.pousser() },
            Choix(titre: "Reprendre là où j'en étais", detail: "Hyper O · \(pile.taille) en attente") { [weak self] in self?.pile.reprendre() },
            Choix(titre: "Tableau de bord", detail: "Hyper H · heure, priorité, focus, batterie") { [weak self] in self?.tableauDeBord() },
            Choix(titre: "Sauter vers une fenêtre", detail: "Hyper J · une lettre par fenêtre") { [weak self] in self?.indices.afficher() },
            Choix(titre: "Monotâche : une seule app visible", detail: "Hyper U") { [weak self] in self?.basculerMonotache() },
            Choix(titre: "Voile de confidentialité", detail: "Hyper L · écran noir et son coupé") { [weak self] in self?.voile.basculer() },
            Choix(titre: "Basculer mode sombre / clair", detail: "Hyper D") { [weak self] in self?.modeSombre() },
            Choix(titre: eveil.actif ? "Laisser l'écran se mettre en veille" : "Garder l'écran allumé", detail: "Pour une présentation ou une recette") { [weak self] in self?.basculerEveil() },
            Choix(titre: "Transformer le presse-papiers", detail: "Hyper V") { [weak self] in self?.ouvrirPresse() },
            Choix(titre: "Définir mes 3 priorités du jour", detail: nil) { [weak self] in self?.demanderPriorites() },
            Choix(titre: "Scène : Début de journée", detail: "Agenda, rappels, priorités") { [weak self] in self?.debutDeJournee() },
            Choix(titre: "Scène : Fin de journée", detail: "Met tout de côté et affiche le bilan") { [weak self] in self?.finDeJournee() },
        ]
        for scene in Scenes.toutes() {
            liste.append(Choix(titre: "Scène : " + scene.nom, detail: scene.description) { [weak self] in self?.appliquer(scene) })
        }
        liste += [
            Choix(titre: "Bilan du jour", detail: nil) { [weak self] in self?.afficherBilan() },
            Choix(titre: "Ranger les téléchargements maintenant", detail: nil) { [weak self] in self?.telechargements.ranger(manuel: true) },
            Choix(titre: "Réglages de Majordome", detail: nil) { [weak self] in self?.ouvrirReglages() },
        ]
        Selecteur.partage.afficher(indication: "Majordome : que veux-tu faire ?") { Selecteur.filtrer(liste, $0) }
    }

    private func ouvrirFocus() {
        Selecteur.partage.afficher(indication: "Sur quoi te concentres-tu ?") { [weak self] texte in
            guard let self else { return [] }
            if let e = self.focus.etat {
                return [
                    Choix(titre: "Arrêter la session", detail: "\(e.tache) · encore \(self.focus.minutesRestantes) min") { self.focus.arreter() },
                    Choix(titre: "Ajouter 10 minutes", detail: e.tache) { self.focus.ajouter10() },
                ]
            }
            let q = texte.trimmingCharacters(in: .whitespaces)
            let tache = q.isEmpty ? "Concentration" : q
            return [
                Choix(titre: "50 min · \(tache)", detail: "Tape le nom de la tâche, puis Entrée") { self.focus.demarrer(minutes: 50, tache: tache) },
                Choix(titre: "25 min · \(tache)", detail: nil) { self.focus.demarrer(minutes: 25, tache: tache) },
                Choix(titre: "90 min · \(tache)", detail: "Travail de fond") { self.focus.demarrer(minutes: 90, tache: tache) },
            ]
        }
    }

    private func ouvrirIdee() {
        Selecteur.partage.afficher(indication: "Une idée, une tâche… puis Entrée") { texte in
            let q = texte.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { return [] }
            return [Choix(titre: q, detail: "Ajouter à ~/Documents/inbox.md") {
                Disque.creerDossier(Chemins.inbox.deletingLastPathComponent())
                Disque.ajouter(Chemins.inbox, Journal.ligneIdee(q, quand: Format.date("dd/MM HH:mm")))
                Toast.afficher("Noté dans ta boîte de réception", duree: 1.5)
            }]
        }
    }

    private func ouvrirPresse() {
        let liste = presse.choix()
        Selecteur.partage.afficher(indication: "Transformer le presse-papiers…") { Selecteur.filtrer(liste, $0) }
    }

    // MARK: - Priorités, scènes, bilans

    private func ecrirePriorites(_ liste: [Priorite]) {
        priorites = liste
        Disque.ecrire(Chemins.priorites, Journal.ecrirePriorites(liste))
        majTitre()
    }

    private func demanderPriorites() {
        var liste: [Priorite] = []
        for i in 1...3 {
            let aide = i == 1 ? "Celle qui rendra ta journée réussie, même si tu ne fais rien d'autre."
                              : "Laisse vide et clique sur Terminer pour t'arrêter là."
            let r = Invite.demander(titre: "Priorité \(i) sur 3", message: aide, bouton: "Suivant", autre: "Terminer")
            if !r.texte.isEmpty { liste.append(Priorite(texte: r.texte)) }
            if !r.premier { break }
        }
        Disque.ecrire(Chemins.rituel, Format.jour)
        if let premiere = liste.first {
            ecrirePriorites(liste)
            Toast.afficher("Priorité n° 1 : " + premiere.texte, duree: 3)
        }
    }

    private func prioritesDuJour() -> Bool {
        guard let d = Disque.dateModification(Chemins.priorites) else { return false }
        return Format.date("yyyy-MM-dd", d) == Format.jour
    }

    /// Au premier déverrouillage du matin (entre 5 h et 14 h), une seule fois par jour.
    private func rituelSiBesoin() {
        guard R.oui("rituelMatin") else { return }
        let heure = Calendar.current.component(.hour, from: Date())
        guard heure >= 5, heure < 14, !(Disque.lire(Chemins.rituel) ?? "").contains(Format.jour), !prioritesDuJour() else { return }
        Disque.ecrire(Chemins.rituel, Format.jour)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.demanderPriorites() }
    }

    private func appliquer(_ scene: SceneTravail) {
        for bundle in scene.apps { Systeme.lancer(bundle: bundle) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            for (bundle, u) in scene.disposition {
                guard let app = Systeme.appEnCours(bundle) else { continue }
                let el = AXUIElementCreateApplication(app.processIdentifier)
                let principale = AX.attribut(el, kAXMainWindowAttribute).map { $0 as! AXUIElement }
                guard let w = principale ?? AX.fenetres(pid: app.processIdentifier).first(where: AX.estStandard),
                      let f = AX.cadre(w), let ecran = Ecrans.ecran(contenant: f) else { continue }
                let zone = Ecrans.versAX(ecran.visibleFrame)
                AX.poser(w, CGRect(x: zone.minX + u.x * zone.width, y: zone.minY + u.y * zone.height,
                                   width: u.w * zone.width, height: u.h * zone.height).integral)
            }
            if let premiere = scene.apps.first { Systeme.appEnCours(premiere)?.activate(options: []) }
            if scene.cacherAutres { self.cacherAutres(garder: Set(scene.apps)) }
            if let m = scene.monotache, m != self.monotache { self.basculerMonotache() }
            if let minutes = scene.focus { self.focus.demarrer(minutes: minutes, tache: scene.nom) }
            Toast.afficher("Scène : " + scene.nom, duree: 1.5)
        }
    }

    private func debutDeJournee() {
        if pile.dessus?.note.hasPrefix("Fin de journée") == true { pile.reprendre() }
        appliquer(SceneTravail(nom: "Début de journée", description: "", apps: ["com.apple.iCal", "com.apple.reminders"],
                        disposition: ["com.apple.iCal": Unite(0, 0, 0.6, 1), "com.apple.reminders": Unite(0.6, 0, 0.4, 1)]))
        if !prioritesDuJour() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.demanderPriorites() }
        }
    }

    private func finDeJournee() {
        pile.pousser(note: "Fin de journée du " + Format.date("dd/MM"))
        cacherAutres(garder: [])
        Toast.afficher("Bonne soirée.\n" + texteBilan(), duree: 8)
    }

    private func texteBilan() -> String {
        journal.vider()
        let st = Journal.stats(jour: Format.jour, focus: Disque.lire(Chemins.journal),
                               reunions: Disque.lire(Chemins.reunions), apps: Disque.lire(Chemins.temps()))
        return Journal.texteBilan(st, objectif: R.objectifMinutes)
    }

    private func afficherBilan() { Toast.afficher("Bilan du jour\n" + texteBilan(), duree: 7) }

    private func tableauDeBord() {
        journal.vider()
        let st = Journal.stats(jour: Format.jour, focus: Disque.lire(Chemins.journal), reunions: nil, apps: nil)
        var lignes = [Format.date("HH:mm") + "   " + Divers.dateLongue(Date())]
        if let p = Journal.prochainePriorite(priorites) { lignes.append(numeros[min(p.numero, 5) - 1] + " " + p.texte) }
        if let e = focus.etat { lignes.append("Focus : \(e.tache) · encore \(focus.minutesRestantes) min") }
        if reunions.debut != nil { lignes.append("Réunion en cours : " + Journal.duree(reunions.minutes)) }
        lignes.append("Concentration : \(Journal.duree(st.focus)) sur \(Journal.duree(R.objectifMinutes))")
        let b = Systeme.batterie()
        if let texte = Divers.texteBatterie(pourcentage: b.pourcentage, minutes: b.minutes, secteur: b.secteur) { lignes.append(texte) }
        let n = pile.taille
        if n > 0 { lignes.append("\(n) contexte\(n > 1 ? "s" : "") mis de côté (Hyper + O)") }
        Toast.afficher(lignes.joined(separator: "\n"), duree: 5, grand: true)
    }

    /// Le rapport du soir, à l'heure choisie dans les réglages.
    private func planifierRapport() {
        minuteurRapport?.invalidate()
        let morceaux = R.heureRapport.split(separator: ":").compactMap { Int($0) }
        guard morceaux.count == 2,
              let prochaine = Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: morceaux[0], minute: morceaux[1]),
                                                        matchingPolicy: .nextTime) else { return }
        let t = Timer(fire: prochaine, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            Systeme.notifier("Ta journée", self.texteBilan(), son: false)
            self.planifierRapport()
        }
        RunLoop.main.add(t, forMode: .common)
        minuteurRapport = t
    }

    // MARK: - Barre des menus

    private func installerMenu() {
        let e = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        e.menu = menu
        element = e
        majTitre()
    }

    func majTitre() {
        var parts: [String] = []
        if eveil.actif { parts.append("☀︎") }
        if monotache { parts.append("◉") }
        if reunions.debut != nil { parts.append("● \(reunions.minutes) min") }
        if focus.etat != nil {
            parts.append("◔ \(focus.minutesRestantes) min")
        } else if let p = Journal.prochainePriorite(priorites) {
            parts.append(numeros[min(p.numero, 5) - 1] + " " + Texte.tronquer(p.texte, 26))
        } else {
            parts.append("◇")
        }
        element?.button?.title = parts.joined(separator: "  ")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(ElementMenu("Priorités du jour", actif: false) {})
        for (i, p) in priorites.enumerated() {
            menu.addItem(ElementMenu(p.texte, coche: p.fait) { [weak self] in
                guard let self else { return }
                var liste = self.priorites
                liste[i].fait.toggle()
                self.ecrirePriorites(liste)
            })
        }
        menu.addItem(ElementMenu(priorites.isEmpty ? "Définir mes priorités…" : "Redéfinir les priorités…") { [weak self] in self?.demanderPriorites() })
        menu.addItem(.separator())
        if let e = focus.etat {
            menu.addItem(ElementMenu("Focus : \(e.tache) · encore \(focus.minutesRestantes) min", actif: false) {})
            menu.addItem(ElementMenu("Ajouter 10 minutes") { [weak self] in self?.focus.ajouter10() })
            menu.addItem(ElementMenu("Arrêter la session") { [weak self] in self?.focus.arreter() })
        } else {
            menu.addItem(ElementMenu("Démarrer un focus…   Hyper G") { [weak self] in self?.ouvrirFocus() })
        }
        menu.addItem(ElementMenu("Monotâche   Hyper U", coche: monotache) { [weak self] in self?.basculerMonotache() })
        menu.addItem(ElementMenu("Écran toujours allumé", coche: eveil.actif) { [weak self] in self?.basculerEveil() })
        let n = pile.taille
        menu.addItem(ElementMenu("Mettre de côté…   Hyper P") { [weak self] in self?.pile.pousser() })
        menu.addItem(ElementMenu("Reprendre (\(n) en attente)   Hyper O", actif: n > 0) { [weak self] in self?.pile.reprendre() })
        menu.addItem(.separator())
        menu.addItem(ElementMenu("Bilan du jour") { [weak self] in self?.afficherBilan() })
        menu.addItem(ElementMenu("Ranger les téléchargements") { [weak self] in self?.telechargements.ranger(manuel: true) })
        menu.addItem(.separator())
        menu.addItem(ElementMenu("Bienvenue…") { [weak self] in self?.montrerBienvenue() })
        menu.addItem(ElementMenu("Réglages…", raccourci: ",") { [weak self] in self?.ouvrirReglages() })
        menu.addItem(ElementMenu("À propos de Majordome") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(options: [
                .credits: NSAttributedString(string: "Ton Mac, réglé pour aller vite. Une seule app en arrière-plan, qui ne fait presque rien quand tu ne fais rien."),
            ])
        })
        menu.addItem(ElementMenu("Quitter Majordome", raccourci: "q") { NSApp.terminate(nil) })
    }

    // MARK: - Fenêtres de l'app

    private func ouvrir<V: View>(_ vue: V, titre: String, fenetre: inout NSWindow?) {
        if fenetre == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: vue))
            w.title = titre
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            fenetre = w
        }
        NSApp.activate(ignoringOtherApps: true)
        fenetre?.makeKeyAndOrderFront(nil)
    }

    func montrerBienvenue() {
        ouvrir(VueBienvenue(fermer: { [weak self] in
            R.bienvenueVue = true
            self?.fenetreBienvenue?.close()
            Toast.afficher("Essaie : maintiens Verr. Maj et appuie sur Espace", duree: 3)
        }), titre: "Bienvenue", fenetre: &fenetreBienvenue)
    }

    func ouvrirReglages() {
        ouvrir(VueReglages(), titre: "Réglages de Majordome", fenetre: &fenetreReglages)
    }
}

/// Élément de menu qui exécute un bloc.
final class ElementMenu: NSMenuItem {
    private let bloc: () -> Void

    init(_ titre: String, coche: Bool = false, actif: Bool = true, raccourci: String = "", _ bloc: @escaping () -> Void) {
        self.bloc = bloc
        super.init(title: titre, action: actif ? #selector(executer) : nil, keyEquivalent: raccourci)
        target = self
        state = coche ? .on : .off
        isEnabled = actif
    }

    required init(coder: NSCoder) { fatalError("init(coder:) non utilisé") }

    @objc private func executer() { bloc() }
}

/// Un espace de travail complet en une commande (Hyper + Espace, puis son nom).
struct SceneTravail {
    let nom: String
    let description: String
    let apps: [String]
    let disposition: [String: Unite]
    var cacherAutres = false
    var monotache: Bool? = nil
    var focus: Int? = nil
}

enum Scenes {
    static func toutes() -> [SceneTravail] {
        let xcode = R.app("x") ?? "com.apple.dt.Xcode"
        let terminal = R.app("t") ?? "com.apple.Terminal"
        let navigateur = R.app("b") ?? "com.apple.Safari"
        let notes = R.app("n") ?? "com.apple.Notes"
        let mail = R.app("e") ?? "com.apple.mail"
        let messages = R.app("s") ?? "com.apple.MobileSMS"
        return [
            SceneTravail(nom: "Coder", description: "Xcode à gauche, terminal et navigateur à droite", apps: [xcode, terminal, navigateur],
                  disposition: [xcode: Unite(0, 0, 0.65, 1), terminal: Unite(0.65, 0, 0.35, 0.5), navigateur: Unite(0.65, 0.5, 0.35, 0.5)],
                  cacherAutres: true),
            SceneTravail(nom: "Écrire", description: "Notes au centre, monotâche et 50 min de focus", apps: [notes],
                  disposition: [notes: Unite(0.17, 0, 0.66, 1)], cacherAutres: true, monotache: true, focus: 50),
            SceneTravail(nom: "Messages", description: "Mail et Messages côte à côte, pour un seul passage", apps: [mail, messages],
                  disposition: [mail: Unite(0, 0, 0.6, 1), messages: Unite(0.6, 0, 0.4, 1)], cacherAutres: true, monotache: false),
        ]
    }
}
