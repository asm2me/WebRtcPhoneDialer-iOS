import Foundation
import SwiftUI

struct UpdateInfo: Equatable {
    let version: String
    let notes: String
    let releasePageUrl: String
    let ipaUrl: String?
}

@MainActor
final class UpdateService: ObservableObject {
    @Published var available: UpdateInfo?

    private static let latestUrl = URL(string: "https://api.github.com/repos/asm2me/Fusionpbx-Plugins/releases/latest")!
    private static let lastCheckKey = "update_last_check"
    private static let skipKey = "update_skip_version"
    private static let checkInterval: TimeInterval = 6 * 60 * 60

    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0"
    }

    func checkOnLaunch() async {
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        if last > 0, Date().timeIntervalSince1970 - last < Self.checkInterval { return }
        await check(force: false)
    }

    @discardableResult
    func check(force: Bool) async -> UpdateInfo? {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
        guard let info = await fetchLatest() else { return nil }
        if !Self.isNewer(info.version, than: Self.currentVersion) { return nil }
        if !force, UserDefaults.standard.string(forKey: Self.skipKey) == info.version { return nil }
        self.available = info
        return info
    }

    func skip(_ version: String) {
        UserDefaults.standard.set(version, forKey: Self.skipKey)
        self.available = nil
    }

    func dismiss() {
        self.available = nil
    }

    private func fetchLatest() async -> UpdateInfo? {
        var req = URLRequest(url: Self.latestUrl)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("VOIPAT-Dialer-iOS", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 30
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            var tag = (obj["tag_name"] as? String) ?? ""
            if tag.hasPrefix("v") || tag.hasPrefix("V") { tag.removeFirst() }
            let notes = (obj["body"] as? String) ?? ""
            let pageUrl = (obj["html_url"] as? String) ?? "https://github.com/asm2me/Fusionpbx-Plugins/releases/latest"

            var ipaUrl: String?
            if let assets = obj["assets"] as? [[String: Any]] {
                for a in assets {
                    if let name = a["name"] as? String, name.lowercased().hasSuffix(".ipa"),
                       let url = a["browser_download_url"] as? String {
                        ipaUrl = url
                        break
                    }
                }
            }
            return UpdateInfo(version: tag, notes: notes, releasePageUrl: pageUrl, ipaUrl: ipaUrl)
        } catch {
            return nil
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let av = parse(a), bv = parse(b)
        let n = max(av.count, bv.count)
        for i in 0..<n {
            let ai = i < av.count ? av[i] : 0
            let bi = i < bv.count ? bv[i] : 0
            if ai > bi { return true }
            if ai < bi { return false }
        }
        return false
    }

    private static func parse(_ v: String) -> [Int] {
        v.split(separator: ".").map { part -> Int in
            let digits = part.prefix(while: { $0.isNumber })
            return Int(digits) ?? 0
        }
    }
}

struct UpdateBanner: View {
    let info: UpdateInfo
    let onOpen: () -> Void
    let onSkip: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                Text("Update available: v\(info.version)").font(.headline)
                Spacer()
            }
            if !info.notes.isEmpty {
                Text(info.notes.prefix(280) + (info.notes.count > 280 ? "…" : ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack {
                Button("View Release", action: onOpen)
                    .buttonStyle(.borderedProminent)
                Spacer()
                Button("Later", action: onLater)
                Button("Skip") { onSkip() }
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
