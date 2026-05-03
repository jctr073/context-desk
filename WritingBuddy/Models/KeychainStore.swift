import Foundation
import Security

enum KeychainError: Error {
    case osStatus(OSStatus)
    case invalidData
}

enum KeychainStore {
    private static let service = "com.writingbuddy.apikeys"

    static func save(_ key: String, for provider: AIProvider) throws {
        guard let data = key.data(using: .utf8) else { throw KeychainError.invalidData }

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            let attrs: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
            guard updateStatus == errSecSuccess else { throw KeychainError.osStatus(updateStatus) }
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.osStatus(addStatus) }
        default:
            throw KeychainError.osStatus(status)
        }
    }

    static func read(for provider: AIProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for provider: AIProvider) throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
    }

    static func exists(for provider: AIProvider) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}

enum APIKeyStore {
    static func read(for provider: AIProvider) -> String? {
        if let key = ShellProfileAPIKeyStore.readKey(for: provider) {
            return key
        }

        return KeychainStore.read(for: provider)
    }

    static func exists(for provider: AIProvider) -> Bool {
        read(for: provider) != nil
    }
}

private enum ShellProfileAPIKeyStore {
    private static var zshrcURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zshrc")
    }

    static func readKey(for provider: AIProvider) -> String? {
        guard let contents = try? String(contentsOf: zshrcURL, encoding: .utf8) else {
            return nil
        }

        for keyName in provider.shellAPIKeyNames {
            if let key = shellAssignment(named: keyName, in: contents) {
                return key
            }
        }

        return nil
    }

    private static func shellAssignment(named variable: String, in contents: String) -> String? {
        var parsedValue: String?

        for line in contents.components(separatedBy: .newlines) {
            guard let value = shellAssignment(named: variable, fromLine: line) else {
                continue
            }
            parsedValue = value
        }

        return parsedValue
    }

    private static func shellAssignment(named variable: String, fromLine rawLine: String) -> String? {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }

        for prefix in ["export ", "typeset -x ", "typeset -gx ", "declare -x "] {
            if line.hasPrefix(prefix) {
                line.removeFirst(prefix.count)
                line = line.trimmingCharacters(in: .whitespaces)
                break
            }
        }

        guard line.hasPrefix(variable) else { return nil }

        var remainder = line.dropFirst(variable.count)
        remainder = remainder.drop(while: { $0 == " " || $0 == "\t" })
        guard remainder.first == "=" else { return nil }

        remainder = remainder.dropFirst()
        let value = shellValue(from: String(remainder).trimmingCharacters(in: .whitespaces))

        guard !value.isEmpty,
              !value.hasPrefix("$"),
              !value.contains("$("),
              !value.contains("`") else {
            return nil
        }

        return value
    }

    private static func shellValue(from rawValue: String) -> String {
        guard let first = rawValue.first else { return "" }

        if first == "'" {
            return String(rawValue.dropFirst().prefix { $0 != "'" })
        }

        if first == "\"" {
            return doubleQuotedValue(from: rawValue)
        }

        return String(rawValue.prefix { char in
            !char.isWhitespace && char != "#" && char != ";"
        })
    }

    private static func doubleQuotedValue(from rawValue: String) -> String {
        var value = ""
        var isEscaped = false

        for char in rawValue.dropFirst() {
            if isEscaped {
                value.append(char)
                isEscaped = false
                continue
            }

            if char == "\\" {
                isEscaped = true
                continue
            }

            if char == "\"" {
                break
            }

            value.append(char)
        }

        return value
    }
}
