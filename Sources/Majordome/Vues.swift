import AppKit
import SwiftUI

// MARK: - Fenêtre de bienvenue (premier lancement)

struct VueBienvenue: View {
    var fermer: () -> Void

    @State private var accessibilite = Systeme.accessibiliteOK()
    @State private var demarrage = Systeme.lancementAuDemarrage
    @State private var notifications = false
    @State private var ancienneVersion = Systeme.hammerspoonAvecMajordome
    private let minuteur = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(fermer: @escaping () -> Void) {
        self.fermer = fermer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bienvenue chez Majordome").font(.system(size: 24, weight: .bold))
                    Text("Trois réglages, et ton Mac travaille pour toi.").foregroundStyle(.secondary)
                }
            }

            Etape(numero: 1, titre: "Autoriser l'accès Accessibilité",
                  detail: "Pour la touche Hyper, ranger tes fenêtres et la pile de contexte. macOS te le demande une seule fois.",
                  fait: accessibilite) {
                Button("Ouvrir les réglages") {
                    _ = Systeme.accessibiliteOK(demander: true)
                    Systeme.ouvrirReglagesAccessibilite()
                }
            }
            Etape(numero: 2, titre: "Autoriser les notifications",
                  detail: "Pour la fin des sessions de focus et le rapport du soir.",
                  fait: notifications) {
                Button("Autoriser") {
                    Systeme.demanderNotifications()
                    notifications = true
                }
            }
            Etape(numero: 3, titre: "Ouvrir Majordome au démarrage",
                  detail: "Il reste discret dans la barre des menus, en haut à droite.",
                  fait: demarrage) {
                Toggle("", isOn: $demarrage)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: demarrage) { Systeme.lancementAuDemarrage = $0 }
            }

            if ancienneVersion {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("L'ancienne version tourne encore dans Hammerspoon").bold()
                        Text("Retire-la pour éviter les raccourcis en double. Ton Hammerspoon et tes réglages restent intacts.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Retirer l'ancienne version") {
                            Systeme.retirerAncienneVersion()
                            ancienneVersion = false
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
            }

            Divider()
            HStack {
                Text("Ensuite : maintiens Verr. Maj et appuie sur Espace.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("C'est parti", action: fermer).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 540)
        .onReceive(minuteur) { _ in accessibilite = Systeme.accessibiliteOK() }
    }
}

struct Etape<Controle: View>: View {
    let numero: Int
    let titre: String
    let detail: String
    let fait: Bool
    @ViewBuilder var controle: () -> Controle

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(fait ? Color.green : Color.accentColor.opacity(0.15)).frame(width: 30, height: 30)
                if fait {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(numero)").font(.system(size: 14, weight: .semibold, design: .rounded))
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(titre).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            controle()
        }
    }
}

// MARK: - Réglages

struct VueReglages: View {
    var body: some View {
        TabView {
            OngletGeneral().tabItem { Label("Général", systemImage: "gearshape") }
            OngletFocus().tabItem { Label("Focus", systemImage: "scope") }
            OngletAutomatique().tabItem { Label("Automatique", systemImage: "wand.and.stars") }
            OngletRaccourcis().tabItem { Label("Raccourcis", systemImage: "keyboard") }
        }
        .frame(width: 580, height: 480)
        .padding(16)
    }
}

struct OngletGeneral: View {
    @AppStorage("verrMajHyper") private var hyper = true
    @AppStorage("fenetres") private var fenetres = true
    @AppStorage("rituelMatin") private var rituel = true
    @AppStorage("objectifMinutes") private var objectif = 210
    @AppStorage("heureRapport") private var heure = "18:00"
    @State private var demarrage = Systeme.lancementAuDemarrage

    var body: some View {
        Form {
            Toggle("Ouvrir Majordome au démarrage", isOn: $demarrage)
                .onChange(of: demarrage) { Systeme.lancementAuDemarrage = $0 }
            Toggle("Verr. Maj devient la touche Hyper (tapée seule : Échap)", isOn: $hyper)
            Toggle("Fenêtres au clavier : ⌃⌥ + flèches, ⌃⌥ ↩, ⌃⌥ C, ⌃⌥ U I J K", isOn: $fenetres)
            Toggle("Me demander mes 3 priorités chaque matin", isOn: $rituel)
            Stepper(value: $objectif, in: 30...480, step: 15) {
                Text("Objectif de concentration : \(objectif / 60) h \(String(format: "%02d", objectif % 60)) par jour")
            }
            TextField("Heure du rapport du soir (HH:MM)", text: $heure)
        }
        .formStyle(.grouped)
    }
}

struct OngletFocus: View {
    @AppStorage("fondFocus") private var fond = true
    @AppStorage("bouclierSites") private var sites = true
    @AppStorage("distractions") private var distractions = ""
    @AppStorage("sitesDistraction") private var listeSites = ""

    var body: some View {
        Form {
            Toggle("Fond d'écran noir pendant un focus (ton fond revient à la fin)", isOn: $fond)
            Toggle("Cacher Safari ou Chrome s'ils affichent un site de la liste", isOn: $sites)
            Section("Apps cachées pendant un focus (une par ligne)") {
                TextEditor(text: $distractions).font(.system(.body, design: .monospaced)).frame(height: 110)
            }
            Section("Sites de distraction (un par ligne)") {
                TextEditor(text: $listeSites).font(.system(.body, design: .monospaced)).frame(height: 110)
            }
            Text("Insiste deux fois en 8 secondes pour passer quand même : la tentative est comptée dans ton bilan.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct OngletAutomatique: View {
    @AppStorage("nettoyerLiens") private var liens = true
    @AppStorage("nommerCaptures") private var captures = true
    @AppStorage("rangerTelechargements") private var ranger = true
    @AppStorage("joursAvantRangement") private var jours = 3
    @AppStorage("suivreReunions") private var reunions = true
    @AppStorage("journalApps") private var journal = true
    @AppStorage("terminalIci") private var ici = true

    var body: some View {
        Form {
            Toggle("Retirer les traqueurs des liens copiés", isOn: $liens)
            Toggle("Nommer les captures d'écran d'après l'app", isOn: $captures)
            Toggle("Ranger les téléchargements par type", isOn: $ranger)
            Stepper("Après \(jours) jour\(jours > 1 ? "s" : "")", value: $jours, in: 0...30).disabled(!ranger)
            Toggle("Compter le temps de réunion (caméra allumée)", isOn: $reunions)
            Toggle("Noter le temps passé par app (reste sur ton Mac)", isOn: $journal)
            Toggle("Hyper + T depuis le Finder ouvre le terminal dans le dossier", isOn: $ici)
            Section("Ce qui tourne en arrière-plan") {
                Text("Majordome réagit aux signaux de macOS et dort entre deux. Au repos, il regarde seulement le presse-papiers toutes les 2 secondes et l'app active une fois par minute.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

struct OngletRaccourcis: View {
    private let actions: [(String, String)] = [
        ("Espace", "Palette : toutes les actions et les scènes"), ("G", "Démarrer ou arrêter un focus"),
        ("I", "Noter une idée"), ("P", "Mettre de côté ce que je fais"), ("O", "Reprendre là où j'en étais"),
        ("H", "Tableau de bord"), ("J", "Sauter vers une fenêtre"), ("U", "Monotâche"), ("L", "Voile de confidentialité"),
        ("V", "Transformer le presse-papiers"), ("D", "Mode sombre / clair"), ("← →", "Envoyer la fenêtre sur l'écran voisin"),
    ]

    var body: some View {
        Form {
            Section("Verr. Maj + lettre : ouvre l'app, ou la cache si elle est déjà devant") {
                ForEach(R.lettresApps, id: \.self) { lettre in LigneApp(lettre: lettre) }
                Text("Pour trouver l'identifiant d'une app : osascript -e 'id of app \"Nom de l app\"'")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Section("Verr. Maj + touche : Majordome") {
                ForEach(actions.indices, id: \.self) { i in
                    HStack {
                        Text(actions[i].0).font(.system(.body, design: .monospaced)).frame(width: 64, alignment: .leading)
                        Text(actions[i].1)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct LigneApp: View {
    let lettre: String
    @AppStorage private var bundle: String

    init(lettre: String) {
        self.lettre = lettre
        _bundle = AppStorage(wrappedValue: "", "app_" + lettre)
    }

    var body: some View {
        HStack {
            Text(lettre.uppercased()).font(.system(.body, design: .monospaced)).frame(width: 24)
            Text(R.nomsLettres[lettre] ?? "").frame(width: 90, alignment: .leading).foregroundStyle(.secondary)
            TextField("identifiant de l'app", text: $bundle).font(.system(.body, design: .monospaced))
        }
    }
}
