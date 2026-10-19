# Relay native interface

Relay has one shared multiplatform target. macOS uses AppKit; iPhone and iPad
use UIKit. There are no SwiftUI screens, hosting controllers, view wrappers,
or parallel legacy interfaces.

## Ownership

- `Application/AppContext` owns account state, the chat store, composer, push,
  and audio services for the application lifetime.
- `Application/AppDelegate` owns the macOS window. On iOS, `SceneDelegate`
  owns the window and a native adaptive split-view controller.
- `NativeSceneMigration` adopts restored windows from previous SwiftUI builds.
  This preserves the existing account, encryption keys, and database.
- `Interface/macOS` and `Interface/iOS` contain platform controllers and views.
  `Interface/Shared` contains presentation values and common actions.
- `ObservationLifetime` updates native controllers from `@Observable` models.
  Updates are coalesced on the main actor; there is no polling loop.
- `Features/SignIn` and `Features/Settings` hold shared feature logic. Their
  presentation uses native platform controls.

## Messages and history

The embedded Matrix engine owns encryption, sync, and the only persistent
message database. Swift keeps the open timeline and transient pending sends
in memory. Other rooms are read from Matrix's database when opened. Display
rows are transient projections, not another message database.

Conversation lists page downward. Message timelines page upward. Scrolling
near the relevant edge reads the next SQLite page, with overlapping loads
prevented and the visible message anchored across prepends. Loading stops
when the local database has no further records. Neither scrolling nor opening
an empty room requests remote history. Matrix sync continues ingesting new
messages, and its event channel updates the UI. Reconnecting also reloads
local state to close any subscription gap.

Pending messages remain separate until the Matrix echo is reconciled, so sends
appear immediately, show upload progress/failure, and can be retried. Drafts
and attachment intake belong to their originating chat, including when a photo
picker finishes after navigation.

## Platform behavior

The original interface remains the visual reference: the unified macOS toolbar,
340-point sidebar, compact conversation rows, sender grouping, message bubbles,
reply and reaction overlays, and glass composer retain their existing layout.
Settings uses native controls with its own platform layout.

AppKit uses `NSSplitViewController`, `NSTableView`, `NSTextView`, native menus,
open/save panels, AVKit, and Quick Look. Return sends, Shift-Return inserts a
line, Up in an empty composer edits the latest editable message, Escape cancels
a reply/edit, and Command-F focuses chat search.

UIKit uses `UISplitViewController`, diffable table views, a bottom integrated
`UISearchController` composer on iPhone, a glass `UITextView` composer on iPad, the
keyboard layout guide, message context menus, conversation swipe actions, photo/document pickers, AVKit,
Quick Look, and the system share sheet. The split view adapts to compact and
regular widths. Return sends; Shift-Return adds a line with a hardware keyboard.

Image thumbnails use a bounded memory cache and downsampling. Animated GIFs
retain inline playback, with decoded frame memory bounded on iOS. Matrix owns
asset decryption. The existing OGG converter is retained for voice messages;
SwiftMediaViewer is removed. Push enrollment and the notification extension
remain shared with the existing Matrix integration.

## Validation

Use the shared Relay scheme to build for macOS, iOS Simulator, and iOS devices.
Validate interactions in Relay itself. Do not add test targets, probe apps,
or another project specification. Never commit or push without specific user
authorization.
