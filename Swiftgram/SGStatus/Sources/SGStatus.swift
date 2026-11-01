import Foundation
import SwiftSignalKit
import TelegramCore

public struct SGStatus: Equatable, Codable {
    public var status: Int64

    // MARK: Swiftgram Mod — Pro unlocked
    // Self-built IPAs have no App Store IAP: every status comparison in the app is
    // `status > 1` / `status < 2`, so 2 is the canonical Pro value.
    public static let proUnlockedValue: Int64 = 2

    public static var `default`: SGStatus {
        return SGStatus(status: SGStatus.proUnlockedValue)
    }

    public init(status: Int64) {
        self.status = status
    }

    public init(from decoder: Decoder) throws {
        // MARK: Swiftgram Mod — Pro unlocked: clamp any persisted value (including a
        // free-tier 1 written by an earlier install) to Pro
        self.status = SGStatus.proUnlockedValue
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encodeIfPresent(self.status, forKey: "status")
    }
}

public func updateSGStatusInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (SGStatus) -> SGStatus) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.sgStatus, { entry in
            let currentSettings: SGStatus
            if let entry = entry?.get(SGStatus.self) {
                currentSettings = entry
            } else {
                currentSettings = SGStatus.default
            }
            return SharedPreferencesEntry(f(currentSettings))
        })
    }
}
