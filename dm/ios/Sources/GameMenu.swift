// In-game menu: a swipe in from the left edge of the screen opens a panel over the game (front_ios.m installs it over the root view once the game starts). The panel follows the finger and
// opens past 35 % of its width or on a quick flick. The game keeps running under it; it closes from Continue, the close button, a tap on
// the dimmed picture or a swipe back to the left. A swipe that lands on a virtual-gamepad control is left to the gamepad (dm_pad_takes), so the left stick near the edge keeps working.
// What it offers, all through DmMenu.h: resume, a screenshot (the next presented frame as PNG into Documents/Screenshots, then into Photos when allowed), shaking the controller, quitting;
// the virtual gamepad's layout, opacity, hide switch and touch feedback; the console mode (handheld / docked, hle_oe.c pushes the change to the game), Ambient mode (front_ios.m)
// and sound. A console mode, Ambient mode or touch feedback chosen here is also kept as the launcher's choice for the next start (Launcher.swift's "launcher.<variable>" keys), unless an env file
// set that variable. Those three rows follow the game's own settings list (dmOfferedSettings, as the launcher shows it): a game or a device without one leaves its row out. The first few starts show a short hint at the left edge. DM_MENU=0 leaves the menu out, DM_MENU=open opens it a second after the game starts (for testing)
import Photos
import SwiftUI
import UIKit
import os

private func tr(_ key: String) -> String { NSLocalizedString(key, comment: "") }
private func info(_ key: String) -> Any? { Bundle.main.object(forInfoDictionaryKey: key) }
private func note(_ s: String) { fputs("menu: \(s)\n", stderr) }

private final class MenuModel: ObservableObject {
    @Published var progress: CGFloat = 0   // 0 closed .. 1 open
    @Published var layout = 0
    @Published var docked = false
    @Published var controller = false
    @Published var opacity = 0.5
    @Published var hidden = false
    @Published var haptics = true
    @Published var ambient = false
    @Published var muted = false
    @Published var fps = -1.0   // frames on screen per second between two looks (stats), -1 before the second look
    @Published var memory: UInt64 = 0
    @Published var thermal = 0
    @Published var battery: Float = -1
    @Published var toast: String?
    @Published var hint = false
    @Published var confirmQuit = false
    var close: (_ then: (() -> Void)?) -> Void = { _ in }
    private let offered = dmOfferedSettings()
    func offers(_ env: String) -> Bool { offered?.contains(env) ?? (env != "DM_AMBIENT" || dmLetterboxed()) }
    private var toastGen = 0
    private var frames0: UInt64 = 0, time0 = 0.0

    func read() {
        layout = Int(dm_pad_layout()); docked = dm_opmode() != 0; controller = dm_pad_controller()
        opacity = dm_pad_opacity(); hidden = dm_pad_hidden(); haptics = dm_pad_haptics()
        ambient = front_menu_ambient(); muted = front_menu_muted()
        fps = -1; frames0 = UInt64(mtl_present_count()); time0 = CACurrentMediaTime()
        stats()
    }
    func stats() {
        let n = UInt64(mtl_present_count()), t = CACurrentMediaTime()
        if t - time0 >= 0.25 { fps = Double(n &- frames0) / (t - time0); frames0 = n; time0 = t }
        memory = UInt64(os_proc_available_memory()); thermal = Int(dm_thermal_now())
        battery = UIDevice.current.batteryLevel
    }
    func show(_ message: String) {
        toastGen += 1; let gen = toastGen
        withAnimation(.snappy) { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            guard let self, self.toastGen == gen else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.toast = nil }
        }
    }

    // A setting chosen here also becomes the launcher's choice for the next start, unless an env file set the variable (the launcher keeps those)
    func remember(_ env: String, _ value: String) {
        let locked = (ProcessInfo.processInfo.environment["DM_ENV_FILE_KEYS"] ?? "").split(separator: " ").contains { $0 == env }
        if locked { return }
        UserDefaults.standard.set(value, forKey: "launcher." + env)
        setenv(env, value, 1)
    }
    func setLayout(_ l: Int) { dm_pad_set_layout(Int32(l)); layout = Int(dm_pad_layout()) }
    func setDocked(_ on: Bool) {
        dm_set_opmode(on ? 1 : 0); docked = on
        if on && layout == 2 { setLayout(0) }   // Tap is offered in handheld mode only
        remember("DM_OPMODE", on ? "1" : "0"); note("console mode \(on ? "docked" : "handheld")")
    }
    func setOpacity(_ a: Double) { dm_pad_set_opacity(a); opacity = dm_pad_opacity() }
    func setHidden(_ on: Bool) { dm_pad_set_hidden(on); hidden = on }
    func setHaptics(_ on: Bool) { dm_pad_set_haptics(on); haptics = on; remember("DM_TOUCH_HAPTICS", on ? "1" : "0") }
    func setAmbient(_ on: Bool) { front_menu_set_ambient(on); ambient = front_menu_ambient(); remember("DM_AMBIENT", on ? "1" : "0") }
    func setMuted(_ on: Bool) { front_menu_set_muted(on); muted = on }

    func shake() { close { dm_pad_shake(0.6) } }
    func screenshot() {
        close { [weak self] in Task { @MainActor in await self?.takeScreenshot() } }
    }
    @MainActor private func takeScreenshot() async {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dir = docs.appendingPathComponent("Screenshots", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = DateFormatter(); stamp.locale = Locale(identifier: "en_US_POSIX"); stamp.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = dir.appendingPathComponent("\(stamp.string(from: Date())).png")
        url.withUnsafeFileSystemRepresentation { if let p = $0 { dm_gfx_shot_at(0, p) } }
        // The graphics side writes the file at the next present; wait for it to be whole (its size unchanged between two looks and it opens)
        var last = -1
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(100))
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
            if size > 0 && size == last && UIImage(contentsOfFile: url.path) != nil { break }
            last = size
        }
        guard UIImage(contentsOfFile: url.path) != nil else { note("screenshot not written: \(url.path)"); show(tr("Screenshot failed")); return }
        note("screenshot \(url.path)")
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { show(tr("Screenshot saved to Files › Screenshots")); return }
        do {
            try await PHPhotoLibrary.shared().performChanges { _ = PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: url) }
            show(tr("Screenshot saved to Photos"))
        } catch {
            note("screenshot not added to Photos: \(error.localizedDescription)"); show(tr("Screenshot saved to Files › Screenshots"))
        }
    }
}

// ---- The menu's look ----
private struct Card<Content: View>: View {
    let title: LocalizedStringKey
    var tag: LocalizedStringKey? = nil   // a short state beside the title
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                if let tag {
                    Label(tag, systemImage: "gamecontroller.fill").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(.white.opacity(0.1), in: Capsule())
                }
            }
            .padding(.leading, 4)
            VStack(spacing: 0) { content }
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// One setting: its name on the left, the control on the right, a hairline under every row but the card's last
private struct Row<Control: View>: View {
    let title: LocalizedStringKey
    var last = false
    @ViewBuilder let control: Control
    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.subheadline).lineLimit(1).layoutPriority(1)
            Spacer(minLength: 6)
            control
        }
        .frame(minHeight: 40)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5) } }
    }
}

private struct Stat: View {
    let symbol: String, value: String, label: LocalizedStringKey
    var tint: Color = .primary
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.footnote.weight(.semibold)).foregroundStyle(tint)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct Action: View {
    let symbol: String, title: LocalizedStringKey
    var primary = false
    let run: () -> Void
    var body: some View {
        Button(action: run) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.glass)
        .tint(primary ? .accentColor : nil)
    }
}

private struct MenuPanel: View {
    @ObservedObject var m: MenuModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                stats
                actions
                if m.offers("DM_OPMODE") || m.offers("DM_AMBIENT") { Card(title: "Game") { game } }   // a game with neither row has no Game card
                Card(title: "Controls", tag: m.controller ? "Controller connected" : nil) { controls }
                Button(role: .destructive) { m.confirmQuit = true } label: {
                    Label("Quit Game", systemImage: "power").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.glass).tint(.red)
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .alert("Quit the game?", isPresented: $m.confirmQuit) {
            Button("Quit", role: .destructive) { note("quit"); front_menu_quit() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Progress since your last save will be lost.") }
    }

    var header: some View {
        HStack(spacing: 12) {
            if let icon = appIcon() {
                Image(uiImage: icon).resizable().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Text((info("CFBundleDisplayName") as? String) ?? tr("Game")).font(.headline).lineLimit(2)
            Spacer(minLength: 8)
            Button { m.close(nil) } label: { Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 30, height: 30) }
                .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel(Text("Close"))
        }
    }

    var stats: some View {
        HStack(spacing: 8) {
            Stat(symbol: "speedometer", value: m.fps < 0 ? "--" : String(format: "%.0f", m.fps), label: "FPS")
            Stat(symbol: "memorychip", value: m.memory == 0 ? "—" : ByteCountFormatter.string(fromByteCount: Int64(m.memory), countStyle: .memory), label: "Memory free")   // 0: no limit to measure against (the simulator)
            Stat(symbol: "thermometer.medium", value: tr(["Normal", "Fair", "Serious", "Critical"][min(max(m.thermal, 0), 3)]), label: "Thermal",
                 tint: [Color.green, .yellow, .orange, .red][min(max(m.thermal, 0), 3)])
            if m.battery >= 0 {
                Stat(symbol: m.battery > 0.2 ? "battery.75percent" : "battery.25percent", value: "\(Int((m.battery * 100).rounded()))%", label: "Battery",
                     tint: m.battery > 0.2 ? .primary : .red)
            }
        }
    }

    var actions: some View {
        HStack(spacing: 8) {
            Action(symbol: "play.fill", title: "Continue", primary: true) { m.close(nil) }
            Action(symbol: "camera.viewfinder", title: "Screenshot") { m.screenshot() }
            Action(symbol: "iphone.radiowaves.left.and.right", title: "Shake") { m.shake() }
            Action(symbol: m.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", title: m.muted ? LocalizedStringKey("Unmute") : LocalizedStringKey("Mute")) { m.setMuted(!m.muted) }
        }
    }

    @ViewBuilder var controls: some View {
        Group {
            Row(title: "Layout") {
                Picker("Layout", selection: Binding(get: { m.layout }, set: { m.setLayout($0) })) {
                    Text("2D").tag(0)
                    Text("3D").tag(1)
                    if !m.docked { Text("Tap").tag(2) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: m.docked ? 110 : 160)
            }
            Row(title: "Opacity") {
                Slider(value: Binding(get: { m.opacity }, set: { m.setOpacity($0) }), in: 0.2...1, step: 0.05).frame(width: 120)
                Text("\(Int((m.opacity * 100).rounded()))%").font(.footnote).monospacedDigit().foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
            }
        }
        .disabled(m.controller || m.hidden)
        Row(title: "Hide touch controls", last: !m.offers("DM_TOUCH_HAPTICS")) { Toggle("", isOn: Binding(get: { m.hidden }, set: { m.setHidden($0) })).labelsHidden() }.disabled(m.controller)
        if m.offers("DM_TOUCH_HAPTICS") {
            Row(title: "Touch feedback", last: true) { Toggle("", isOn: Binding(get: { m.haptics }, set: { m.setHaptics($0) })).labelsHidden() }
        }
    }

    @ViewBuilder var game: some View {
        if m.offers("DM_OPMODE") {
            Row(title: "Console mode", last: !m.offers("DM_AMBIENT")) {
                Picker("Console mode", selection: Binding(get: { m.docked }, set: { m.setDocked($0) })) {
                    Text("Handheld").tag(false)
                    Text("Docked").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 160)
            }
        }
        if m.offers("DM_AMBIENT") {
            Row(title: "Ambient mode", last: true) { Toggle("", isOn: Binding(get: { m.ambient }, set: { m.setAmbient($0) })).labelsHidden() }
        }
    }

    private func appIcon() -> UIImage? {
        if let i = UIImage(named: "AppIcon") { return i }
        guard let icons = info("CFBundleIcons") as? [String: Any], let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String], let last = files.last else { return nil }
        return UIImage(named: last)
    }
}

private struct MenuOverlay: View {
    @ObservedObject var m: MenuModel
    let width: CGFloat

    var body: some View {
        GeometryReader { geo in
            // The panel keeps clear of the Dynamic Island and the rounded corners at the side (the whole side inset: half of it let the island cover rows as they
            // scrolled past). Above and below it floats at one margin: in landscape only the home indicator, hidden while playing, insets the bottom, and taking that
            // inset there left the panel three times as far from the bottom edge as from the top
            let lead = geo.safeAreaInsets.leading + 12
            let top = geo.safeAreaInsets.top + 12
            let bottom = top
            let shift = (1 - m.progress) * (width + lead + 24)
            ZStack(alignment: .leading) {
                Color.black.opacity(0.45 * m.progress)
                    .contentShape(Rectangle())
                    .onTapGesture { m.close(nil) }
                    .gesture(DragGesture(minimumDistance: 12).onEnded { if $0.translation.width < -40 { m.close(nil) } })
                    .allowsHitTesting(m.progress > 0)
                MenuPanel(m: m)
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .glassEffect(.regular.tint(.black.opacity(0.35)), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .padding(.leading, lead)
                    .padding(.top, top).padding(.bottom, bottom)
                    .offset(x: -shift)
                    .opacity(m.progress > 0 ? 1 : 0)
                if m.hint && m.progress == 0 {
                    Label("Swipe in from the left edge for the menu", systemImage: "chevron.compact.right")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .glassEffect(.regular, in: Capsule())
                        .padding(.leading, geo.safeAreaInsets.leading + 8)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .top) {
                if let t = m.toast {
                    Text(t).font(.subheadline.weight(.medium))
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .glassEffect(.regular, in: Capsule())
                        .padding(.top, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }
}

// ---- The edge swipe and the panel over the root view ----
private final class MenuController: NSObject, UIGestureRecognizerDelegate {
    static let width: CGFloat = 340
    let model: MenuModel
    let host: UIHostingController<MenuOverlay>
    weak var root: UIViewController?
    private var timer: Timer?
    private var generation = 0   // an animation's completion acts only if no later open / close came after it

    init(root: UIViewController) {
        let m = MenuModel()
        self.root = root; model = m
        host = UIHostingController(rootView: MenuOverlay(m: m, width: Self.width))
        super.init()
        host.view.backgroundColor = .clear
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = root.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.isUserInteractionEnabled = false
        root.addChild(host); root.view.addSubview(host.view); host.didMove(toParent: root)
        let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgePan(_:)))
        edge.edges = .left; edge.delegate = self
        root.view.addGestureRecognizer(edge)
        model.close = { [weak self] then in self?.animate(open: false, then: then) }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let shown = UserDefaults.standard.integer(forKey: "DmMenuHintShown")
        if shown < 3 {
            UserDefaults.standard.set(shown + 1, forKey: "DmMenuHintShown")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in withAnimation(.snappy) { self?.model.hint = true } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) { [weak self] in withAnimation(.easeOut) { self?.model.hint = false } }
        }
    }

    // A swipe starting on a gamepad control stays with the gamepad (the left stick reaches the edge); no new swipe while the menu is open
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard model.progress == 0, let v = root?.view else { return false }
        let p = touch.location(in: v)
        return !dm_pad_takes(Double(p.x), Double(p.y))
    }

    @objc private func edgePan(_ g: UIScreenEdgePanGestureRecognizer) {
        guard let v = root?.view else { return }
        let x = g.translation(in: v).x, vx = g.velocity(in: v).x
        switch g.state {
        case .began:
            generation += 1
            model.read(); model.hint = false
            host.view.isUserInteractionEnabled = true
            model.progress = 0.001
        case .changed:
            model.progress = min(max(x / Self.width, 0.001), 1)
        case .ended:
            animate(open: vx > 400 || (model.progress > 0.35 && vx > -300))
        default:
            animate(open: false)
        }
    }

    func animate(open: Bool, then: (() -> Void)? = nil) {
        generation += 1; let gen = generation
        if open {
            model.read()
            host.view.isUserInteractionEnabled = true
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { model.progress = 1 } completion: { [weak self] in
                guard let self, self.generation == gen else { return }
                self.model.stats()
                self.timer?.invalidate()
                self.timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.model.stats() }
            }
            note("open")
        } else {
            timer?.invalidate(); timer = nil
            withAnimation(.spring(response: 0.3, dampingFraction: 0.92)) { model.progress = 0 } completion: { [weak self] in
                guard let self, self.generation == gen else { return }
                self.host.view.isUserInteractionEnabled = false
                then?()
            }
        }
    }
}

private var menu: MenuController?

@_cdecl("dm_menu_install")
public func dmMenuInstall(_ viewController: UnsafeMutableRawPointer) {
    if menu != nil { return }
    if ProcessInfo.processInfo.environment["DM_MENU"] == "0" { note("off (DM_MENU=0)"); return }
    let root = Unmanaged<UIViewController>.fromOpaque(viewController).takeUnretainedValue()
    menu = MenuController(root: root)
    note("installed: swipe in from the left edge")
    if ProcessInfo.processInfo.environment["DM_MENU"] == "open" {   // for testing and screenshots: open it once the game is on screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { menu?.animate(open: true) }
    }
}
