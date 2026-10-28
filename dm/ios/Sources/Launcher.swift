// Launcher: the settings screen shown before the game starts (front_ios.m dm_show_launcher). Its settings come from the app's dm/launcher.json, which build_ipa.sh writes for this game
// from dm/games/settings.tsv (dm/games/settings.py): each sets an environment variable the host reads when the game starts. A variable an env file set (Documents/env.txt, the bundle's
// dm/env.txt; main.m lists them in DM_ENV_FILE_KEYS) is shown but kept. All settings share one screen, grouped by section, beside the game's icon, name and Play over a blurred
// backdrop of the icon (rows: LauncherRow.swift). The model (LauncherSettings.swift): choices that differ from the game's default are kept in UserDefaults; Reset to tested defaults
// shows the defaults, and Play then forgets them. DM_LAUNCHER=0 in Documents/env.txt starts the game at once with the saved choices; DM_SAVED_CHOICES=0 ignores them (and keeps them)
import SwiftUI
import UIKit
import os

private func info(_ key: String) -> Any? { Bundle.main.object(forInfoDictionaryKey: key) }
private func localized(_ key: String) -> String { NSLocalizedString(key, comment: "") }

// What a game offers differs (dm/games/settings.py writes each app's list), and a setting may do nothing on this device: Ambient mode only fills bars, so it is left out where
// the screen is 16:9 itself. The launcher and the in-game menu (GameMenu.swift, dmOfferedSettings) both show only the settings that are left
func dmLetterboxed() -> Bool {
    let s = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.size ?? .zero
    guard s.width > 0, s.height > 0 else { return true }
    return abs(max(s.width, s.height) / min(s.width, s.height) - 16.0 / 9.0) > 0.01
}
private func applies(_ s: Setting) -> Bool { s.env != "DM_AMBIENT" || dmLetterboxed() }
private func readSettings() -> SettingsFile? {
    guard let url = Bundle.main.resourceURL?.appendingPathComponent("dm/launcher.json"), let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(SettingsFile.self, from: data)
}
// The variables of the settings this app offers here; nil when it has no dm/launcher.json (then the menu offers all of its own)
func dmOfferedSettings() -> Set<String>? { readSettings().map { Set($0.settings.filter(applies).map(\.env)) } }

// The symbol beside each section's heading (settings.py's sections)
private func sectionSymbol(_ section: String) -> String {
    switch section { case "Controls": return "hand.tap"; case "Performance": return "speedometer"; default: return "gamecontroller" }
}

private struct LauncherView: View {
    @ObservedObject var m: LauncherModel
    let play: () -> Void
    @State private var memory = os_proc_available_memory()

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let icon = appIcon()
            ZStack {
                backdrop(icon)
                if size.width >= 760 && size.height >= 330 {
                    wideLayout(icon, size: size)
                } else {
                    compactLayout(icon)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
        .task {
            while !Task.isCancelled {
                memory = os_proc_available_memory()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func wideLayout(_ icon: UIImage?, size: CGSize) -> some View {
        let contentWidth = min(max(size.width - 48, 0), 1_240)
        let contentHeight = max(size.height - 28, 0)
        let heroWidth = contentWidth * 0.43
        let settingsWidth = contentWidth - heroWidth

        return HStack(spacing: 0) {
            hero(icon)
                .frame(width: heroWidth, height: contentHeight)
            settingsPanel()
                .frame(width: settingsWidth, height: contentHeight)
        }
        .frame(width: contentWidth, height: contentHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func compactLayout(_ icon: UIImage?) -> some View {
        VStack(spacing: 12) {
            compactIdentity(icon)
            settingsPanel()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func settingsPanel() -> some View {
        Form {
            ForEach(m.sections, id: \.self) { section in
                let rows = m.rows(in: section)   // a sub-setting only while it can do anything (LauncherModel.visible)
                if !rows.isEmpty {
                    Section {
                        ForEach(rows) { SettingRow(s: $0, m: m).listRowBackground(Color.white.opacity(0.08)) }
                    } header: {
                        Label(LocalizedStringKey(section), systemImage: sectionSymbol(section))
                    }
                }
            }

            Section {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { m.reset() }
                } label: {
                    Label(localized("Reset to tested defaults"), systemImage: "arrow.counterclockwise")
                }
                .disabled(!m.changed)
                .listRowBackground(Color.white.opacity(0.08))
            } footer: {
                Text(LocalizedStringKey("Brings back all settings this game was tested with."))
            }

            Section {
                HStack {
                    Label(localized("Memory available"), systemImage: "memorychip")
                    Spacer(minLength: 12)
                    Text(memory == 0 ? "—" : ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.white.opacity(0.08))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)   // the backdrop shows through, as beside the panel
        .contentMargins(.horizontal, 10, for: .scrollContent)
    }

    private func hero(_ icon: UIImage?) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)
            artwork(icon, size: 112)
            VStack(spacing: 5) {
                Text((info("CFBundleDisplayName") as? String) ?? localized("Game"))
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)   // a long name takes its second line before it shrinks or is cut
                versionLabel
            }
            playButton
            menuHint
            Spacer(minLength: 8)
        }
        .padding(20)
    }

    private func compactIdentity(_ icon: UIImage?) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                artwork(icon, size: 62)
                VStack(alignment: .leading, spacing: 4) {
                    Text((info("CFBundleDisplayName") as? String) ?? localized("Game"))
                        .font(.headline.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    versionLabel
                }
                Spacer(minLength: 8)
                playButton
            }
            menuHint
        }
        .padding(13)
        .background(Color.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
    }

    private var versionLabel: some View {
        Text(String(format: localized("Version %@"), (info("CFBundleShortVersionString") as? String) ?? ""))
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private var menuHint: some View {
        Label(LocalizedStringKey("In game, swipe in from the left edge for the menu"), systemImage: "hand.draw")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func artwork(_ icon: UIImage?, size: CGFloat) -> some View {
        if let icon {
            Image(uiImage: icon)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))
                .frame(width: size, height: size)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var playButton: some View {
        let button = Button(action: play) {
            Label(localized("Play"), systemImage: "play.fill")
                .font(.headline.weight(.semibold))
                .frame(minWidth: 126, minHeight: 46)
        }
        .controlSize(.large)
        if #available(iOS 26.0, *) { button.buttonStyle(.glassProminent) } else { button.buttonStyle(.borderedProminent) }
    }

    private func backdrop(_ icon: UIImage?) -> some View {
        Color.black
            .overlay {
                if let icon {
                    GeometryReader { geometry in
                        Image(uiImage: icon)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .blur(radius: 48)
                            .opacity(0.54)
                            .scaleEffect(1.18)
                            .clipped()
                    }
                }
            }
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.34), .black.opacity(0.76)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .ignoresSafeArea()
    }

    private func appIcon() -> UIImage? {
        if let i = UIImage(named: "AppIcon") { return i }
        guard let icons = info("CFBundleIcons") as? [String: Any], let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String], let last = files.last else { return nil }
        return UIImage(named: last)
    }
}

// Shows the launcher over the root view controller and calls done once the settings are in the environment; false (done is not called) when there is no launcher
@_cdecl("dm_show_launcher")
public func dmShowLauncher(_ viewController: UnsafeMutableRawPointer, _ done: @convention(c) () -> Void) -> Bool {
    guard let url = Bundle.main.resourceURL?.appendingPathComponent("dm/launcher.json"), let data = try? Data(contentsOf: url) else { return false }
    guard let file = try? JSONDecoder().decode(SettingsFile.self, from: data), !file.settings.isEmpty else { fputs("[RED] launcher: dm/launcher.json cannot be read; starting the game\n", stderr); return false }
    if ProcessInfo.processInfo.environment["DM_LAUNCHER"] == "0" { fputs("launcher: off (DM_LAUNCHER=0)\n", stderr); LauncherModel(file.settings.filter(applies)).applySaved(); return false }
    let parent = Unmanaged<UIViewController>.fromOpaque(viewController).takeUnretainedValue()
    let model = LauncherModel(file.settings.filter(applies))
    var host: UIViewController?
    let view = LauncherView(m: model) {
        guard let h = host else { return }
        host = nil
        model.apply()
        h.dismiss(animated: false) { done() }
    }
    let h = UIHostingController(rootView: view)
    h.modalPresentationStyle = .fullScreen
    h.overrideUserInterfaceStyle = .dark
    h.view.backgroundColor = .black
    host = h
    parent.present(h, animated: false)
    fputs("launcher: \(file.settings.count) settings shown\n", stderr)
    return true
}
