import AppKit
import Carbon.HIToolbox

/// Raccourci clavier global (API Carbon de macOS) : aucune autorisation requise, aucun coût au repos.
final class Raccourci {
    private static var suivant: UInt32 = 1
    private static var actions: [UInt32: (Bool) -> Void] = [:]
    private static var gestionnaireInstalle = false

    private var reference: EventHotKeyRef?
    private let identifiant: UInt32

    static let hyper = UInt32(cmdKey | optionKey | controlKey | shiftKey)
    static let ctrlAlt = UInt32(controlKey | optionKey)

    /// action(true) à l'appui, action(false) au relâchement.
    init?(code: Int, modificateurs: UInt32, action: @escaping (Bool) -> Void) {
        Raccourci.installerGestionnaire()
        identifiant = Raccourci.suivant
        Raccourci.suivant += 1
        let id = EventHotKeyID(signature: OSType(0x4D414A44), id: identifiant)  // 'MAJD'
        guard RegisterEventHotKey(UInt32(code), modificateurs, id, GetApplicationEventTarget(), 0, &reference) == noErr else {
            return nil
        }
        Raccourci.actions[identifiant] = action
    }

    func supprimer() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        Raccourci.actions[identifiant] = nil
    }

    private static func installerGestionnaire() {
        guard !gestionnaireInstalle else { return }
        gestionnaireInstalle = true
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, evenement, _ -> OSStatus in
            guard let evenement else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(evenement, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let appui = GetEventKind(evenement) == UInt32(kEventHotKeyPressed)
            Raccourci.actions[id.id]?(appui)
            return noErr
        }, 2, &types, nil, nil)
    }
}

/// Verr. Maj, devenue F18 grâce à hidutil, sert de touche Hyper :
/// maintenue + une lettre → action ; tapée seule → Échap.
final class ToucheHyper {
    private var liaisons: [(code: Int, action: () -> Void)] = []
    private var permanents: [Raccourci] = []
    private var actifs: [Raccourci] = []
    private var f18: Raccourci?
    private var utilisee = false
    private var debut = Date()

    func lier(_ code: Int, _ action: @escaping () -> Void) {
        liaisons.append((code, action))
        // ⌘⌥⌃⇧ + touche marche aussi, par exemple sur un clavier sans Verr. Maj.
        if let r = Raccourci(code: code, modificateurs: Raccourci.hyper, action: { appui in if appui { action() } }) {
            permanents.append(r)
        }
    }

    func demarrer() {
        f18 = Raccourci(code: kVK_F18, modificateurs: 0) { [weak self] appui in
            if appui { self?.entrer() } else { self?.sortir() }
        }
    }

    func toutRetirer() {
        (permanents + actifs).forEach { $0.supprimer() }
        f18?.supprimer()
        permanents = []
        actifs = []
        liaisons = []
        f18 = nil
    }

    private func entrer() {
        guard actifs.isEmpty else { return }
        utilisee = false
        debut = Date()
        for l in liaisons {
            let action = l.action
            if let r = Raccourci(code: l.code, modificateurs: 0, action: { [weak self] appui in
                guard appui else { return }
                self?.utilisee = true
                action()
            }) {
                actifs.append(r)
            }
        }
    }

    private func sortir() {
        actifs.forEach { $0.supprimer() }
        actifs = []
        if !utilisee && Date().timeIntervalSince(debut) < 0.5 { Clavier.taper(kVK_Escape) }
    }
}
