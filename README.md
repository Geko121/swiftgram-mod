# Swiftgram Mod — self-built Telegram client for iOS

A personal build of [Swiftgram](https://github.com/Swiftgram/Telegram-iOS) (itself a fork of
[Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS)) with additional mods, compiled
to a sideloadable IPA by GitHub Actions on a macOS runner. **No Xcode or Mac required.**

## What's in this fork

Everything upstream Swiftgram ships (unlimited accounts, full customization, download/upload
boosts, translator, voice-to-text, session backup, 50+ settings…) **plus**:

| Mod | Default | What it does |
|---|---|---|
| **Pro unlocked** | always on | Swiftgram Pro is force-enabled. A self-built IPA has no App Store IAP, so the paywall and the backend status check are removed. All Pro features (session backup, message filter, formatting panel, unique app icons, Pro notifications settings) are available for free in this build. |
| **Keep deleted messages** | on | Messages deleted by others ("delete for everyone" in private chats, group/channel clean-ups) stay in your local history. Your own deletions work normally. |
| **Unrestricted saving** | on | Chats/channels with "protected content" (noforwards) behave like normal chats: save, forward, copy, share, download media, and take screenshots. The media bytes are already on your device to display them; only the client-side enforcement is removed. |
| **Ghost mode — read receipts** | off | Read messages without the server telling the other side. |
| **Ghost mode — typing indicator** | off | Never send "typing…" to anyone. |
| **Ghost mode — online status** | off | Never report yourself online; you appear as last-seen. |
| **Ghost mode — master switch** | off | One toggle for read receipts, typing, online status and story stealth together. |
| **Send Read Receipt** | with ghost reads | Long-press an incoming message → *Send Read Receipt* marks just that chat as read on the server while ghost mode stays on everywhere else. |
| **Stealth view-once & listened** | on | Opening view-once media or playing voice/video messages doesn't mark them viewed/listened for the sender. |
| **Deleted-message marker** | on | Kept deleted messages show a configurable "deleted" label (text + color). |
| **Edit history** | on | Previous versions of edited messages are kept. Long-press → *Edit History* lists every version with its time; tap one to copy it. |
| **Message details** | always | Long-press → Swiftgram → *Details*: message/chat/author IDs (Bot API form), sent/edited/deleted/forwarded times to the second. Tap to copy. |
| **Save any story** | with Unrestricted Saving | *Save to Gallery* for every story, including protected ones, without Premium. |
| **Bypass iOS-only restrictions** | off | Shows channels, bots and messages hidden only on iOS by App Store rules (as Desktop/Web show them). Restrictions for all platforms stay. |
| **Hide sponsored messages** | off | Never loads channel/video ads. Off by default: Telegram's API terms require clients to show them. |

All toggles live in **Settings → Swiftgram → MOD FEATURES** (bottom of the list).

## Mod map (where the changes live)

| Mod | File(s) |
|---|---|
| Pro unlock | `Swiftgram/SGStatus/Sources/SGStatus.swift` (status forced to 2), `Swiftgram/SGSimpleSettings/Sources/SimpleSettings.swift` (defaults), `submodules/TelegramUI/Sources/AppDelegate.swift` (`fetchSGStatus` disabled) |
| Keep deleted | `submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift` (`updateDeleteMessages`, `updateDeleteChannelMessages` — pts still advances) |
| Unrestricted saving | `submodules/TelegramCore/Sources/Utils/MessageUtils.swift` (`isCopyProtected`), `submodules/TelegramCore/Sources/Utils/PeerUtils.swift` (`isCopyProtectionEnabled`) |
| Ghost read receipts | `submodules/TelegramCore/Sources/State/SynchronizePeerReadState.swift` |
| Ghost typing | `submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift` |
| Ghost online | `submodules/TelegramCore/Sources/State/ManagedAccountPresence.swift` |
| Send Read Receipt | `submodules/TelegramCore/Sources/State/SynchronizePeerReadState.swift` (`sgPushPeerReadState`), `Swiftgram/SGTelegramUIExtensions/Sources/SGModContextMenu.swift` |
| Stealth view-once | `submodules/TelegramCore/Sources/TelegramEngine/Messages/MarkMessageContentAsConsumedInteractively.swift` |
| Deleted marker | `SyncCore_SGDeletedMessageAttribute.swift`, `AccountStateManagementUtils.swift`, `StringForMessageTimestampStatus.swift`, `ChatMessageDateAndStatusNode.swift` |
| Edit history | `submodules/TelegramCore/Sources/SyncCore/SyncCore_SGEditHistoryAttribute.swift`, `submodules/TelegramCore/Sources/State/ServerMessageMerge.swift`, `Swiftgram/SGTelegramUIExtensions/Sources/SGModContextMenu.swift` |
| Mod attribute registration | `submodules/TelegramCore/Sources/Account/AccountManager.swift` (`declareEncodable`) |
| Message details | `Swiftgram/SGTelegramUIExtensions/Sources/SGModContextMenu.swift`, `submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift` |
| Save any story | `submodules/TelegramUI/Components/Stories/StoryContainerScreen/Sources/StoryItemSetContainerComponent.swift` |
| iOS restriction bypass | `submodules/TelegramCore/Sources/Utils/PeerUtils.swift` (`restrictionText`), `submodules/PlatformRestrictionMatching/Sources/PlatformRestrictionMatching.swift` |
| Hide sponsored | `submodules/TelegramCore/Sources/TelegramEngine/Messages/AdMessages.swift` |
| Settings UI | `Swiftgram/SGSettingsUI/Sources/SGSettingsController.swift`, `Swiftgram/SGStrings/Strings/en.lproj/SGLocalizable.strings` |

All mods are tagged `// MARK: Swiftgram Mod` in the source.

## Build it

### 1. Push this repo to GitHub

Create an **empty** repository on GitHub (public is recommended: macOS runners cost 10× minutes
on private repos, and public repos get unlimited Actions minutes) and push:

```bash
git remote add origin git@github.com:YOUR_USERNAME/YOUR_REPO.git
git push -u origin main
```

### 2. Add your Telegram API credentials

Get your own `api_id` / `api_hash` at **https://my.telegram.org/apps** (Telegram requires every
self-built client to use its own application id), then add repository secrets:

- `Settings → Secrets and variables → Actions → New repository secret`
- `TELEGRAM_API_ID` — your numeric api_id
- `TELEGRAM_API_HASH` — your api_hash

### 3. Run the workflow

`Actions → Build Modded IPA → Run workflow`. The build takes roughly 60–120 minutes on the
first run (later runs reuse the Bazel cache). When it finishes, download the
`SwiftgramMod-…` artifact from the run page — it contains the unsigned IPA.

The IPA is built with fake codesigning against the well-known fake profile that ships in the
repo (`ph.telegra.Telegraph` / team `C67CF9S4VU`). Your sideload tool rewrites the bundle id and
re-signs it with your certificate when installing, so it coexists with App Store Telegram and
Swiftgram.

## Sideload

The produced IPA is unsigned — install it with any of:

- **TrollStore** (iOS 14.0–17.0, best option): no re-signing, no 7-day expiry, extensions work.
- **Sideloadly** (any iOS, free Apple ID): install with your Apple ID; free accounts get a
  7-day signing window and a 3-app limit.
- **AltStore / SideStore** (any iOS): same free-Apple-ID constraints, with on-device refresh.

Notes:

- The free-Apple-ID route installs the main app fine; the bundled widgets/notifications
  extensions may be stripped or need "include all app extensions" enabled in the tool.
- After installing, open **Settings → Swiftgram → MOD FEATURES** and set the toggles you want.

## Sync with upstream

```bash
git remote add upstream https://github.com/Swiftgram/Telegram-iOS.git
git fetch upstream --unshallow        # or: git fetch upstream
git merge upstream/master             # resolve conflicts near the MARK: Swiftgram Mod tags
```

## Requirements from Telegram / licensing

- This fork keeps upstream's licenses (GPL). If you distribute your IPA, you must offer the
  corresponding source — this repo is that source; publish it.
- Use your own api_id (that's what the secrets are for); don't share it.
- The app is unofficial. Don't call it "Telegram".
- [Telegram's API terms](https://core.telegram.org/api/terms) forbid ghost mode (hiding read
  receipts, typing or online status), interfering with sponsored messages, and keeping
  self-destructing content from disappearing. If Telegram detects a violation it can revoke the
  api_id's API access after a 10-day notice. Keep the api_id private, and turn those toggles on
  knowing that risk.

## Credits

- [Swiftgram](https://github.com/Swiftgram) — the fork this is based on
- [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) — upstream
