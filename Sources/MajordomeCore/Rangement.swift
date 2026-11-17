import Foundation

/// Téléchargements rangés et captures d'écran nommées.
public enum Rangement {
    static let categories: [String: [String]] = [
        "Images": ["png", "jpg", "jpeg", "gif", "heic", "webp", "svg", "tif", "tiff", "bmp", "avif"],
        "PDF": ["pdf"],
        "Documents": ["doc", "docx", "pages", "txt", "rtf", "md", "odt", "xls", "xlsx", "numbers", "csv",
                      "ppt", "pptx", "key", "epub"],
        "Archives": ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz"],
        "Installeurs": ["dmg", "pkg", "mpkg", "ipa"],
        "Vidéos": ["mp4", "mov", "mkv", "avi", "webm", "m4v"],
        "Audio": ["mp3", "wav", "m4a", "aac", "flac", "aiff", "ogg"],
        "Code": ["json", "js", "ts", "py", "swift", "sh", "html", "css", "xml", "yaml", "yml", "sql"],
    ]
    static let extCategorie: [String: String] = {
        var table: [String: String] = [:]
        for (categorie, extensions) in categories { for e in extensions { table[e] = categorie } }
        return table
    }()
    static let enCours: Set<String> = ["download", "crdownload", "part", "partial", "opdownload"]

    /// Le dossier de rangement d'un fichier, ou nil s'il faut le laisser (caché, en cours).
    public static func categorie(_ nom: String) -> String? {
        if nom.hasPrefix(".") { return nil }
        guard let point = nom.lastIndex(of: "."), point != nom.startIndex else { return "Autres" }
        let ext = nom[nom.index(after: point)...].lowercased()
        if ext.isEmpty { return "Autres" }
        if enCours.contains(ext) { return nil }
        return extCategorie[ext] ?? "Autres"
    }

    /// Premier nom libre : « nom.ext », puis « nom (2).ext »…
    public static func nomLibre(_ dossier: String, _ nom: String, existe: (String) -> Bool) -> String? {
        let chemin = dossier + "/" + nom
        if !existe(chemin) { return chemin }
        var racine = nom
        var ext = ""
        if let point = nom.lastIndex(of: "."), point != nom.startIndex {
            racine = String(nom[..<point])
            ext = String(nom[point...])
        }
        for i in 2...999 {
            let candidat = "\(dossier)/\(racine) (\(i))\(ext)"
            if !existe(candidat) { return candidat }
        }
        return nil
    }

    static let prefixesCapture = ["Capture d’écran", "Capture d'écran", "Screenshot", "Enregistrement de l’écran",
                                  "Enregistrement de l'écran", "Screen Recording"]

    public static func estCaptureBrute(_ nom: String) -> Bool {
        prefixesCapture.contains { nom.hasPrefix($0) }
    }

    /// « Capture d’écran 2026-11-14 à 18.05.33.png » → « 2026-11-14 18.05.33 · Xcode.png »
    public static func nomCapture(_ nom: String, app: String?) -> String? {
        guard let rDate = nom.range(of: "\\d{4}-\\d{2}-\\d{2}", options: .regularExpression),
              let rHeure = nom.range(of: "\\d{1,2}[.:h]\\d{2}[.:m]\\d{2}", options: .regularExpression) else { return nil }
        let date = String(nom[rDate])
        let heure = String(nom[rHeure]).replacingOccurrences(of: "[:hm]", with: ".", options: .regularExpression)
        var ext = ".png"
        if let point = nom.lastIndex(of: ".") { ext = String(nom[point...]) }
        var suffixe = ""
        if let app, !app.isEmpty {
            suffixe = " · " + app.replacingOccurrences(of: "[/:]", with: "-", options: .regularExpression)
        }
        return date + " " + heure + suffixe + ext
    }
}
