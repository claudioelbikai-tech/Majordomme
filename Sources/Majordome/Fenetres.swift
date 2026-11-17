import AppKit
import ApplicationServices
import Carbon.HIToolbox
import MajordomeCore

/// Accès aux fenêtres des autres apps (autorisation Accessibilité).
enum AX {
    static func attribut(_ el: AXUIElement, _ nom: String) -> CFTypeRef? {
        var valeur: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, nom as CFString, &valeur) == .success ? valeur : nil
    }

    static func fenetreActive() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let v = attribut(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute) else { return nil }
        return (v as! AXUIElement)
    }

    static func fenetres(pid: pid_t) -> [AXUIElement] {
        (attribut(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }

    static func cadre(_ w: AXUIElement) -> CGRect? {
        guard let p = attribut(w, kAXPositionAttribute), let s = attribut(w, kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero
        var taille = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &position)
        AXValueGetValue(s as! AXValue, .cgSize, &taille)
        return CGRect(origin: position, size: taille)
    }

    static func poser(_ w: AXUIElement, _ r: CGRect) {
        var position = r.origin
        var taille = r.size
        guard let p = AXValueCreate(.cgPoint, &position), let s = AXValueCreate(.cgSize, &taille) else { return }
        AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, s)
        AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, p)
        AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, s)
    }

    static func titre(_ w: AXUIElement) -> String { attribut(w, kAXTitleAttribute) as? String ?? "" }

    static func estStandard(_ w: AXUIElement) -> Bool {
        (attribut(w, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole
    }

    static func estReduite(_ w: AXUIElement) -> Bool { attribut(w, kAXMinimizedAttribute) as? Bool ?? false }

    static func deReduire(_ w: AXUIElement) {
        AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    }

    static func lever(_ w: AXUIElement) {
        AXUIElementPerformAction(w, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    static func proches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 3 && abs(a.minY - b.minY) < 3 && abs(a.width - b.width) < 3 && abs(a.height - b.height) < 3
    }
}

/// Conversion entre les repères d'AppKit (origine en bas) et d'Accessibilité (origine en haut).
enum Ecrans {
    static var hauteurPrincipale: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func versAX(_ r: NSRect) -> CGRect {
        CGRect(x: r.minX, y: hauteurPrincipale - r.maxY, width: r.width, height: r.height)
    }

    static func versAppKit(_ r: CGRect) -> NSRect {
        NSRect(x: r.minX, y: hauteurPrincipale - r.maxY, width: r.width, height: r.height)
    }

    static func ecran(contenant r: CGRect) -> NSScreen? {
        let centre = CGPoint(x: r.midX, y: r.midY)
        return NSScreen.screens.first { versAX($0.frame).contains(centre) } ?? NSScreen.main
    }
}

/// Fenêtre visible à l'écran, de l'avant vers l'arrière.
struct FenetreVisible {
    let pid: pid_t
    let app: NSRunningApplication
    let bornes: CGRect
    let element: AXUIElement?
}

enum ListeFenetres {
    static func visibles() -> [FenetreVisible] {
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var resultat: [FenetreVisible] = []
        var parPid: [pid_t: [AXUIElement]] = [:]
        for info in infos {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier,
                  let dico = info[kCGWindowBounds as String] as? NSDictionary,
                  let bornes = CGRect(dictionaryRepresentation: dico as CFDictionary),
                  bornes.width > 60, bornes.height > 40 else { continue }
            if parPid[pid] == nil { parPid[pid] = AX.fenetres(pid: pid) }
            let element = parPid[pid]?.first { AX.cadre($0).map { AX.proches($0, bornes) } ?? false }
            resultat.append(FenetreVisible(pid: pid, app: app, bornes: bornes, element: element))
        }
        return resultat
    }
}

// MARK: - Fenêtres au clavier (⌃⌥ + flèches, Hyper + ← →)

final class GestionFenetres {
    private var avantPlein: [Int: CGRect] = [:]

    func deplacer(_ direction: String) {
        guard Systeme.accessibiliteOK() else { demanderAccessibilite(); return }
        guard let w = AX.fenetreActive(), let f = AX.cadre(w), let ecran = Ecrans.ecran(contenant: f) else { return }
        let zone = Ecrans.versAX(ecran.visibleFrame)
        let actuelle = Unite((f.minX - zone.minX) / zone.width, (f.minY - zone.minY) / zone.height,
                             f.width / zone.width, f.height / zone.height)
        let cle = Int(CFHash(w))
        if direction == "plein" {
            if Geometrie.estPlein(actuelle), let avant = avantPlein[cle] {
                AX.poser(w, avant)
                avantPlein[cle] = nil
            } else {
                avantPlein[cle] = f
                AX.poser(w, zone)
            }
            return
        }
        guard let u = Geometrie.suivante(actuelle, direction) else { return }
        AX.poser(w, CGRect(x: zone.minX + u.x * zone.width, y: zone.minY + u.y * zone.height,
                           width: u.w * zone.width, height: u.h * zone.height).integral)
    }

    /// Envoie la fenêtre active sur l'écran voisin, à la même place relative.
    func ecranVoisin(_ sens: Int) {
        guard Systeme.accessibiliteOK() else { demanderAccessibilite(); return }
        let ecrans = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
        guard ecrans.count > 1, let w = AX.fenetreActive(), let f = AX.cadre(w),
              let actuel = Ecrans.ecran(contenant: f), let i = ecrans.firstIndex(of: actuel) else { return }
        let cible = ecrans[(i + sens + ecrans.count) % ecrans.count]
        let de = Ecrans.versAX(actuel.visibleFrame), vers = Ecrans.versAX(cible.visibleFrame)
        let rx = (f.minX - de.minX) / de.width, ry = (f.minY - de.minY) / de.height
        let largeur = min(f.width, vers.width), hauteur = min(f.height, vers.height)
        AX.poser(w, CGRect(x: vers.minX + rx * vers.width, y: vers.minY + ry * vers.height, width: largeur, height: hauteur).integral)
    }

    func demanderAccessibilite() {
        Toast.afficher("Majordome a besoin de l'accès Accessibilité pour ranger tes fenêtres.\nRéglages Système → Confidentialité et sécurité → Accessibilité", duree: 5)
        _ = Systeme.accessibiliteOK(demander: true)
    }
}

// MARK: - Hyper + J : une lettre sur chaque fenêtre

final class PanneauClavier: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class Indices {
    private var bulles: [NSWindow] = []
    private var capteur: PanneauClavier?
    private var cibles: [String: FenetreVisible] = [:]

    func afficher() {
        guard Systeme.accessibiliteOK() else { GestionFenetres().demanderAccessibilite(); return }
        fermer()
        let fenetres = Array(ListeFenetres.visibles().prefix(26))
        guard !fenetres.isEmpty else { return }
        let lettres = Divers.lettresIndices(fenetres.map { $0.app.localizedName ?? "?" })
        for (fenetre, lettre) in zip(fenetres, lettres) {
            cibles[lettre] = fenetre
            let cadre = Ecrans.versAppKit(fenetre.bornes)
            let taille = NSSize(width: 64, height: 64)
            let bulle = NSWindow(contentRect: NSRect(x: cadre.midX - taille.width / 2, y: cadre.midY - taille.height / 2,
                                                     width: taille.width, height: taille.height),
                                 styleMask: .borderless, backing: .buffered, defer: false)
            bulle.isOpaque = false
            bulle.backgroundColor = .clear
            bulle.level = .popUpMenu
            bulle.ignoresMouseEvents = true
            bulle.hasShadow = true
            let fond = NSView(frame: NSRect(origin: .zero, size: taille))
            fond.wantsLayer = true
            fond.layer?.backgroundColor = NSColor(calibratedRed: 0.09, green: 0.1, blue: 0.12, alpha: 0.95).cgColor
            fond.layer?.cornerRadius = 14
            let texte = NSTextField(labelWithString: lettre)
            texte.font = .monospacedSystemFont(ofSize: 34, weight: .bold)
            texte.textColor = NSColor(calibratedRed: 0.94, green: 0.68, blue: 0.24, alpha: 1)
            texte.alignment = .center
            texte.frame = NSRect(x: 0, y: (taille.height - 42) / 2, width: taille.width, height: 42)
            fond.addSubview(texte)
            bulle.contentView = fond
            bulle.orderFrontRegardless()
            bulles.append(bulle)
        }
        // Panneau invisible qui reçoit la lettre tapée (Échap ou clic pour annuler).
        let ecran = NSScreen.main?.frame ?? .zero
        let capteur = PanneauClavier(contentRect: ecran, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        capteur.isOpaque = false
        capteur.backgroundColor = NSColor.black.withAlphaComponent(0.001)
        capteur.level = .popUpMenu
        let vue = VueCapteur(frame: NSRect(origin: .zero, size: ecran.size))
        vue.touche = { [weak self] caractere in self?.choisir(caractere) }
        capteur.contentView = vue
        capteur.makeKeyAndOrderFront(nil)
        capteur.makeFirstResponder(vue)
        self.capteur = capteur
    }

    private func choisir(_ caractere: String?) {
        let cible = caractere.flatMap { cibles[$0.uppercased()] }
        fermer()
        guard let cible else { return }
        cible.app.activate(options: [])
        if let element = cible.element { AX.lever(element) }
    }

    func fermer() {
        bulles.forEach { $0.orderOut(nil) }
        bulles = []
        capteur?.orderOut(nil)
        capteur = nil
        cibles = [:]
    }
}

final class VueCapteur: NSView {
    var touche: ((String?) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        touche?(event.keyCode == UInt16(kVK_Escape) ? nil : event.charactersIgnoringModifiers)
    }
    override func mouseDown(with event: NSEvent) { touche?(nil) }
}
