import Foundation

/// Liens nettoyés à la copie et sites de distraction.
public enum Liens {
    static let traqueurs: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "mc_cid", "mc_eid", "igshid", "igsh",
        "yclid", "twclid", "ttclid", "_hsenc", "_hsmi", "mkt_tok", "ref_src", "ref_url", "oly_anon_id",
        "oly_enc_id", "vero_id", "rb_clickid", "s_cid", "epik", "srsltid", "_gl", "_ga", "si_source",
    ]
    /// « si » n'est un traqueur que sur ces sites (liens de partage).
    static let hotesSi = ["youtube.com", "youtu.be", "spotify.com"]

    static func finitPar(_ hote: String, _ suffixe: String) -> Bool {
        hote == suffixe || hote.hasSuffix("." + suffixe)
    }

    public static func hote(_ url: String?) -> String? {
        guard let url, let r = url.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://[^/:?#]+", options: .regularExpression),
              let separateur = url[r].range(of: "://") else { return nil }
        return String(url[separateur.upperBound..<r.upperBound]).lowercased()
    }

    public static func estSiteDistraction(_ hote: String?, _ sites: [String]) -> Bool {
        guard let hote else { return false }
        return sites.contains { finitPar(hote, $0) }
    }

    /// Le lien sans ses traqueurs, ou nil s'il n'y a rien à retirer.
    public static func nettoyer(_ texte: String?) -> (lien: String, retires: [String])? {
        guard let texte else { return nil }
        let url = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard url.range(of: "^https?://\\S+$", options: .regularExpression) != nil else { return nil }
        var fragment = ""
        var sansFragment = url
        if let diese = url.firstIndex(of: "#") {
            fragment = String(url[diese...])
            sansFragment = String(url[..<diese])
        }
        guard let point = sansFragment.firstIndex(of: "?") else { return nil }
        let base = String(sansFragment[..<point])
        let requete = String(sansFragment[sansFragment.index(after: point)...])
        let siTraqueur = estSiteDistraction(hote(base), hotesSi)
        var garder: [String] = []
        var retires: [String] = []
        for paire in requete.split(separator: "&").map(String.init) {
            let cle = (paire.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "").lowercased()
            if cle.hasPrefix("utm_") || cle.hasPrefix("pk_") || traqueurs.contains(cle) || (cle == "si" && siTraqueur) {
                retires.append(paire)
            } else {
                garder.append(paire)
            }
        }
        guard !retires.isEmpty else { return nil }
        return (base + (garder.isEmpty ? "" : "?" + garder.joined(separator: "&")) + fragment, retires)
    }
}
