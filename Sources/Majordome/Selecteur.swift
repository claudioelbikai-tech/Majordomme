import AppKit

struct Choix {
    let titre: String
    var detail: String? = nil
    let action: () -> Void
}

/// Fenêtre de recherche façon Spotlight, utilisée par la palette (Hyper + Espace),
/// le focus (Hyper + G), les idées (Hyper + I) et le presse-papiers (Hyper + V).
final class Selecteur: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    static let partage = Selecteur()

    private let largeur: CGFloat = 640
    private let hauteurChamp: CGFloat = 58
    private let hauteurLigne: CGFloat = 46
    private let panneau: PanneauClavier
    private let champ = NSTextField()
    private let table = NSTableView()
    private let defilement = NSScrollView()
    private var choix: [Choix] = []
    private var fournisseur: (String) -> [Choix] = { _ in [] }

    private override init() {
        panneau = PanneauClavier(contentRect: NSRect(x: 0, y: 0, width: 640, height: 58),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panneau.isOpaque = false
        panneau.backgroundColor = .clear
        panneau.hasShadow = true
        panneau.level = .modalPanel
        panneau.isFloatingPanel = true
        panneau.becomesKeyOnlyIfNeeded = false
        panneau.hidesOnDeactivate = false
        panneau.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panneau.delegate = self

        let fond = NSVisualEffectView()
        fond.material = .hudWindow
        fond.blendingMode = .behindWindow
        fond.state = .active
        fond.wantsLayer = true
        fond.layer?.cornerRadius = 14
        fond.layer?.masksToBounds = true
        panneau.contentView = fond

        champ.isBordered = false
        champ.drawsBackground = false
        champ.focusRingType = .none
        champ.font = .systemFont(ofSize: 22, weight: .regular)
        champ.textColor = .labelColor
        champ.delegate = self
        champ.cell?.usesSingleLineMode = true
        champ.cell?.wraps = false
        fond.addSubview(champ)

        let colonne = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("choix"))
        table.addTableColumn(colonne)
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = hauteurLigne
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clic)
        defilement.documentView = table
        defilement.drawsBackground = false
        defilement.hasVerticalScroller = false
        fond.addSubview(defilement)
    }

    /// fournisseur : la liste à afficher pour le texte tapé.
    func afficher(indication: String, fournisseur: @escaping (String) -> [Choix]) {
        self.fournisseur = fournisseur
        champ.placeholderString = indication
        champ.stringValue = ""
        rafraichir()
        let ecran = (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)?.visibleFrame ?? .zero
        let cadre = panneau.frame
        panneau.setFrameTopLeftPoint(NSPoint(x: ecran.midX - cadre.width / 2, y: ecran.maxY - ecran.height * 0.22))
        panneau.makeKeyAndOrderFront(nil)
        panneau.makeFirstResponder(champ)
        if !panneau.isKeyWindow {
            NSApp.activate(ignoringOtherApps: true)
            panneau.makeKeyAndOrderFront(nil)
            panneau.makeFirstResponder(champ)
        }
    }

    /// Filtre une liste fixe par le texte tapé (sans tenir compte des accents ni des majuscules).
    static func filtrer(_ liste: [Choix], _ texte: String) -> [Choix] {
        let q = texte.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return liste }
        return liste.filter {
            ($0.titre + " " + ($0.detail ?? "")).range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private func rafraichir() {
        choix = fournisseur(champ.stringValue)
        table.reloadData()
        if !choix.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        let lignes = min(choix.count, 8)
        let hauteurListe = CGFloat(lignes) * hauteurLigne + (lignes > 0 ? 10 : 0)
        let hauteur = hauteurChamp + hauteurListe
        var cadre = panneau.frame
        let haut = cadre.maxY
        cadre.size = NSSize(width: largeur, height: hauteur)
        cadre.origin.y = haut - hauteur
        panneau.setFrame(cadre, display: true)
        champ.frame = NSRect(x: 20, y: hauteur - hauteurChamp + 14, width: largeur - 40, height: 30)
        defilement.frame = NSRect(x: 8, y: 6, width: largeur - 16, height: hauteurListe - (lignes > 0 ? 6 : 0))
        table.tableColumns.first?.width = largeur - 16
    }

    private func bouger(_ pas: Int) {
        guard !choix.isEmpty else { return }
        let i = max(0, min(choix.count - 1, table.selectedRow + pas))
        table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        table.scrollRowToVisible(i)
    }

    private func valider() {
        let i = table.selectedRow
        guard i >= 0, i < choix.count else { return }
        let action = choix[i].action
        fermer()
        DispatchQueue.main.async(execute: action)
    }

    func fermer() { panneau.orderOut(nil) }

    @objc private func clic() { valider() }

    // MARK: Délégués

    func controlTextDidChange(_ obj: Notification) { rafraichir() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commande: Selector) -> Bool {
        switch commande {
        case #selector(NSResponder.moveDown(_:)): bouger(1)
        case #selector(NSResponder.moveUp(_:)): bouger(-1)
        case #selector(NSResponder.insertNewline(_:)): valider()
        case #selector(NSResponder.cancelOperation(_:)): fermer()
        default: return false
        }
        return true
    }

    func windowDidResignKey(_ notification: Notification) { fermer() }

    func numberOfRows(in tableView: NSTableView) -> Int { choix.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let c = choix[row]
        let vue = NSView(frame: NSRect(x: 0, y: 0, width: largeur - 16, height: hauteurLigne))
        let titre = NSTextField(labelWithString: c.titre)
        titre.font = .systemFont(ofSize: 15, weight: .medium)
        titre.lineBreakMode = .byTruncatingTail
        vue.addSubview(titre)
        if let detail = c.detail, !detail.isEmpty {
            titre.frame = NSRect(x: 14, y: 22, width: largeur - 50, height: 20)
            let sous = NSTextField(labelWithString: detail)
            sous.font = .systemFont(ofSize: 12)
            sous.textColor = .secondaryLabelColor
            sous.lineBreakMode = .byTruncatingTail
            sous.frame = NSRect(x: 14, y: 5, width: largeur - 50, height: 16)
            vue.addSubview(sous)
        } else {
            titre.frame = NSRect(x: 14, y: 13, width: largeur - 50, height: 20)
        }
        return vue
    }
}
