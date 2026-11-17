import XCTest
@testable import MajordomeCore

final class TexteTests: XCTestCase {
    func testMajusculesEtMinuscules() {
        XCTAssertEqual(Texte.majuscules("été à l'œil, ça"), "ÉTÉ À L'ŒIL, ÇA")
        XCTAssertEqual(Texte.minuscules("ÉTÉ À L'ŒIL"), "été à l'œil")
    }

    func testTitre() {
        XCTAssertEqual(Texte.titre("le PETIT prince d'été"), "Le Petit Prince D'Été")
        XCTAssertEqual(Texte.titre("jean-éric à paris"), "Jean-Éric À Paris")
    }

    func testSlug() {
        XCTAssertEqual(Texte.slug("  Écran de Connexion — v2 (final) !"), "ecran-de-connexion-v2-final")
        XCTAssertEqual(Texte.slug("Cœur Œuvre"), "coeur-oeuvre")
    }

    func testEspacesEtCompte() {
        XCTAssertEqual(Texte.espaces("  Bonjour   le\tmonde  \n\n\n\nfin   "), "Bonjour le monde\n\nfin")
        XCTAssertEqual(Texte.compter("Un deux trois\nquatre é"), "5 mots · 22 caractères · 2 lignes")
        XCTAssertEqual(Texte.compter("seul"), "1 mot · 4 caractères · 1 ligne")
        XCTAssertEqual(Texte.tronquer("Écran de connexion très long", 10), "Écran de …")
        XCTAssertEqual(Texte.tronquer("Court", 10), "Court")
    }
}

final class LiensTests: XCTestCase {
    func testNettoyer() {
        let r = Liens.nettoyer("https://exemple.fr/article?id=42&utm_source=x&utm_medium=y&fbclid=abc#partie")
        XCTAssertEqual(r?.lien, "https://exemple.fr/article?id=42#partie")
        XCTAssertEqual(r?.retires.count, 3)
        XCTAssertEqual(Liens.nettoyer("https://youtu.be/dQw4w9WgXcQ?si=ABCDEF&t=42")?.lien, "https://youtu.be/dQw4w9WgXcQ?t=42")
        XCTAssertEqual(Liens.nettoyer("https://www.youtube.com/watch?v=abc&si=xyz")?.lien, "https://www.youtube.com/watch?v=abc")
        XCTAssertNil(Liens.nettoyer("https://example.com/search?si=keep&q=1"))
        XCTAssertEqual(Liens.nettoyer("https://shop.fr/p?utm_campaign=a")?.lien, "https://shop.fr/p")
        XCTAssertNil(Liens.nettoyer("bonjour https://x.fr?utm_source=1"))
        XCTAssertNil(Liens.nettoyer("https://x.fr/page"))
        XCTAssertEqual(Liens.nettoyer("  https://x.fr/?UTM_Source=a&ok=1\n")?.lien, "https://x.fr/?ok=1")
        XCTAssertEqual(Liens.nettoyer("https://open.spotify.com/track/1?si=abc&pk_campaign=z")?.lien, "https://open.spotify.com/track/1")
    }

    func testHotes() {
        XCTAssertEqual(Liens.hote("https://WWW.YouTube.com/watch?v=1"), "www.youtube.com")
        XCTAssertTrue(Liens.estSiteDistraction("www.youtube.com", ["youtube.com"]))
        XCTAssertFalse(Liens.estSiteDistraction("notyoutube.com", ["youtube.com"]))
        XCTAssertTrue(Liens.estSiteDistraction("x.com", ["x.com"]))
        XCTAssertFalse(Liens.estSiteDistraction("box.com", ["x.com"]))
    }
}

final class RangementTests: XCTestCase {
    func testCategories() {
        XCTAssertEqual(Rangement.categorie("Photo.PNG"), "Images")
        XCTAssertEqual(Rangement.categorie("facture.pdf"), "PDF")
        XCTAssertEqual(Rangement.categorie("App.dmg"), "Installeurs")
        XCTAssertEqual(Rangement.categorie("film.mov"), "Vidéos")
        XCTAssertEqual(Rangement.categorie("truc.xyz"), "Autres")
        XCTAssertEqual(Rangement.categorie("LISEZMOI"), "Autres")
        XCTAssertNil(Rangement.categorie(".DS_Store"))
        XCTAssertNil(Rangement.categorie("gros.zip.crdownload"))
    }

    func testNomLibre() {
        let pris: Set<String> = ["/d/a.pdf", "/d/a (2).pdf"]
        XCTAssertEqual(Rangement.nomLibre("/d", "a.pdf", existe: pris.contains), "/d/a (3).pdf")
        XCTAssertEqual(Rangement.nomLibre("/d", "b.pdf", existe: pris.contains), "/d/b.pdf")
        XCTAssertEqual(Rangement.nomLibre("/d", "x", existe: { $0 == "/d/x" }), "/d/x (2)")
    }

    func testCaptures() {
        XCTAssertTrue(Rangement.estCaptureBrute("Capture d’écran 2026-11-14 à 18.05.33.png"))
        XCTAssertFalse(Rangement.estCaptureBrute("2026-11-14 18.05.33 · Xcode.png"))
        XCTAssertEqual(Rangement.nomCapture("Capture d’écran 2026-11-14 à 18.05.33.png", app: "Xcode"), "2026-11-14 18.05.33 · Xcode.png")
        XCTAssertEqual(Rangement.nomCapture("Screenshot 2026-11-14 at 9.05.33.png", app: "Safari"), "2026-11-14 9.05.33 · Safari.png")
        XCTAssertEqual(Rangement.nomCapture("Capture d’écran 2026-11-14 à 18.05.33.png", app: nil), "2026-11-14 18.05.33.png")
        XCTAssertEqual(Rangement.nomCapture("Screenshot 2026-11-14 at 18.05.33.png", app: "A/B:C"), "2026-11-14 18.05.33 · A-B-C.png")
        XCTAssertEqual(Rangement.nomCapture("Enregistrement de l’écran 2026-11-14 à 18.05.33.mov", app: "Keynote"), "2026-11-14 18.05.33 · Keynote.mov")
    }
}

final class JournalTests: XCTestCase {
    func testEtatFocus() {
        let e = EtatFocus.lire("1794700000|50|Écran de connexion|3\n")
        XCTAssertEqual(e, EtatFocus(fin: 1794700000, min: 50, tache: "Écran de connexion", distractions: 3))
        let t = EtatFocus.lire("1794700000|25|Tâche du terminal\n")
        XCTAssertEqual(t?.tache, "Tâche du terminal")
        XCTAssertEqual(t?.distractions, 0)
        XCTAssertNil(EtatFocus.lire(""))
        XCTAssertNil(EtatFocus.lire(nil))
        XCTAssertEqual(EtatFocus(fin: 10, min: 5, tache: "a|b\nc", distractions: 2).ecrire(), "10|5|a b c|2\n")
        XCTAssertEqual(EtatFocus.lire(EtatFocus(fin: 99, min: 90, tache: "x", distractions: 7).ecrire())?.distractions, 7)
    }

    func testLignes() {
        XCTAssertEqual(Journal.ligne(debut: "2026-11-14 09:00", min: 50, tache: "A|B", distractions: 2, prochaine: "Faire\nC"),
                       "2026-11-14 09:00|50|A B|2|Faire C\n")
        let journal = "2026-11-13 09:00|50|A|1|Ouvrir le fichier X\n2026-11-14 09:00|50|B|0|\n2026-11-14 10:00|25|C|2|Finir le test\n"
        XCTAssertEqual(Journal.derniereEtape(journal), "Finir le test")
        XCTAssertNil(Journal.derniereEtape(""))
        XCTAssertEqual(Journal.ligneIdee("Appeler\nle comptable", quand: "14/11 18:00"), "- [ ] Appeler le comptable  (14/11 18:00)\n")
    }

    func testPriorites() {
        var pr = Journal.lirePriorites("[ ] Écran de connexion\n[x] Facture\nsans crochets\n\n")
        XCTAssertEqual(pr.count, 3)
        XCTAssertTrue(pr[1].fait)
        XCTAssertEqual(pr[2].texte, "sans crochets")
        XCTAssertEqual(Journal.prochainePriorite(pr)?.texte, "Écran de connexion")
        pr[0].fait = true
        XCTAssertEqual(Journal.prochainePriorite(pr)?.numero, 3)
        XCTAssertEqual(Journal.ecrirePriorites([Priorite(texte: "a"), Priorite(texte: "b", fait: true)]), "[ ] a\n[x] b\n")
        XCTAssertNil(Journal.prochainePriorite([]))
    }

    func testStatsEtBilan() {
        let journal = "2026-11-13 09:00|50|A|1|Ouvrir\n2026-11-14 09:00|50|B|0|\n2026-11-14 10:00|25|C|2|Finir\n2026-11-14 14:00|90|D\n"
        let st = Journal.stats(jour: "2026-11-14", focus: journal, reunions: "2026-11-14 11:00|34\n2026-11-13 11:00|10\n",
                               apps: "2026-11-14 09:00\tXcode\n2026-11-14 09:01\tXcode\n2026-11-14 09:02\tSafari\n2026-11-13 09:00\tMail\n")
        XCTAssertEqual(st.focus, 165)
        XCTAssertEqual(st.sessions, 3)
        XCTAssertEqual(st.distractions, 2)
        XCTAssertEqual(st.reunions, 34)
        XCTAssertEqual(st.apps.first?.nom, "Xcode")
        XCTAssertEqual(Journal.texteBilan(st, objectif: 210),
                       "Concentration : 2 h 45 sur 3 h 30 (78 %)\n3 sessions · 2 distractions bloquées\nRéunions : 34 min (1)\nApps : Xcode 2 min · Safari 1 min")
        XCTAssertEqual(Journal.texteBilan(Journal.stats(jour: "2026-11-15", focus: journal, reunions: "", apps: ""), objectif: 210),
                       "Concentration : 0 min sur 3 h 30 (0 %)\n0 session · 0 distraction bloquée")
    }

    func testAssocierFenetres() {
        let paires = Journal.associer(sauvees: ["Doc A", "Doc B", "Ancien"], actuelles: ["Doc B", "Nouveau", "Doc A"])
        var carte: [Int: Int] = [:]
        for p in paires { carte[p.sauvee] = p.actuelle }
        XCTAssertEqual(carte, [0: 2, 1: 0, 2: 1])
        XCTAssertEqual(Journal.associer(sauvees: ["a", "b"], actuelles: ["x"]).count, 1)
    }
}

final class GeometrieTests: XCTestCase {
    func testCycles() {
        XCTAssertEqual(Geometrie.suivante(Unite(0.2, 0.1, 0.4, 0.5), "gauche"), Unite(0, 0, 1 / 2, 1))
        XCTAssertEqual(Geometrie.suivante(Unite(0, 0, 0.5, 1), "gauche"), Unite(0, 0, 1 / 3, 1))
        XCTAssertEqual(Geometrie.suivante(Unite(0, 0, 0.334, 1), "gauche"), Unite(0, 0, 2 / 3, 1))
        XCTAssertEqual(Geometrie.suivante(Unite(0.005, 0, 0.66, 0.99), "gauche"), Unite(0, 0, 1 / 2, 1))
        XCTAssertEqual(Geometrie.suivante(Unite(0.5, 0, 0.5, 1), "droite"), Unite(2 / 3, 0, 1 / 3, 1))
        XCTAssertEqual(Geometrie.suivante(Unite(0, 0, 0.497, 0.985), "gauche"), Unite(0, 0, 1 / 3, 1))
        XCTAssertEqual(Geometrie.suivante(Unite(0, 0, 1, 1), "bd"), Unite(1 / 2, 1 / 2, 1 / 2, 1 / 2))
        XCTAssertNil(Geometrie.suivante(Unite(0, 0, 1, 1), "nulle"))
        XCTAssertTrue(Geometrie.estPlein(Unite(0, 0, 0.99, 1)))
        XCTAssertFalse(Geometrie.estPlein(Unite(0, 0, 0.5, 1)))
    }
}

final class DiversTests: XCTestCase {
    func testDateEtBatterie() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        let samedi = cal.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 9))!
        XCTAssertEqual(Divers.dateLongue(samedi, calendrier: cal), "samedi 14 novembre")
        let lundi = cal.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 9))!
        XCTAssertEqual(Divers.dateLongue(lundi, calendrier: cal), "lundi 3 août")
        XCTAssertEqual(Divers.texteBatterie(pourcentage: 82.4, minutes: 250, secteur: false), "Batterie 82 % · 4 h 10 restantes")
        XCTAssertEqual(Divers.texteBatterie(pourcentage: 100, minutes: -2, secteur: true), "Batterie 100 % · sur secteur")
        XCTAssertEqual(Divers.texteBatterie(pourcentage: 50, minutes: -1, secteur: false), "Batterie 50 %")
        XCTAssertNil(Divers.texteBatterie(pourcentage: nil, minutes: 1, secteur: true))
    }

    func testLettresIndices() {
        XCTAssertEqual(Divers.lettresIndices(["Ghostty", "Finder", "Ghostty", "Écrire"]), ["G", "F", "H", "E"])
        XCTAssertEqual(Divers.lettresIndices(["1", "2"]), ["A", "S"])
    }
}
