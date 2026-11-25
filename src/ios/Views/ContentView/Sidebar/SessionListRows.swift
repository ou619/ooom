import SwiftUI
// [T-session-avatar] PhotosPicker / PhotosPickerItem live here.
import PhotosUI

// MARK: - [T-home-list-lazy-rows] One concrete row per session id

// Why these are named structs and not inline row builders:
//
// A List only builds the rows on screen if it can count rows WITHOUT running
// their content - which it can when every ForEach element is statically one
// view. The home list's elements were `if let session = sessionForRow(id) { … }`
// (zero or one view) and, on iPhone, an `AnyView` (any number of views), so
// every ContentView body pass ran all ~4,700 row closures to count them. Field
// log 2026-10-03 22:08-22:23 (1.15, 4,722 sessions): "one pass resolved 4707 of
// 4707 rows" on every pass, and a 240-420 ms [MainStall] on 24 of 29 pushes into
// a chat and on returning home - the hitch the user saw on every back swipe.
//
// Each struct is exactly one view of a fixed type, so the ForEach row count is
// `ids.count` and only visible rows are built. The struct is also the type
// boundary that f8012dfa4 needed: the parent's type names only the struct, and
// the 8-modifier chain lives in the struct's own body type, so stackList's
// metadata stays shallow without the AnyView that made rows uncountable.
//
// All inputs are values (no closures capturing ContentView - see
// [T-ios-crash-contextmenu-uaf]); the menu goes through the same
// SessionMenuActionChannel as before.

/// iPhone (compact, `stackList`) row: a tap opens the session through
/// `SessionMenuActionChannel` (`.open`), which replaces the navigation path.
///
/// [T-nav-ghost-row-link] This used to be a hidden `NavigationLink(value:)` in
/// the row's background. After a session had been opened from its row and the
/// user swiped back, the next PROGRAMMATIC push (a new chat from the FAB or a
/// folder card) brought that session back underneath the new chat, so Back had
/// to be pressed twice. The mechanism - the List's value link being re-applied
/// to the path - is inferred from the log below (nothing in the app writes that
/// element; no deferred navigation was pending), not reproduced in isolation. Field log
/// 2026-10-04 12:31-12:33: FD704863 entered from its row (no openSession line),
/// swiped back (nav depth=0), then a new chat logged `nav depth=2` with
/// FD704863's view rebuilt under the draft; new chats whose previous entry was a
/// programmatic push stayed at depth 1. With no value links in the list, every
/// push from the home list goes through the app's own path writes.
struct SessionStackRow: View {
    let session: ChatSession
    let isActive: Bool
    let isSuspended: Bool
    let highlightQuery: String?
    let matchSnippet: String?
    let isRegeneratingTitle: Bool
    let inFolder: Bool
    let isLastInFolder: Bool
    let menuActions: SessionMenuActionChannel

    // [T-session-avatar] Row-local avatar plumbing. NOT `private`: a private
    // stored property would make the synthesized memberwise init private and
    // ContentView could no longer build this row. All four have defaults, so
    // existing call sites are unaffected.
    //
    /// Presents the photo picker. Set from the context menu one run loop later.
    @State var showAvatarPicker = false
    /// The pending pick; `nil` while idle (reset after every attempt).
    @State var avatarItem: PhotosPickerItem?
    /// What this row just wrote, so the new avatar shows before the store's
    /// throttled session-list refresh replaces `session`.
    @State var avatarOverride: String?
    /// Bumped to ask `SessionAvatarPicker` to restore the default icon.
    @State var avatarRestoreTick = 0

    var body: some View {
        let _ = HomeListPerf.rowBuilt()
        Button { [menuActions, sid = session.id] in
            menuActions.send(.open(sid))
        } label: {
            SessionRow(
                session: session,
                // [T-ios-ipad-sidebar-running-indicator-stale] Running / suspended as
                // VALUES so a flip re-evaluates this row in place.
                isActive: isActive,
                isSuspended: isSuspended,
                highlightQuery: highlightQuery,
                matchSnippet: matchSnippet,
                // [T-session-avatar] Row-local value wins until the refresh lands.
                avatarRefOverride: avatarOverride
            )
            // [T-ios-session-list-equatable-jank] Gate parent-driven re-eval on
            // SessionRow's cheap custom ==.
            .equatable()
        }
        .buttonStyle(SessionRowPressStyle())
        // Entry D: long-press then move drags the session id; the system
        // arbitrates against .contextMenu on the same press.
        .draggable(session.id)
        .overlay {
            if isRegeneratingTitle {
                ZStack {
                    Color(.systemBackground).opacity(0.7)
                    ProgressView()
                }
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Group {
            if inFolder {
                FolderMemberRowBackground(isLast: isLastInFolder)
            } else {
                Color(.systemBackground)
            }
        })
        .contextMenu {
            // [T-ios-crash-contextmenu-uaf] Value-only menu view, no closure captures.
            SessionContextMenu(
                key: MenuKey(sid: session.id, pinned: session.isPinned, title: session.title, filed: session.isFiled),
                actions: menuActions
            )
            .equatable()
            // [T-session-avatar] Plain value-only buttons rather than extending
            // SessionContextMenu: that view is shared and Equatable by key, and
            // knows nothing about avatars. These capture only this row's own
            // state and the session id — never ContentView, per
            // [T-ios-crash-contextmenu-uaf].
            Button {
                // One run loop later: presenting a sheet synchronously from a
                // context-menu action races the menu's own dismissal.
                DispatchQueue.main.async { showAvatarPicker = true }
            } label: {
                Label(AppLocalized("更换会话头像"), systemImage: "person.crop.circle")
            }
            // Only offered when there is something to restore.
            if let currentRef = avatarOverride ?? session.avatarRef, !currentRef.isEmpty {
                Button {
                    avatarRestoreTick += 1
                } label: {
                    Label(AppLocalized("恢复默认头像"), systemImage: "arrow.uturn.backward")
                }
            }
        }
        .modifier(SessionAvatarPicker(
            sessionId: session.id,
            isPresented: $showAvatarPicker,
            item: $avatarItem,
            overrideRef: $avatarOverride,
            restoreTick: $avatarRestoreTick
        ))
    }
}

/// iPad / Mac (`splitList`) row: selected through `List(selection:)` + `.tag`.
struct SessionSplitRow: View {
    let session: ChatSession
    let isHighlighted: Bool
    let isActive: Bool
    let isSuspended: Bool
    let highlightQuery: String?
    let matchSnippet: String?
    let isRegeneratingTitle: Bool
    /// The id the context menu acts on: the real id for a persisted draft row,
    /// nil for a never-sent draft (no menu). See [T-ios-ipad-new-session-contextmenu-broken].
    let menuSid: String?
    let inFolder: Bool
    let isLastInFolder: Bool
    let menuActions: SessionMenuActionChannel

    // [T-session-avatar] Same four row-local values as the phone row (see the
    // note there: they must not be `private` or the memberwise init disappears).
    @State var showAvatarPicker = false
    @State var avatarItem: PhotosPickerItem?
    @State var avatarOverride: String?
    @State var avatarRestoreTick = 0

    private static let highlightFill = Color(red: 183/255.0, green: 175/255.0, blue: 150/255.0).opacity(0.3)

    var body: some View {
        let _ = HomeListPerf.rowBuilt()
        SessionRow(
            session: session,
            isHighlighted: isHighlighted,
            isActive: isActive,
            isSuspended: isSuspended,
            highlightQuery: highlightQuery,
            matchSnippet: matchSnippet,
            // [T-session-avatar] Row-local value wins until the refresh lands.
            avatarRefOverride: avatarOverride
        )
        .equatable()
        .draggable(session.id)
        .overlay {
            if isRegeneratingTitle {
                ZStack {
                    Color(.systemBackground).opacity(0.7)
                    ProgressView()
                }
            }
        }
        // [T-ios-selected-session-contextmenu] On the row CONTENT, below the
        // selection layer, so it fires on the selected row too (GH#30).
        .contextMenu {
            if let menuSid {
                SessionContextMenu(
                    key: MenuKey(sid: menuSid, pinned: session.isPinned, title: session.title, filed: session.isFiled),
                    actions: menuActions
                )
                .equatable()
                // [T-session-avatar] Same two value-only items as the phone row.
                Button {
                    DispatchQueue.main.async { showAvatarPicker = true }
                } label: {
                    Label(AppLocalized("更换会话头像"), systemImage: "person.crop.circle")
                }
                if let currentRef = avatarOverride ?? session.avatarRef, !currentRef.isEmpty {
                    Button {
                        avatarRestoreTick += 1
                    } label: {
                        Label(AppLocalized("恢复默认头像"), systemImage: "arrow.uturn.backward")
                    }
                }
            }
        }
        .modifier(SessionAvatarPicker(
            sessionId: menuSid ?? session.id,
            isPresented: $showAvatarPicker,
            item: $avatarItem,
            overrideRef: $avatarOverride,
            restoreTick: $avatarRestoreTick
        ))
        .tag(session.id)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(
            ZStack {
                if inFolder {
                    FolderMemberRowBackground(isLast: isLastInFolder)
                    // Flush selection band inside the group; the last member's
                    // band takes the container's bottom radii.
                    if isHighlighted {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: isLastInFolder ? 16 : 0,
                            bottomTrailingRadius: isLastInFolder ? 16 : 0,
                            topTrailingRadius: 0,
                            style: .continuous
                        )
                        .fill(Self.highlightFill)
                        .padding(.horizontal, 6)
                        .padding(.bottom, isLastInFolder ? 4 : 0)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isHighlighted ? Self.highlightFill : Color.clear)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                }
            }
        )
    }
}

extension ChatSession {
    /// Stand-in for a row id that resolves to no session. Group ids come from
    /// `sessions` (plus the iPad draft, which sessionForRow resolves), so this
    /// should never render; it exists so a row is always exactly one view.
    /// HomeListPerf counts these as `nil` lookups.
    static func missingRowPlaceholder(_ id: String) -> ChatSession {
        ChatSession(id: id, title: nil, category: nil, modelId: "",
                    createdAt: .distantPast, updatedAt: .distantPast, lastMessage: nil)
    }
}

/// [T-nav-ghost-row-link] Press feedback for SessionStackRow's Button: the whole
/// row is the hit area and dims while pressed, standing in for the cell
/// highlight the hidden NavigationLink used to get. A custom style also keeps
/// List from tinting the row's text with the accent colour.
struct SessionRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .overlay(Color(.systemFill).opacity(configuration.isPressed ? 1 : 0).allowsHitTesting(false))
    }
}

// MARK: - [T-session-avatar] Photo picker + apply / restore

/// Photo-picker plumbing for one session row.
///
/// A modifier so neither row grows its own presentation chain and the phone and
/// iPad rows behave identically. It owns the transient pick and the failure
/// alert; the row keeps only what the row RENDERS (the resulting reference).
struct SessionAvatarPicker: ViewModifier {
    /// The session the avatar belongs to.
    let sessionId: String
    @Binding var isPresented: Bool
    @Binding var item: PhotosPickerItem?
    /// What the row should render from now on (`""` = restored default).
    @Binding var overrideRef: String?
    /// Incremented by the "restore default" menu item.
    @Binding var restoreTick: Int

    @State private var errorShown = false

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $isPresented,
                selection: $item,
                matching: .images,
                photoLibrary: .shared()
            )
            .onChange(of: item) { _, newItem in
                guard let newItem else { return }
                Task { await apply(newItem) }
            }
            .onChange(of: restoreTick) { _, _ in
                Task { await restoreDefault() }
            }
            .alert(AppLocalized("这张图片无法使用"), isPresented: $errorShown) {
                Button(AppLocalized("好"), role: .cancel) { errorShown = false }
            } message: {
                Text(AppLocalized("读取这张图片失败，请换一张再试。"))
            }
    }

    /// Decode → normalise → write → record the reference.
    ///
    /// Re-encoding through `SoulIconImage` (1:1 centre crop, ≤96px, PNG) makes a
    /// session avatar the same kind of asset as a Soul avatar, and keeps what
    /// the DB stores down to a file NAME.
    @MainActor
    private func apply(_ picked: PhotosPickerItem) async {
        // Clear the pick either way, or re-picking the same photo is a no-op.
        defer { item = nil }
        guard let data = try? await picked.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            errorShown = true
            return
        }
        guard case .success(let dataURI) = SoulIconImage.encode(image),
              let png = SoulIconImage.pngData(from: dataURI) else {
            errorShown = true
            return
        }
        guard let name = try? SessionAvatarFiles.write(png, for: sessionId) else {
            errorShown = true
            return
        }
        await ChatStore.shared.updateSessionAvatar(sessionId, ref: name)
        SessionAvatarCache.shared.invalidate(sessionId: sessionId)
        // Row-local value: the sidebar only re-reads this row on its next
        // (throttled) refresh, so without this the old icon stays visible.
        overrideRef = name
    }

    /// 「恢复默认头像」: drop the bytes, then write the `''` sentinel.
    ///
    /// `''` instead of NULL on purpose — it records that the user CHOSE the
    /// default, which stays distinguishable from a row that never had an
    /// avatar. `updated_at` is untouched, so the row does not jump in the list.
    @MainActor
    private func restoreDefault() async {
        SessionAvatarFiles.removeAll(for: sessionId)
        await ChatStore.shared.updateSessionAvatar(sessionId, ref: "")
        SessionAvatarCache.shared.invalidate(sessionId: sessionId)
        overrideRef = ""
    }
}
