import Foundation

public enum UsageQuotaCredentials {
    public static let service = "com.morax.garage.usage"
    private static let secret = KeychainSecret(service: service, account: "internal-key")

    public static func read() -> String? { secret.read() }

    @discardableResult
    public static func write(_ value: String) -> Bool { secret.write(value) }

    @discardableResult
    public static func delete() -> Bool { secret.delete() }
}

/// OpenAI organization admin key (`sk-admin-…`). Regular project keys cannot read
/// `/v1/organization/costs`, which is the only endpoint reporting what was billed.
public enum OpenAIAdminCredentials {
    private static let secret = KeychainSecret(service: UsageQuotaCredentials.service, account: "openai-admin-key")

    public static func read() -> String? { secret.read() }

    /// Stores the trimmed key, or removes the item when the field was emptied.
    @discardableResult
    public static func write(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? secret.delete() : secret.write(trimmed)
    }
}
