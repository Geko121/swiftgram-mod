import Foundation
import Postbox
import SwiftSignalKit

// MARK: Swiftgram Mod — Deleted Messages Log: one list of the messages anti-revoke kept, newest
// first, across all chats. An entry is a snapshot (text, media kind, dates), so the log still
// reads after the message itself is gone; tapping one opens the message if it is still stored.
// Kept in a Postbox ordered item list, written in the transaction that marks the message deleted.
private let sgDeletedMessagesLogCollectionId: Int32 = 1000
private let sgDeletedMessagesLogMaxCount = 2000
private let sgDeletedMessagesLogMaxTextLength = 4000

public struct SGDeletedMessageLogEntry: Codable, Equatable {
    public let messageId: MessageId
    public let authorId: PeerId?
    public let text: String
    /// "photo", "video", "round", "voice", "audio", "gif", "sticker", "file", "poll", "location",
    /// "contact", or "" for a text-only message.
    public let mediaKind: String
    public let date: Int32
    public let deletedDate: Int32

    init(messageId: MessageId, authorId: PeerId?, text: String, mediaKind: String, date: Int32, deletedDate: Int32) {
        self.messageId = messageId
        self.authorId = authorId
        self.text = text
        self.mediaKind = mediaKind
        self.date = date
        self.deletedDate = deletedDate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        let peerId = PeerId(try container.decode(Int64.self, forKey: "p"))
        let namespace = try container.decode(Int32.self, forKey: "n")
        let id = try container.decode(Int32.self, forKey: "i")
        self.messageId = MessageId(peerId: peerId, namespace: namespace, id: id)
        let authorId = try container.decode(Int64.self, forKey: "a")
        self.authorId = authorId == 0 ? nil : PeerId(authorId)
        self.text = try container.decode(String.self, forKey: "t")
        self.mediaKind = try container.decode(String.self, forKey: "m")
        self.date = try container.decode(Int32.self, forKey: "d")
        self.deletedDate = try container.decode(Int32.self, forKey: "x")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode(self.messageId.peerId.toInt64(), forKey: "p")
        try container.encode(self.messageId.namespace, forKey: "n")
        try container.encode(self.messageId.id, forKey: "i")
        try container.encode(self.authorId?.toInt64() ?? 0, forKey: "a")
        try container.encode(self.text, forKey: "t")
        try container.encode(self.mediaKind, forKey: "m")
        try container.encode(self.date, forKey: "d")
        try container.encode(self.deletedDate, forKey: "x")
    }
}

public struct SGDeletedMessageLogItem: Equatable {
    public let entry: SGDeletedMessageLogEntry
    public let chat: EnginePeer?
    public let author: EnginePeer?
}

private func sgDeletedMessagesLogItemId(_ messageId: MessageId) -> MemoryBuffer {
    var peerIdValue: Int64 = messageId.peerId.toInt64()
    var namespaceValue: Int32 = messageId.namespace
    var idValue: Int32 = messageId.id
    let buffer = MemoryBuffer(memory: malloc(16)!, capacity: 16, length: 16, freeWhenDone: true)
    memcpy(buffer.memory, &peerIdValue, 8)
    memcpy(buffer.memory.advanced(by: 8), &namespaceValue, 4)
    memcpy(buffer.memory.advanced(by: 12), &idValue, 4)
    return buffer
}

private func sgDeletedMessageMediaKind(_ message: Message) -> String {
    for media in message.media {
        if media is TelegramMediaImage {
            return "photo"
        } else if let file = media as? TelegramMediaFile {
            if file.isInstantVideo {
                return "round"
            } else if file.isVoice {
                return "voice"
            } else if file.isSticker {
                return "sticker"
            } else if file.isAnimated {
                return "gif"
            } else if file.isVideo {
                return "video"
            } else if file.isMusic {
                return "audio"
            } else {
                return "file"
            }
        } else if media is TelegramMediaPoll {
            return "poll"
        } else if media is TelegramMediaMap {
            return "location"
        } else if media is TelegramMediaContact {
            return "contact"
        }
    }
    return ""
}

/// Records a message anti-revoke just kept. Service messages (joins, pins, …) are not logged.
func sgAddDeletedMessagesLogEntry(transaction: Transaction, message: Message, deletedDate: Int32) {
    if message.media.contains(where: { $0 is TelegramMediaAction }) {
        return
    }
    let entry = SGDeletedMessageLogEntry(
        messageId: message.id,
        authorId: message.author?.id,
        text: String(message.text.prefix(sgDeletedMessagesLogMaxTextLength)),
        mediaKind: sgDeletedMessageMediaKind(message),
        date: message.timestamp,
        deletedDate: deletedDate
    )
    if let contents = CodableEntry(entry) {
        transaction.addOrMoveToFirstPositionOrderedItemListItem(collectionId: sgDeletedMessagesLogCollectionId, item: OrderedItemListEntry(id: sgDeletedMessagesLogItemId(message.id), contents: contents), removeTailIfCountExceeds: sgDeletedMessagesLogMaxCount)
    }
}

/// The log, newest first, with each entry's chat and author resolved. Updates live.
public func sgDeletedMessagesLog(account: Account) -> Signal<[SGDeletedMessageLogItem], NoError> {
    let postbox = account.postbox
    let key: PostboxViewKey = .orderedItemList(id: sgDeletedMessagesLogCollectionId)
    return postbox.combinedView(keys: [key])
    |> map { views -> [SGDeletedMessageLogEntry] in
        guard let view = views.views[key] as? OrderedItemListView else {
            return []
        }
        return view.items.compactMap { $0.contents.get(SGDeletedMessageLogEntry.self) }
    }
    |> distinctUntilChanged
    |> mapToSignal { entries -> Signal<[SGDeletedMessageLogItem], NoError> in
        return postbox.transaction { transaction -> [SGDeletedMessageLogItem] in
            return entries.map { entry in
                let chat = transaction.getPeer(entry.messageId.peerId).flatMap { EnginePeer($0) }
                let author = entry.authorId.flatMap { transaction.getPeer($0) }.flatMap { EnginePeer($0) }
                return SGDeletedMessageLogItem(entry: entry, chat: chat, author: author)
            }
        }
    }
}

/// Empties the log. The kept messages themselves stay in their chats.
public func sgClearDeletedMessagesLog(account: Account) -> Signal<Never, NoError> {
    return account.postbox.transaction { transaction -> Void in
        transaction.replaceOrderedItemListItems(collectionId: sgDeletedMessagesLogCollectionId, items: [])
    }
    |> ignoreValues
}
