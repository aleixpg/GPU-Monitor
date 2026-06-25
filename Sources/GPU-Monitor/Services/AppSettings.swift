import Foundation
import Security

enum AppSettings {
    private static let service = "com.gpu-monitor.app"
    private static let compactModeKey = "compactMode"

    private static func kcQuery(_ a: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: a, kSecReturnData as String: true,
         kSecMatchLimit as String: kSecMatchLimitOne]
    }

    private static func kcGet(_ a: String) -> String? {
        var r: AnyObject?
        return (SecItemCopyMatching(kcQuery(a) as CFDictionary, &r) == errSecSuccess)
            ? String(data: r as! Data, encoding: .utf8) : nil
    }

    private static func kcSet(_ a: String, _ v: String) {
        guard let d = v.data(using: .utf8) else { return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: a]
        let u: [String: Any] = [kSecValueData as String: d]
        let r = SecItemUpdate(q as CFDictionary, u as CFDictionary)
        if r != errSecSuccess { SecItemAdd((q.merging(u) { _, n in n }) as CFDictionary, nil) }
    }

    static func migrate() {
        guard kcGet("host") == nil || kcGet("user") == nil else { return }
        let keys = ["serverHost": "host", "serverUser": "user", "sshKeyPath": "keyPath"]
        for (ud, kc) in keys {
            if let v = UserDefaults.standard.string(forKey: ud), !v.isEmpty { kcSet(kc, v) }
            UserDefaults.standard.removeObject(forKey: ud)
        }
    }

    static var isCompactMode: Bool {
        get { UserDefaults.standard.bool(forKey: compactModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: compactModeKey) }
    }

    static var host: String {
        get { kcGet("host") ?? "" }
        set { kcSet("host", newValue) }
    }
    static var port: Int {
        get { let v = UserDefaults.standard.integer(forKey: "serverPort"); return v == 0 ? 22 : v }
        set { UserDefaults.standard.set(newValue, forKey: "serverPort") }
    }
    static var user: String {
        get { kcGet("user") ?? "" }
        set { kcSet("user", newValue) }
    }
    static var sshKeyPath: String {
        get { kcGet("keyPath") ?? "" }
        set { kcSet("keyPath", newValue) }
    }

    static var hasConfig: Bool { !host.isEmpty && !user.isEmpty }

    // S1+S5: block invalid keys, sanitize
    static func validateKey() -> KeyCheck {
        let p = (sshKeyPath as NSString).expandingTildeInPath
        guard !p.isEmpty else { return .ok }
        guard FileManager.default.fileExists(atPath: p) else { return .fail("Key not found: \(p)") }
        if let a = try? FileManager.default.attributesOfItem(atPath: p),
           let pm = a[.posixPermissions] as? UInt16, (pm & 0o022) != 0 {
            return .fail("Insecure key permissions (group/world-writable)")
        }
        return .ok
    }

    static var sshArgs: [String] {
        var a: [String] = []
        let p = (sshKeyPath as NSString).expandingTildeInPath
        if !p.isEmpty { a += ["-i", p] }
        if port != 22 { a += ["-p", String(port)] }
        a.append("\(s(user))@\(s(host))")
        return a
    }

    // S5: only hostname-safe chars
    private static func s(_ v: String) -> String {
        v.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "", options: .regularExpression)
    }
}

enum KeyCheck {
    case ok, fail(String)
}
