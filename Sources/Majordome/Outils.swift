import AppKit
import ApplicationServices
import Carbon.HIToolbox
import IOKit.ps
import IOKit.pwr_mgt
import ServiceManagement
import UserNotifications

// MARK: - Fichiers partagés avec le terminal (~/.majordome)

enum Chemins {
    static let maison = FileManager.default.homeDirectoryForCurrentUser
    static let dossier = maison.appendingPathComponent(".majordome")
    static let focus = dossier.appendingPathComponent("focus")
    static let journal = dossier.appendingPathComponent("focus.log")
    static let reunions = dossier.appendingPathComponent("reunions.log")
    static let priorites = dossier.appendingPathComponent("priorites.txt")
    static let pile = dossier.appendingPathComponent("pile.json")
    static let ici = dossier.appendingPathComponent("ici")
    static let fonds = dossier.appendingPathComponent("fonds-avant.json")
    static let rituel = dossier.appendingPathComponent("rituel")
    static let fondImage = dossier.appendingPathComponent("fond-focus.png")
    static let inbox = maison.appendingPathComponent("Documents/inbox.md")
    static let captures = maison.appendingPathComponent("Pictures/Captures")
    static let telechargements = maison.appendingPathComponent("Downloads")

    static func temps(_ date: Date = Date()) -> URL {
        dossier.appendingPathComponent("temps-" + Format.date("yyyy-MM", date) + ".tsv")
    }
}

enum Format {
    static func date(_ motif: String, _ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = motif
        return f.string(from: date)
    }
    static var jour: String { date("yyyy-MM-dd") }
}

enum Disque {
    static func lire(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    @discardableResult
    static func ecrire(_ url: URL, _ texte: String) -> Bool {
        (try? texte.write(to: url, atomically: true, encoding: .utf8)) != nil
    }

    static func ajouter(_ url: URL, _ texte: String) {
        guard let donnees = texte.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(donnees)
            try? h.close()
        } else {
            ecrire(url, texte)
        }
    }

    static func existe(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    static func existe(_ chemin: String) -> Bool { FileManager.default.fileExists(atPath: chemin) }
    static func supprimer(_ url: URL) { try? FileManager.default.removeItem(at: url) }
    static func creerDossier(_ url: URL) { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }

    static func dateModification(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

/// Prévient quand le contenu d'un dossier change (création, suppression, renommage). Aucune boucle.
final class Surveillant {
    private let source: DispatchSourceFileSystemObject

    init?(_ dossier: URL, _ action: @escaping () -> Void) {
        let descripteur = open(dossier.path, O_EVTONLY)
        guard descripteur >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descripteur, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler(handler: action)
        source.setCancelHandler { close(descripteur) }
        source.resume()
    }

    deinit { source.cancel() }
}

// MARK: - Petites briques système

enum Script {
    /// Exécute un AppleScript ; nil en cas d'erreur (ou d'autorisation refusée).
    @discardableResult
    static func executer(_ source: String) -> String? {
        var erreur: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let resultat = script.executeAndReturnError(&erreur)
        if erreur != nil { return nil }
        return resultat.stringValue ?? ""
    }
}

enum Clavier {
    static func taper(_ code: Int, drapeaux: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        for appui in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: appui)
            e?.flags = drapeaux
            e?.post(tap: .cghidEventTap)
        }
    }

    static func coller() { taper(kVK_ANSI_V, drapeaux: .maskCommand) }

    /// Tape un texte caractère par caractère (pour les champs qui refusent le collage).
    static func ecrire(_ texte: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for caractere in texte {
            var unites = Array(String(caractere).utf16)
            for appui in [true, false] {
                let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: appui)
                e?.keyboardSetUnicodeString(stringLength: unites.count, unicodeString: &unites)
                e?.post(tap: .cghidEventTap)
            }
            usleep(4000)
        }
    }
}

enum Systeme {
    static func accessibiliteOK(demander: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: demander] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func ouvrirReglagesAccessibilite() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // Verr. Maj (0x39) devient F18 (0x6D) : réglage du système de clavier de macOS, sans pilote.
    static let mappageVerrMaj = #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}"#

    static func appliquerVerrMaj(_ actif: Bool) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        p.arguments = ["property", "--set", actif ? mappageVerrMaj : #"{"UserKeyMapping":[]}"#]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    static var lancementAuDemarrage: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                Toast.afficher("Ouverture au démarrage : réglage refusé par macOS.\nRéglages Système → Général → Ouverture.", duree: 4)
            }
        }
    }

    static func demanderNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notifier(_ titre: String, _ texte: String, son: Bool = true) {
        let contenu = UNMutableNotificationContent()
        contenu.title = titre
        contenu.body = texte
        if son { contenu.sound = UNNotificationSound(named: UNNotificationSoundName("Glass")) }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: contenu, trigger: nil))
    }

    /// Secondes depuis la dernière action au clavier ou à la souris.
    static var inactivite: TimeInterval {
        guard let tout = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: tout)
    }

    static func batterie() -> (pourcentage: Double?, minutes: Int?, secteur: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let liste = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return (nil, nil, true) }
        for source in liste {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let actuelle = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let secteur = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return (Double(actuelle) * 100 / Double(max), d[kIOPSTimeToEmptyKey] as? Int, secteur)
        }
        return (nil, nil, true)
    }

    static var sonCoupe: Bool { Script.executer("output muted of (get volume settings)") == "true" }

    static func couperSon(_ coupe: Bool) {
        Script.executer(coupe ? "set volume with output muted" : "set volume without output muted")
    }

    static func basculerModeSombre() -> Bool {
        Script.executer(#"tell application "System Events" to tell appearance preferences to set dark mode to not dark mode"#) != nil
    }

    static func lancer(bundle: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            Toast.afficher("App introuvable : \(bundle)\nChange-la dans Réglages → Raccourcis.", duree: 3)
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func appEnCours(_ bundle: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
    }

    static var hammerspoonAvecMajordome: Bool {
        let initLua = Chemins.maison.appendingPathComponent(".hammerspoon/init.lua")
        return (Disque.lire(initLua) ?? "").contains("require(\"majordome\")")
    }

    /// Retire l'ancienne version (Hammerspoon) pour éviter les raccourcis en double.
    static func retirerAncienneVersion() {
        let initLua = Chemins.maison.appendingPathComponent(".hammerspoon/init.lua")
        if let texte = Disque.lire(initLua) {
            let lignes = texte.components(separatedBy: "\n").filter {
                !$0.contains("require(\"majordome\")") && !$0.contains("-- Le Majordome (mac-setup-productivite.sh)")
            }
            Disque.ecrire(initLua, lignes.joined(separator: "\n"))
        }
        appEnCours("org.hammerspoon.Hammerspoon")?.terminate()
    }
}

// MARK: - Bulles d'information et questions

enum Toast {
    private static var panneau: NSPanel?
    private static var minuteur: Timer?

    static func afficher(_ texte: String, duree: TimeInterval = 2.5, grand: Bool = false) {
        minuteur?.invalidate()
        panneau?.orderOut(nil)

        let etiquette = NSTextField(wrappingLabelWithString: texte)
        etiquette.font = .systemFont(ofSize: grand ? 22 : 17, weight: .medium)
        etiquette.textColor = .white
        etiquette.alignment = grand ? .left : .center
        etiquette.maximumNumberOfLines = 0
        let taille = etiquette.sizeThatFits(NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
        let marge: CGFloat = grand ? 28 : 20
        let cadre = NSRect(x: 0, y: 0, width: ceil(taille.width) + marge * 2, height: ceil(taille.height) + marge * 2)

        let fond = NSView(frame: cadre)
        fond.wantsLayer = true
        fond.layer?.backgroundColor = NSColor(calibratedRed: 0.09, green: 0.1, blue: 0.12, alpha: 0.95).cgColor
        fond.layer?.cornerRadius = 16
        etiquette.frame = cadre.insetBy(dx: marge, dy: marge)
        fond.addSubview(etiquette)

        let p = NSPanel(contentRect: cadre, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = fond
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        if let ecran = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: ecran.midX - cadre.width / 2, y: ecran.minY + ecran.height * 0.55 - cadre.height / 2))
        }
        p.alphaValue = 1
        p.orderFrontRegardless()
        panneau = p
        minuteur = Timer.scheduledTimer(withTimeInterval: duree, repeats: false) { _ in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                p.animator().alphaValue = 0
            }, completionHandler: { p.orderOut(nil) })
        }
    }
}

enum Invite {
    /// Pose une question avec un champ texte. Renvoie le bouton choisi (true = premier) et le texte.
    static func demander(titre: String, message: String, bouton: String, autre: String) -> (premier: Bool, texte: String) {
        let precedente = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        let alerte = NSAlert()
        alerte.messageText = titre
        alerte.informativeText = message
        alerte.addButton(withTitle: bouton)
        alerte.addButton(withTitle: autre)
        let champ = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        alerte.accessoryView = champ
        alerte.window.initialFirstResponder = champ
        let reponse = alerte.runModal()
        if precedente?.bundleIdentifier != Bundle.main.bundleIdentifier { precedente?.activate(options: []) }
        return (reponse == .alertFirstButtonReturn, champ.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - Écran gardé allumé

final class Eveil {
    private var assertion: IOPMAssertionID = 0
    private(set) var actif = false

    func basculer() -> Bool {
        if actif {
            IOPMAssertionRelease(assertion)
            actif = false
        } else {
            actif = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                "Majordome : écran gardé allumé" as CFString, &assertion) == kIOReturnSuccess
        }
        return actif
    }
}
