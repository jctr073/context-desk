import Foundation

enum APIKeyStore {
    static var profileFileLabels: [String] {
        ShellProfileAPIKeyStore.profileFileLabels
    }

    static func read(for provider: AIProvider) -> String? {
        if let key = ShellProfileAPIKeyStore.readKey(for: provider) {
            return key
        }

        for keyName in provider.shellAPIKeyNames {
            if let key = normalizedKey(ProcessInfo.processInfo.environment[keyName]) {
                return key
            }
        }

        return nil
    }

    static func exists(for provider: AIProvider) -> Bool {
        read(for: provider) != nil
    }

    private static func normalizedKey(_ rawKey: String?) -> String? {
        guard let key = rawKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            return nil
        }

        return key
    }
}

private enum ShellProfileAPIKeyStore {
    static let profileFileLabels = [
        "~/.zshrc",
        "~/.zprofile",
        "~/.zshenv",
        "~/.profile",
        "~/.bash_profile",
        "~/.bashrc",
    ]

    private static var profileURLs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return profileFileLabels.map { label in
            home.appendingPathComponent(String(label.dropFirst(2)))
        }
    }

    static func readKey(for provider: AIProvider) -> String? {
        for profileURL in profileURLs {
            guard let contents = try? String(contentsOf: profileURL, encoding: .utf8) else {
                continue
            }

            for keyName in provider.shellAPIKeyNames {
                if let key = shellAssignment(named: keyName, in: contents) {
                    return key
                }
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
