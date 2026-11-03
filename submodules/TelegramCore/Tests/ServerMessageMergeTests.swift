import XCTest
import Postbox
import SGSimpleSettings
@testable import TelegramCore

/// `mergedServerMessageUpdate`: the server's copy of a stored message keeps the state the server does not send.
/// Edit updates have always merged this way; feed pages, which refresh posts the account already stores, do too.
final class ServerMessageMergeTests: XCTestCase {
    private let channel = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(1))

    private var messageId: MessageId {
        return MessageId(peerId: self.channel, namespace: Namespaces.Message.Cloud, id: 10)
    }

    private func stored(text: String, attributes: [MessageAttribute], media: [Media]) -> Message {
        return Message(stableId: 1, stableVersion: 0, id: self.messageId, globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 100, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: text, attributes: attributes, media: media, peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    private func fromServer(text: String, media: [Media]) -> StoreMessage {
        return StoreMessage(id: self.messageId, customStableId: nil, globallyUniqueId: nil, groupingKey: nil, threadId: nil, timestamp: 100, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, authorId: nil, text: text, attributes: [], media: media)
    }

    private func fromServer(text: String, attributes: [MessageAttribute]) -> StoreMessage {
        return StoreMessage(id: self.messageId, customStableId: nil, globallyUniqueId: nil, groupingKey: nil, threadId: nil, timestamp: 100, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, authorId: nil, text: text, attributes: attributes, media: [])
    }

    private func editHistory(_ message: StoreMessage) -> [SGEditHistoryAttribute.Entry]? {
        return (message.attributes.first(where: { $0 is SGEditHistoryAttribute }) as? SGEditHistoryAttribute)?.entries
    }

    func testTranslationSurvivesTheSameText() {
        let translation = TranslationMessageAttribute(text: "Hallo", entities: [], toLang: "de")
        let merged = mergedServerMessageUpdate(previous: self.stored(text: "Hello", attributes: [translation], media: []), updated: self.fromServer(text: "Hello", media: []))
        XCTAssertTrue(merged.attributes.contains(where: { $0 is TranslationMessageAttribute }))
    }

    func testTranslationIsDroppedWhenTheTextChanged() {
        let translation = TranslationMessageAttribute(text: "Hallo", entities: [], toLang: "de")
        let merged = mergedServerMessageUpdate(previous: self.stored(text: "Hello", attributes: [translation], media: []), updated: self.fromServer(text: "Hello!", media: []))
        XCTAssertFalse(merged.attributes.contains(where: { $0 is TranslationMessageAttribute }))
    }

    // A purchased paid post must not fall back to its locked preview.
    func testUnlockedPaidMediaSurvives() {
        let image = TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.CloudImage, id: 1), representations: [], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        let unlocked = TelegramMediaPaidContent(amount: 10, extendedMedia: [.full(media: image)])
        let locked = TelegramMediaPaidContent(amount: 10, extendedMedia: [.preview(dimensions: nil, immediateThumbnailData: nil, videoDuration: nil)])
        let merged = mergedServerMessageUpdate(previous: self.stored(text: "", attributes: [], media: [unlocked]), updated: self.fromServer(text: "", media: [locked]))
        guard let paid = merged.media.first as? TelegramMediaPaidContent, case .full = paid.extendedMedia.first else {
            XCTFail("the paid media went back to its preview")
            return
        }
    }

    // MARK: Swiftgram Mod — edit history and the anti-revoke marker are local-only attributes.

    // An edit records the text it replaced, dated when that text became current (the send date).
    func testEditRecordsTheReplacedText() {
        SGSimpleSettings.shared.saveEditHistory = true
        let merged = mergedServerMessageUpdate(previous: self.stored(text: "Hello", attributes: [], media: []), updated: self.fromServer(text: "Hello!", attributes: [EditedMessageAttribute(date: 200, isHidden: false)]))
        XCTAssertEqual(self.editHistory(merged), [SGEditHistoryAttribute.Entry(text: "Hello", date: 100)])
    }

    // A second edit appends, dating the replaced version by the previous edit.
    func testSecondEditAppendsToTheHistory() {
        SGSimpleSettings.shared.saveEditHistory = true
        let previous = self.stored(text: "Hello!", attributes: [EditedMessageAttribute(date: 200, isHidden: false), SGEditHistoryAttribute(entries: [SGEditHistoryAttribute.Entry(text: "Hello", date: 100)])], media: [])
        let merged = mergedServerMessageUpdate(previous: previous, updated: self.fromServer(text: "Hello!!", attributes: [EditedMessageAttribute(date: 300, isHidden: false)]))
        XCTAssertEqual(self.editHistory(merged), [SGEditHistoryAttribute.Entry(text: "Hello", date: 100), SGEditHistoryAttribute.Entry(text: "Hello!", date: 200)])
    }

    // A server copy with the same text (a reaction or view-count update) keeps the history as is.
    func testHistorySurvivesAnUpdateThatIsNotAnEdit() {
        SGSimpleSettings.shared.saveEditHistory = true
        let history = SGEditHistoryAttribute(entries: [SGEditHistoryAttribute.Entry(text: "Hello", date: 100)])
        let previous = self.stored(text: "Hello!", attributes: [EditedMessageAttribute(date: 200, isHidden: false), history], media: [])
        let merged = mergedServerMessageUpdate(previous: previous, updated: self.fromServer(text: "Hello!", attributes: [EditedMessageAttribute(date: 200, isHidden: false)]))
        XCTAssertEqual(self.editHistory(merged), history.entries)
    }

    // A text change without an edit mark is not an edit, so nothing is recorded.
    func testTextChangeWithoutEditMarkIsNotRecorded() {
        SGSimpleSettings.shared.saveEditHistory = true
        let merged = mergedServerMessageUpdate(previous: self.stored(text: "Hello", attributes: [], media: []), updated: self.fromServer(text: "Hello!", media: []))
        XCTAssertNil(self.editHistory(merged))
    }

    func testNothingIsRecordedWhileTheSettingIsOff() {
        SGSimpleSettings.shared.saveEditHistory = false
        defer {
            SGSimpleSettings.shared.saveEditHistory = true
        }
        let merged = mergedServerMessageUpdate(previous: self.stored(text: "Hello", attributes: [], media: []), updated: self.fromServer(text: "Hello!", attributes: [EditedMessageAttribute(date: 200, isHidden: false)]))
        XCTAssertNil(self.editHistory(merged))
    }

    func testDeletedMarkerSurvives() {
        let merged = mergedServerMessageUpdate(previous: self.stored(text: "Hello", attributes: [SGDeletedMessageAttribute(timestamp: 150)], media: []), updated: self.fromServer(text: "Hello", media: []))
        XCTAssertTrue(merged.attributes.contains(where: { $0 is SGDeletedMessageAttribute }))
    }
}
