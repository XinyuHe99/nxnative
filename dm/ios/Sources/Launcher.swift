// Launcher: the settings screen shown before the game starts (front_ios.m dm_show_launcher). Its settings come from the app's dm/launcher.json, which build_ipa.sh writes for this game
// from dm/games/settings.tsv (dm/games/settings.py): each sets an environment variable the host reads when the game starts. A variable an env file set (Documents/env.txt, the bundle's
// dm/env.txt; main.m lists them in DM_ENV_FILE_KEYS) is shown but kept. The choices are kept in UserDefaults. DM_LAUNCHER=0 in Documents/env.txt starts the game at once, as an app
// without launcher.json does
import SwiftUI
import UIKit
import os

private struct Setting: Decodable, Identifiable {
    let env, kind, label, note, def: String
    let options: [[String]]?   // choice: [value, label]
    let min, max, step: Double?   // range
    var id: String { env }
    enum CodingKeys: String, CodingKey { case env, kind, label, note, def = "default", options, min, max, step }
}
private struct SettingsFile: Decodable { let settings: [Setting] }

private func info(_ key: String) -> Any? { Bundle.main.object(forInfoDictionaryKey: key) }
private func localized(_ key: String) -> String { NSLocalizedString(key, comment: "") }
private let defaults = UserDefaults.standard

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

private final class LauncherModel: ObservableObject {
    let settings: [Setting]
    let fromFile: Set<String>   // set by an env file: shown, not changed
    @Published var values: [String: String] = [:]

    init(_ settings: [Setting]) {
        self.settings = settings
        fromFile = Set((ProcessInfo.processInfo.environment["DM_ENV_FILE_KEYS"] ?? "").split(separator: " ").map(String.init))
        for s in settings {
            if fromFile.contains(s.env), let v = ProcessInfo.processInfo.environment[s.env] { values[s.env] = v; continue }
            let saved = defaults.string(forKey: "launcher." + s.env)
            values[s.env] = saved.flatMap { v in s.options == nil || s.options!.contains { $0[0] == v } ? v : nil } ?? s.def   // a saved choice the game no longer offers: its default
        }
    }

    func binding(_ s: Setting) -> Binding<String> { Binding(get: { self.values[s.env] ?? s.def }, set: { self.values[s.env] = $0 }) }

    // Before the game starts: every setting not set by an env file goes into the environment (DM_LANG replaces the packed language main.m set as a default)
    func apply() {
        for s in settings {
            let v = values[s.env] ?? s.def
            if fromFile.contains(s.env) { fputs("launcher: \(s.env) kept at \(v) (env file)\n", stderr); continue }
            defaults.set(v, forKey: "launcher." + s.env)
            setenv(s.env, v, 1); fputs("launcher: \(s.env)=\(v)\n", stderr)
        }
    }
    func isDefault(_ s: Setting) -> Bool {
        let v = values[s.env] ?? s.def
        if fromFile.contains(s.env) || v == s.def { return true }
        if s.kind == "range", let a = Double(v), let b = Double(s.def) { return abs(a - b) < 0.001 }
        return false
    }
    func restoreDefaults() { for s in settings where !fromFile.contains(s.env) { values[s.env] = s.def } }
}

// Group only the settings this screen knows about; new game/profile settings stay visible under Other.
private let groups: [(title: String, symbol: String, envs: [String])] = [
    ("Display", "display", ["DM_FPS_TARGET", "DM_RENDER_SCALE", "DM_PRESENT_SNAP", "DM_AMBIENT", "DM_METAL_HUD", "DM_PERF_OVERLAY"]),
    ("Game", "gamecontroller", ["DM_OPMODE", "DM_LANG"]),
    ("Controls & Haptics", "hand.tap", ["DM_TOUCH_HAPTICS", "DM_RUMBLE", "DM_RUMBLE_GAIN"]),
]

private struct SettingRow: View {
    let s: Setting
    @ObservedObject var m: LauncherModel

    private var locked: Bool { m.fromFile.contains(s.env) }
    private var note: String {
        let n = localized(s.note)
        return locked ? (n.isEmpty ? "" : n + " · ") + localized("Set by an env file") : n
    }
    private var rangeValue: Binding<Double> {
        Binding(get: { Double(m.values[s.env] ?? s.def) ?? s.max ?? 1 },
                set: { m.values[s.env] = String(format: "%.2f", $0) })
    }
    private var percentage: String { "\(Int((rangeValue.wrappedValue * 100).rounded())) %" }

    private var settingLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localized(s.label))
            if !note.isEmpty { Text(note).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    var body: some View {
        Group {
            switch s.kind {
            case "choice":
                Picker(selection: m.binding(s)) {
                    ForEach(s.options ?? [], id: \.[0]) { Text(localized($0[1])).tag($0[0]) }
                } label: {
                    settingLabel
                }
                .pickerStyle(.navigationLink)
            case "range":
                NavigationLink {
                    Form {
                        Section {
                            HStack {
                                Text(localized(s.label))
                                Spacer()
                                Text(percentage).monospacedDigit().foregroundStyle(.secondary)
                            }
                            Slider(value: rangeValue, in: (s.min ?? 0)...(s.max ?? 1), step: s.step ?? 0.05)
                                .accessibilityLabel(localized(s.label))
                                .accessibilityValue(percentage)
                                .disabled(locked)
                        } footer: {
                            if !note.isEmpty { Text(note) }
                        }
                    }
                    .contentMargins(.horizontal, 12, for: .scrollContent)
                    .navigationTitle(localized(s.label))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(.visible, for: .navigationBar)
                } label: {
                    HStack {
                        settingLabel
                        Spacer()
                        Text(percentage).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            default:
                Toggle(isOn: Binding(get: { (m.values[s.env] ?? s.def) == "1" }, set: { m.values[s.env] = $0 ? "1" : "0" })) {
                    settingLabel
                }
            }
        }
        .disabled(locked)
        .listRowBackground(Color.white.opacity(0.08))
    }
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
        NavigationStack {
            Form {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    let rows = m.settings.filter { group.envs.contains($0.env) }
                    if !rows.isEmpty {
                        Section {
                            ForEach(rows) { SettingRow(s: $0, m: m) }
                        } header: {
                            Label(LocalizedStringKey(group.title), systemImage: group.symbol)
                        }
                    }
                }

                let assigned = Set(groups.flatMap(\.envs))
                let other = m.settings.filter { !assigned.contains($0.env) }
                if !other.isEmpty {
                    Section {
                        ForEach(other) { SettingRow(s: $0, m: m) }
                    } header: {
                        Text(LocalizedStringKey("Other"))
                    }
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
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { m.restoreDefaults() }
                    } label: {
                        Label(localized("Restore Defaults"), systemImage: "arrow.counterclockwise")
                    }
                    .disabled(m.settings.allSatisfy(m.isDefault))
                    .listRowBackground(Color.white.opacity(0.08))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, 10, for: .scrollContent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .containerBackground(.clear, for: .navigation)   // the backdrop shows through, as beside the panel (the stack's own fill drew a black box)
        }
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
    if ProcessInfo.processInfo.environment["DM_LAUNCHER"] == "0" { fputs("launcher: off (DM_LAUNCHER=0)\n", stderr); return false }
    guard let url = Bundle.main.resourceURL?.appendingPathComponent("dm/launcher.json"), let data = try? Data(contentsOf: url) else { return false }
    guard let file = try? JSONDecoder().decode(SettingsFile.self, from: data), !file.settings.isEmpty else { fputs("[RED] launcher: dm/launcher.json cannot be read; starting the game\n", stderr); return false }
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
