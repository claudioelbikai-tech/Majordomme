import AppKit

@main
enum Lanceur {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let majordome = Majordome()
        app.delegate = majordome
        app.setActivationPolicy(.accessory)  // pas d'icône dans le Dock : l'app vit dans la barre des menus
        withExtendedLifetime(majordome) { app.run() }
    }
}
