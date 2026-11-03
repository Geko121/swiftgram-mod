import SGSimpleSettings
import SGStrings
//
import AccountContext
import ChatControllerInteraction
import ChatPresentationInterfaceState
import ContextUI
import Display
import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramStringFormatting
import UIKit
import UndoUI

// MARK: Swiftgram Mod — "Edit History" message context menu item. Pushes a submenu with every
// version of an edited message (SGEditHistoryAttribute + the current text), newest first.
// Tapping a version copies it.
func sgMakeEditHistoryContextMenuAction(chatPresentationInterfaceState: ChatPresentationInterfaceState, controllerInteraction: ChatControllerInteraction, message: EngineRawMessage) -> ContextMenuItem? {
    guard let attribute = message.attributes.first(where: { $0 is SGEditHistoryAttribute }) as? SGEditHistoryAttribute, !attribute.entries.isEmpty else {
        return nil
    }
    let strings = chatPresentationInterfaceState.strings
    let lang = strings.baseLanguageCode
    let dateTimeFormat = chatPresentationInterfaceState.dateTimeFormat

    let currentDate = (message.attributes.first(where: { $0 is EditedMessageAttribute }) as? EditedMessageAttribute)?.date ?? message.timestamp
    var versions: [(text: String, date: Int32)] = attribute.entries.map { (text: $0.text, date: $0.date) }
    versions.append((text: message.text, date: currentDate))

    var popItems: (() -> Void)?
    var items: [ContextMenuItem] = []
    items.append(.action(ContextMenuActionItem(text: strings.Common_Back, icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Back"), color: theme.actionSheet.primaryTextColor)
    }, iconPosition: .left, action: { _, _ in
        popItems?()
    })))

    let lastIndex = versions.count - 1
    for index in stride(from: lastIndex, through: 0, by: -1) {
        let version = versions[index]
        let label: String
        if index == lastIndex {
            label = i18n("EditHistory.Current", lang)
        } else if index == 0 {
            label = i18n("EditHistory.Original", lang)
        } else {
            label = i18n("EditHistory.Edited", lang)
        }
        let header = "\(label) · \(stringForFullDate(timestamp: version.date, strings: strings, dateTimeFormat: dateTimeFormat))"

        var displayText = version.text
        if displayText.isEmpty {
            displayText = i18n("EditHistory.NoText", lang)
        } else if displayText.count > 1000 {
            displayText = String(displayText.prefix(1000)) + "…"
        }
        let fullText = version.text

        let noAction: ((ContextMenuActionItem.Action) -> Void)? = nil
        var copyAction: ((ContextMenuActionItem.Action) -> Void)? = nil
        if !fullText.isEmpty {
            copyAction = { action in
                UIPasteboard.general.string = fullText
                controllerInteraction.displayUndo(.copy(text: strings.Conversation_TextCopied))
                action.dismissWithResult(.default)
            }
        }

        items.append(.separator)
        items.append(.action(ContextMenuActionItem(text: header, textColor: .disabled, textLayout: .singleLine, textFont: .small, icon: { _ in
            return nil
        }, action: noAction)))
        items.append(.action(ContextMenuActionItem(text: displayText, textLayout: .multiline, icon: { _ in
            return nil
        }, action: copyAction)))
    }
    let versionItems = items

    return .action(ContextMenuActionItem(text: i18n("ContextMenu.EditHistory", lang), textLayout: .secondLineWithValue(i18n("EditHistory.Versions", lang, "\(versions.count)")), icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Edit"), color: theme.actionSheet.primaryTextColor)
    }, action: { c, _ in
        popItems = { [weak c] in
            c?.popItems()
        }
        c?.pushItems(items: .single(ContextController.Items(content: .list(versionItems))))
    }))
}

// MARK: Swiftgram Mod — Ghost Mode "Send Read Receipt": while read receipts are hidden, push this
// chat's read position to the server once, so the sender sees it as read.
func sgMakeSendReadReceiptContextMenuAction(context: AccountContext, chatPresentationInterfaceState: ChatPresentationInterfaceState, controllerInteraction: ChatControllerInteraction, message: EngineRawMessage) -> ContextMenuItem? {
    guard SGSimpleSettings.shared.ghostReadReceipts, message.flags.contains(.Incoming) else {
        return nil
    }
    let lang = chatPresentationInterfaceState.strings.baseLanguageCode
    let peerId = message.id.peerId
    return .action(ContextMenuActionItem(text: i18n("ContextMenu.SendReadReceipt", lang), icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Read"), color: theme.actionSheet.primaryTextColor)
    }, action: { _, f in
        let _ = sgPushPeerReadState(account: context.account, peerId: peerId).start()
        controllerInteraction.displayUndo(.info(title: nil, text: i18n("ContextMenu.SendReadReceipt.Done", lang), timeout: nil, customUndoText: nil))
        f(.default)
    }))
}

// MARK: Swiftgram Mod — "Details" item in the Swiftgram submenu: message / chat / author IDs (in
// Bot API form) and exact timestamps with seconds. Tapping the details copies them.
func sgMakeMessageDetailsContextMenuAction(chatPresentationInterfaceState: ChatPresentationInterfaceState, controllerInteraction: ChatControllerInteraction, message: EngineRawMessage) -> ContextMenuItem {
    let strings = chatPresentationInterfaceState.strings
    let lang = strings.baseLanguageCode
    
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let formatDate: (Int32) -> String = { timestamp in
        return dateFormatter.string(from: Date(timeIntervalSince1970: Double(timestamp)))
    }
    let formatPeerId: (EnginePeer.Id) -> String = { peerId in
        let rawId = peerId.id._internalGetInt64Value()
        if peerId.namespace == Namespaces.Peer.CloudChannel {
            return "-100\(rawId)"
        } else if peerId.namespace == Namespaces.Peer.CloudGroup {
            return "-\(rawId)"
        } else {
            return "\(rawId)"
        }
    }
    
    var lines: [String] = []
    lines.append("\(i18n("MessageDetails.MessageId", lang)): \(message.id.id)")
    lines.append("\(i18n("MessageDetails.ChatId", lang)): \(formatPeerId(message.id.peerId))")
    if let author = message.author {
        lines.append("\(i18n("MessageDetails.AuthorId", lang)): \(formatPeerId(author.id))")
    }
    lines.append("\(i18n("MessageDetails.Sent", lang)): \(formatDate(message.timestamp))")
    if let editedAttribute = message.attributes.first(where: { $0 is EditedMessageAttribute }) as? EditedMessageAttribute {
        lines.append("\(i18n("MessageDetails.Edited", lang)): \(formatDate(editedAttribute.date))")
    }
    if let editHistoryAttribute = message.attributes.first(where: { $0 is SGEditHistoryAttribute }) as? SGEditHistoryAttribute {
        lines.append("\(i18n("MessageDetails.SavedVersions", lang)): \(editHistoryAttribute.entries.count)")
    }
    if let deletedAttribute = message.attributes.first(where: { $0 is SGDeletedMessageAttribute }) as? SGDeletedMessageAttribute, deletedAttribute.timestamp != 0 {
        lines.append("\(i18n("MessageDetails.Deleted", lang)): \(formatDate(deletedAttribute.timestamp))")
    }
    if let forwardInfo = message.forwardInfo {
        lines.append("\(i18n("MessageDetails.ForwardedDate", lang)): \(formatDate(forwardInfo.date))")
        if let forwardAuthor = forwardInfo.author {
            lines.append("\(i18n("MessageDetails.ForwardedFrom", lang)): \(formatPeerId(forwardAuthor.id))")
        }
    }
    if let groupingKey = message.groupingKey {
        lines.append("\(i18n("MessageDetails.AlbumId", lang)): \(groupingKey)")
    }
    let detailsText = lines.joined(separator: "\n")
    
    var popItems: (() -> Void)?
    var items: [ContextMenuItem] = []
    items.append(.action(ContextMenuActionItem(text: strings.Common_Back, icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Back"), color: theme.actionSheet.primaryTextColor)
    }, iconPosition: .left, action: { _, _ in
        popItems?()
    })))
    items.append(.separator)
    let copyAction: ((ContextMenuActionItem.Action) -> Void)? = { action in
        UIPasteboard.general.string = detailsText
        controllerInteraction.displayUndo(.copy(text: strings.Conversation_TextCopied))
        action.dismissWithResult(.default)
    }
    items.append(.action(ContextMenuActionItem(text: detailsText, textLayout: .multiline, textFont: .small, icon: { _ in
        return nil
    }, action: copyAction)))
    let detailsItems = items
    
    return .action(ContextMenuActionItem(text: i18n("ContextMenu.MessageDetails", lang), icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Info"), color: theme.actionSheet.primaryTextColor)
    }, action: { c, _ in
        popItems = { [weak c] in
            c?.popItems()
        }
        c?.pushItems(items: .single(ContextController.Items(content: .list(detailsItems))))
    }))
}
