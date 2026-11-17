// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Majordome",
    platforms: [.macOS(.v13)],
    targets: [
        // Logique pure (texte, liens, journaux, géométrie) : testée à part.
        .target(name: "MajordomeCore"),
        // L'app : barre des menus, touche Hyper, fenêtres, focus…
        .executableTarget(
            name: "Majordome",
            dependencies: ["MajordomeCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .testTarget(name: "MajordomeCoreTests", dependencies: ["MajordomeCore"]),
    ]
)
