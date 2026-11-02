import Foundation
import Postbox

// MARK: Swiftgram Mod — marks a message that was deleted server-side (delete-for-everyone,
// channel clean-up) but kept locally by the anti-revoke mod. Drives the optional
// "deleted" marker in the message timestamp label.
public class SGDeletedMessageAttribute: MessageAttribute {
    public let timestamp: Int32
    
    public init(timestamp: Int32) {
        self.timestamp = timestamp
    }
    
    required public init(decoder: PostboxDecoder) {
        self.timestamp = decoder.decodeInt32ForKey("t", orElse: 0)
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.timestamp, forKey: "t")
    }
}
