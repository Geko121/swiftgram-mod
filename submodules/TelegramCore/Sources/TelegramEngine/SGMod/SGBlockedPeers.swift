import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi

// MARK: Swiftgram Mod — Hide Blocked Users: the peers each account has blocked. Telegram keeps a
// user's blocked flag only in their cached data, which most group members never get, so the full
// list is fetched once per launch (contacts.getBlocked) and kept current from updatePeerBlocked and
// local block / unblock. Mirrored to UserDefaults so it is there before the fetch completes.
public final class SGBlockedPeers {
    public static let shared = SGBlockedPeers()

    private final class AccountState {
        var peerIds: Set<PeerId>
        let promise: ValuePromise<Set<PeerId>>
        var isFetchStarted = false

        init(peerIds: Set<PeerId>) {
            self.peerIds = peerIds
            self.promise = ValuePromise(peerIds, ignoreRepeated: true)
        }
    }

    private let queue = Queue()
    private var states: [PeerId: AccountState] = [:]
    private let fetchDisposables = DisposableSet()

    private init() {
    }

    private static func defaultsKey(accountPeerId: PeerId) -> String {
        return "SGBlockedPeers.\(accountPeerId.toInt64())"
    }

    // Called on self.queue only.
    private func state(accountPeerId: PeerId) -> AccountState {
        if let current = self.states[accountPeerId] {
            return current
        }
        var peerIds = Set<PeerId>()
        if let stored = UserDefaults.standard.array(forKey: SGBlockedPeers.defaultsKey(accountPeerId: accountPeerId)) as? [Int64] {
            peerIds = Set(stored.map { PeerId($0) })
        }
        let state = AccountState(peerIds: peerIds)
        self.states[accountPeerId] = state
        return state
    }

    // Called on self.queue only.
    private func setPeerIds(_ peerIds: Set<PeerId>, accountPeerId: PeerId) {
        let state = self.state(accountPeerId: accountPeerId)
        if state.peerIds == peerIds {
            return
        }
        state.peerIds = peerIds
        state.promise.set(peerIds)
        UserDefaults.standard.set(peerIds.map { $0.toInt64() }, forKey: SGBlockedPeers.defaultsKey(accountPeerId: accountPeerId))
    }

    func update(accountPeerId: PeerId, peerId: PeerId, isBlocked: Bool) {
        self.queue.async {
            var peerIds = self.state(accountPeerId: accountPeerId).peerIds
            if isBlocked {
                peerIds.insert(peerId)
            } else {
                peerIds.remove(peerId)
            }
            self.setPeerIds(peerIds, accountPeerId: accountPeerId)
        }
    }

    /// The account's blocked peers. The first subscription in a launch also fetches the full list.
    public func blockedPeerIds(account: Account) -> Signal<Set<PeerId>, NoError> {
        let accountPeerId = account.peerId
        let network = account.network
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.queue.async {
                let state = self.state(accountPeerId: accountPeerId)
                if !state.isFetchStarted {
                    state.isFetchStarted = true
                    self.fetchDisposables.add(sgFetchAllBlockedPeerIds(network: network).start(next: { peerIds in
                        self.queue.async {
                            self.setPeerIds(peerIds, accountPeerId: accountPeerId)
                        }
                    }))
                }
                disposable.set(state.promise.get().start(next: { peerIds in
                    subscriber.putNext(peerIds)
                }))
            }
            return disposable
        }
    }
}

// Pages through contacts.getBlocked. Emits nothing when a page fails, so the stored set stays.
private func sgFetchAllBlockedPeerIds(network: Network) -> Signal<Set<PeerId>, NoError> {
    func fetchPage(offset: Int32, collected: Set<PeerId>) -> Signal<Set<PeerId>, NoError> {
        return network.request(Api.functions.contacts.getBlocked(flags: 0, offset: offset, limit: 200))
        |> map(Optional.init)
        |> `catch` { _ -> Signal<Api.contacts.Blocked?, NoError> in
            return .single(nil)
        }
        |> mapToSignal { result -> Signal<Set<PeerId>, NoError> in
            guard let result else {
                return .complete()
            }
            var collected = collected
            let blocked: [Api.PeerBlocked]
            var totalCount: Int32?
            switch result {
            case let .blocked(blockedData):
                blocked = blockedData.blocked
            case let .blockedSlice(blockedSliceData):
                blocked = blockedSliceData.blocked
                totalCount = blockedSliceData.count
            }
            for blockedPeer in blocked {
                switch blockedPeer {
                case let .peerBlocked(peerBlockedData):
                    collected.insert(peerBlockedData.peerId.peerId)
                }
            }
            let nextOffset = offset + Int32(blocked.count)
            if let totalCount, !blocked.isEmpty, nextOffset < totalCount, nextOffset < 10000 {
                return fetchPage(offset: nextOffset, collected: collected)
            }
            return .single(collected)
        }
    }
    return fetchPage(offset: 0, collected: Set())
}
