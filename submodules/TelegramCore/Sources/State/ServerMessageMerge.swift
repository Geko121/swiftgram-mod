import Foundation
import Postbox
import SGSimpleSettings

/// The server's copy of a message the account already stores, keeping what the server's copy does not carry:
/// the outgoing live-location tag, the stored Incoming flag, a translation while the text and entities are
/// unchanged, a resolved fact check over a pending one with the same hash, and unlocked paid media.
/// (`SeedConfiguration.mergeMessageAttributes`, which Postbox applies to every update, keeps the rest.)
/// Used by edit updates and by feed pages, which refresh posts the account may already store.
func mergedServerMessageUpdate(previous previousMessage: Message, updated message: StoreMessage) -> StoreMessage {
    var updatedFlags = message.flags
    var updatedLocalTags = message.localTags
    var updatedAttributes = message.attributes
    if previousMessage.localTags.contains(.OutgoingLiveLocation) {
        updatedLocalTags.insert(.OutgoingLiveLocation)
    }
    if previousMessage.flags.contains(.Incoming) {
        updatedFlags.insert(.Incoming)
    } else {
        updatedFlags.remove(.Incoming)
    }

    if previousMessage.text == message.text {
        let previousEntities = previousMessage.textEntitiesAttribute?.entities ?? []
        let updatedEntities = (message.attributes.first(where: { $0 is TextEntitiesMessageAttribute }) as? TextEntitiesMessageAttribute)?.entities ?? []
        if previousEntities == updatedEntities, let translation = previousMessage.attributes.first(where: { $0 is TranslationMessageAttribute }) as? TranslationMessageAttribute {
            if message.attributes.firstIndex(where: { $0 is TranslationMessageAttribute }) == nil {
                updatedAttributes.append(translation)
            }
        }
    }

    if let previousFactCheckAttribute = previousMessage.attributes.first(where: { $0 is FactCheckMessageAttribute }) as? FactCheckMessageAttribute, let updatedFactCheckAttribute = message.attributes.first(where: { $0 is FactCheckMessageAttribute }) as? FactCheckMessageAttribute {
        if case .Pending = updatedFactCheckAttribute.content, updatedFactCheckAttribute.hash == previousFactCheckAttribute.hash {
            updatedAttributes.removeAll(where: { $0 is FactCheckMessageAttribute })
            updatedAttributes.append(previousFactCheckAttribute)
        }
    }

    // MARK: Swiftgram Mod — the server copy doesn't carry the local-only mod attributes:
    // keep the anti-revoke marker and the edit history, and record the replaced text as a
    // new history entry when this update is an edit that changed it.
    if let deletedAttribute = previousMessage.attributes.first(where: { $0 is SGDeletedMessageAttribute }), !updatedAttributes.contains(where: { $0 is SGDeletedMessageAttribute }) {
        updatedAttributes.append(deletedAttribute)
    }
    var editHistory = (previousMessage.attributes.first(where: { $0 is SGEditHistoryAttribute }) as? SGEditHistoryAttribute)?.entries ?? []
    if SGSimpleSettings.shared.saveEditHistory && previousMessage.text != message.text && message.attributes.contains(where: { $0 is EditedMessageAttribute }) {
        let previousVersionDate = (previousMessage.attributes.first(where: { $0 is EditedMessageAttribute }) as? EditedMessageAttribute)?.date ?? previousMessage.timestamp
        editHistory.append(SGEditHistoryAttribute.Entry(text: previousMessage.text, date: previousVersionDate))
        if editHistory.count > SGEditHistoryAttribute.maxEntries {
            editHistory.removeFirst(editHistory.count - SGEditHistoryAttribute.maxEntries)
        }
    }
    if !editHistory.isEmpty {
        updatedAttributes.removeAll(where: { $0 is SGEditHistoryAttribute })
        updatedAttributes.append(SGEditHistoryAttribute(entries: editHistory))
    }

    var updatedMedia = message.media
    if let previousPaidContent = previousMessage.media.first(where: { $0 is TelegramMediaPaidContent }) as? TelegramMediaPaidContent, case .full = previousPaidContent.extendedMedia.first {
        updatedMedia = previousMessage.media
    }

    return message.withUpdatedLocalTags(updatedLocalTags).withUpdatedFlags(updatedFlags).withUpdatedAttributes(updatedAttributes).withUpdatedMedia(updatedMedia)
}
