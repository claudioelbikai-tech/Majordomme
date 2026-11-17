import Carbon.HIToolbox
import Foundation

/// Réglages enregistrés dans les préférences de l'app (modifiables dans la fenêtre Réglages).
enum R {
    static let d = UserDefaults.standard

    /// Lettres utilisables avec Hyper : à la même place en AZERTY et en QWERTY.
    static let lettresApps = ["t", "b", "f", "x", "n", "c", "r", "e", "s", "k"]
    static let nomsLettres: [String: String] = [
        "t": "Terminal", "b": "Navigateur", "f": "Fichiers", "x": "Xcode", "n": "Notes",
        "c": "Calendrier", "r": "Rappels", "e": "Mail", "s": "Messages", "k": "Claude",
    ]
    static let codes: [String: Int] = [
        "t": kVK_ANSI_T, "b": kVK_ANSI_B, "f": kVK_ANSI_F, "x": kVK_ANSI_X, "n": kVK_ANSI_N, "c": kVK_ANSI_C,
        "r": kVK_ANSI_R, "e": kVK_ANSI_E, "s": kVK_ANSI_S, "k": kVK_ANSI_K, "g": kVK_ANSI_G, "i": kVK_ANSI_I,
        "p": kVK_ANSI_P, "o": kVK_ANSI_O, "u": kVK_ANSI_U, "l": kVK_ANSI_L, "v": kVK_ANSI_V, "h": kVK_ANSI_H,
        "j": kVK_ANSI_J, "d": kVK_ANSI_D,
    ]

    static func enregistrerDefauts() {
        d.register(defaults: [
            "objectifMinutes": 210,
            "heureRapport": "18:00",
            "rituelMatin": true,
            "verrMajHyper": true,
            "fenetres": true,
            "fondFocus": true,
            "bouclierSites": true,
            "rangerTelechargements": true,
            "joursAvantRangement": 3,
            "nommerCaptures": true,
            "nettoyerLiens": true,
            "suivreReunions": true,
            "journalApps": true,
            "terminalIci": true,
            "distractions": """
            com.apple.MobileSMS
            com.apple.mail
            net.whatsapp.WhatsApp
            com.hnc.Discord
            com.tinyspeck.slackmacgap
            ru.keepcoder.Telegram
            org.whispersystems.signal-desktop
            com.facebook.archon
            """,
            "sitesDistraction": """
            youtube.com
            instagram.com
            tiktok.com
            x.com
            twitter.com
            facebook.com
            reddit.com
            netflix.com
            twitch.tv
            linkedin.com
            """,
            "app_t": "com.mitchellh.ghostty",
            "app_b": "com.apple.Safari",
            "app_f": "com.apple.finder",
            "app_x": "com.apple.dt.Xcode",
            "app_n": "com.apple.Notes",
            "app_c": "com.apple.iCal",
            "app_r": "com.apple.reminders",
            "app_e": "com.apple.mail",
            "app_s": "com.apple.MobileSMS",
            "app_k": "com.anthropic.claudefordesktop",
        ])
    }

    static func oui(_ cle: String) -> Bool { d.bool(forKey: cle) }

    static var objectifMinutes: Int { max(15, d.integer(forKey: "objectifMinutes")) }
    static var heureRapport: String { d.string(forKey: "heureRapport") ?? "18:00" }
    static var joursAvantRangement: Int { max(0, d.integer(forKey: "joursAvantRangement")) }

    static func liste(_ cle: String) -> [String] {
        (d.string(forKey: cle) ?? "")
            .components(separatedBy: CharacterSet(charactersIn: "\n,"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static var distractions: Set<String> { Set(liste("distractions")) }
    static var sitesDistraction: [String] { liste("sitesDistraction") }

    static func app(_ lettre: String) -> String? {
        let b = (d.string(forKey: "app_" + lettre) ?? "").trimmingCharacters(in: .whitespaces)
        return b.isEmpty ? nil : b
    }

    static var bienvenueVue: Bool {
        get { d.bool(forKey: "bienvenueVue") }
        set { d.set(newValue, forKey: "bienvenueVue") }
    }
}
