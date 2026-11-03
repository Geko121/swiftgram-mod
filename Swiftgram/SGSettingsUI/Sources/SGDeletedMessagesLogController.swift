import SGStrings
//
import AccountContext
import Display
import Foundation
import ItemListUI
import LocalizedPeerData
import PresentationDataUtils
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import UIKit

// MARK: Swiftgram Mod — Deleted Messages Log (Settings > Swiftgram > MOD FEATURES): every message
// anti-revoke kept, newest first, across all chats. Tapping one opens it in its chat.
private final class SGDeletedMessagesLogArguments {
    let openMessage: (SGDeletedMessageLogItem) -> Void
    let clearLog: () -> Void

    init(openMessage: @escaping (SGDeletedMessageLogItem) -> Void, clearLog: @escaping () -> Void) {
        self.openMessage = openMessage
        self.clearLog = clearLog
    }
}

private enum SGDeletedMessagesLogSection: Int32 {
    case info
    case messages
    case actions
}

private enum SGDeletedMessagesLogEntryId: Hashable {
    case info
    case empty
    case message(EngineMessage.Id)
    case clear
}

private enum SGDeletedMessagesLogEntry: ItemListNodeEntry {
    case info(text: String)
    case empty(text: String)
    case message(index: Int, item: SGDeletedMessageLogItem, label: String, text: String)
    case clear(text: String)

    var section: ItemListSectionId {
        switch self {
        case .info:
            return SGDeletedMessagesLogSection.info.rawValue
        case .empty, .message:
            return SGDeletedMessagesLogSection.messages.rawValue
        case .clear:
            return SGDeletedMessagesLogSection.actions.rawValue
        }
    }

    var stableId: SGDeletedMessagesLogEntryId {
        switch self {
        case .info:
            return .info
        case .empty:
            return .empty
        case let .message(_, item, _, _):
            return .message(item.entry.messageId)
        case .clear:
            return .clear
        }
    }

    private var sortIndex: Int {
        switch self {
        case .info:
            return 0
        case .empty:
            return 1
        case let .message(index, _, _, _):
            return 2 + index
        case .clear:
            return Int.max
        }
    }

    static func <(lhs: SGDeletedMessagesLogEntry, rhs: SGDeletedMessagesLogEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SGDeletedMessagesLogArguments
        switch self {
        case let .info(text), let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .message(_, item, label, text):
            return ItemListTextWithLabelItem(presentationData: presentationData, label: label, text: text, style: .blocks, enabledEntityTypes: [], multiline: true, sectionId: self.section, action: {
                arguments.openMessage(item)
            })
        case let .clear(text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clearLog()
            })
        }
    }
}

private func sgDeletedMessagesLogEntries(presentationData: PresentationData, items: [SGDeletedMessageLogItem]) -> [SGDeletedMessagesLogEntry] {
    let strings = presentationData.strings
    let lang = strings.baseLanguageCode

    var entries: [SGDeletedMessagesLogEntry] = []
    entries.append(.info(text: i18n("DeletedLog.Info", lang)))
    if items.isEmpty {
        entries.append(.empty(text: i18n("DeletedLog.Empty", lang)))
        return entries
    }

    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .short
    dateFormatter.timeStyle = .short

    for (index, item) in items.enumerated() {
        var label = item.chat?.displayTitle(strings: strings, displayOrder: presentationData.nameDisplayOrder) ?? i18n("DeletedLog.UnknownChat", lang)
        if let author = item.author, author.id != item.chat?.id {
            label += " · " + author.displayTitle(strings: strings, displayOrder: presentationData.nameDisplayOrder)
        }
        label += " · " + dateFormatter.string(from: Date(timeIntervalSince1970: Double(item.entry.date)))

        var text = item.entry.text
        if !item.entry.mediaKind.isEmpty {
            let mediaLabel = "[" + i18n("DeletedLog.Media.\(item.entry.mediaKind)", lang) + "]"
            text = text.isEmpty ? mediaLabel : mediaLabel + " " + text
        }
        if text.isEmpty {
            text = i18n("DeletedLog.NoText", lang)
        } else if text.count > 500 {
            text = String(text.prefix(500)) + "…"
        }
        entries.append(.message(index: index, item: item, label: label, text: text))
    }
    entries.append(.clear(text: i18n("DeletedLog.Clear", lang)))
    return entries
}

public func sgDeletedMessagesLogController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var navigationControllerImpl: (() -> NavigationController?)?

    let arguments = SGDeletedMessagesLogArguments(openMessage: { item in
        guard let chat = item.chat, let navigationController = navigationControllerImpl?() else {
            return
        }
        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(chat), subject: .message(id: .id(item.entry.messageId), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false), keepStack: .always))
    }, clearLog: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        presentControllerImpl?(textAlertController(context: context, title: nil, text: i18n("DeletedLog.Clear.Confirm", lang), actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: i18n("DeletedLog.Clear", lang), action: {
                let _ = sgClearDeletedMessagesLog(account: context.account).start()
            })
        ]))
    })

    let signal = combineLatest(queue: Queue.mainQueue(), context.sharedContext.presentationData, sgDeletedMessagesLog(account: context.account))
    |> map { presentationData, items -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(i18n("DeletedLog.Title", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: sgDeletedMessagesLogEntries(presentationData: presentationData, items: items), style: .blocks)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root), with: nil)
    }
    navigationControllerImpl = { [weak controller] in
        return controller?.navigationController as? NavigationController
    }
    return controller
}
