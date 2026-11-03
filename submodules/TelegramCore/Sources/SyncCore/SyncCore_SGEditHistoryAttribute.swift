import Foundation
import Postbox

// MARK: Swiftgram Mod — edit history: the versions of a message's text that a server edit
// replaced, oldest first. Each entry's date is when that version became current (the send
// date for the original, the edit date for later ones). Recorded and carried over in
// mergedServerMessageUpdate; shown by the "Edit History" context menu item.
public class SGEditHistoryAttribute: MessageAttribute {
    public struct Entry: Equatable {
        public let text: String
        public let date: Int32
        
        public init(text: String, date: Int32) {
            self.text = text
            self.date = date
        }
    }
    
    public static let maxEntries = 50
    
    public let entries: [Entry]
    
    public init(entries: [Entry]) {
        self.entries = entries
    }
    
    required public init(decoder: PostboxDecoder) {
        let texts = decoder.decodeStringArrayForKey("t")
        let dates = decoder.decodeInt32ArrayForKey("d")
        var entries: [Entry] = []
        for i in 0 ..< min(texts.count, dates.count) {
            entries.append(Entry(text: texts[i], date: dates[i]))
        }
        self.entries = entries
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeStringArray(self.entries.map { $0.text }, forKey: "t")
        encoder.encodeInt32Array(self.entries.map { $0.date }, forKey: "d")
    }
}
