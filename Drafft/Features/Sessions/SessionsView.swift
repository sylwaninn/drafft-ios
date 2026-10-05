import SwiftUI

/// Where a push from the Sessions tab goes: a session's page, or its chat.
private enum SessionsRoute: Hashable {
    case session(UUID)
    case chat(ChatRoute)
}

/// Sessions tab: what to answer, the next confirmed session as a feature card, then everything else
/// coming up. From the server (`upcoming_sessions`, `SessionStore`), live. It follows sessions, it never
/// creates one: a session is proposed from a chat only. A row opens the session's own page.
struct SessionsView: View {
    @Environment(AppModel.self) private var app
    @State private var scrollOffset: CGFloat = 0
    /// Pages and chats open inside this tab, so Back returns to Sessions.
    @State private var path: [SessionsRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                SessionsList(matchID: nil, onOpen: { path.append(.session($0)) }, empty: {
                    EmptyStateView(art: .sessions, title: "No sessions yet.",
                                   message: "Open a chat with a match and propose a session. Confirmed ones show up here.") {
                        Button("Go to chats") { app.tab = .chats }
                            .buttonStyle(.drafftPrimaryFit)
                    }
                    // The middle of the visible page, under the header.
                    .containerRelativeFrame(.vertical) { h, _ in h * 0.8 }
                })
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.xxl)
            }
            .contentMargins(.top, DS.Space.xs, for: .scrollContent)
            .trackingScrollOffset($scrollOffset)
            // Read again whenever the tab shows (Realtime and foreground keep it current meanwhile).
            .task { await SessionStore.shared.refresh() }
            .background(DS.Palette.canvasSoft)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: SessionsRoute.self) { route in
                switch route {
                case .session(let id):
                    SessionDetailView(sessionID: id) {
                        if let match = SessionStore.shared.record(id)?.matchID {
                            path.append(.chat(ChatRoute(chatID: match.uuidString.lowercased())))
                        }
                    }
                case .chat(let r):
                    ChatView(conversationID: r.chatID).trackScreen(.chat)
                }
            }
            .topBar {
                TabHeader(offset: scrollOffset) { TabTitle(text: L("Sessions")) }
            }
        }
        .toolbarVisibility(path.isEmpty ? .visible : .hidden, for: .tabBar)
    }
}

/// Every session with one person, pushed from their chat: the same list as the tab, filtered. It only
/// lists and opens; proposing is the chat's session button.
struct PersonSessionsView: View {
    let chatID: String
    let name: String
    @State private var openSession: UUID?

    var body: some View {
        ScrollView {
            SessionsList(matchID: UUID(uuidString: chatID), onOpen: { openSession = $0 }, empty: {
                EmptyStateView(art: .sessions, title: "No sessions with \(name) yet.",
                               message: "Propose one from the chat.") { EmptyView() }
                    .containerRelativeFrame(.vertical) { h, _ in h * 0.7 }
            })
            .padding(.horizontal, DS.Space.lg)
            .padding(.bottom, DS.Space.xxl)
        }
        .background(DS.Palette.canvasSoft)
        .navigationTitle("Sessions with \(name)")
        .navigationBarTitleDisplayMode(.inline)
        .blurredNavigationEdge()
        .task { await SessionStore.shared.refresh() }
        // No "Open chat" on the page: Back returns to this list, then to the chat.
        .navigationDestination(item: $openSession) { id in
            SessionDetailView(sessionID: id)
        }
    }
}

/// The sessions, shared by the tab and a person's list: the next confirmed one as a feature card (on the
/// tab), then one list. One container, no category cards: what needs an answer comes first, then by date,
/// and each row says what it is (the sport, first), with whom, and when.
struct SessionsList<Empty: View>: View {
    /// Only this match's sessions (a person's list), or all of them (the tab).
    let matchID: UUID?
    let onOpen: (UUID) -> Void
    @ViewBuilder var empty: Empty

    @Environment(AppModel.self) private var app

    /// One upcoming session, with who it's with and whose turn it is.
    private struct Item {
        let session: SessionProposal
        let name: String
        let photo: String
        let mine: Bool
        /// News: an answer is expected or the other person changed it since it was last opened.
        let news: Bool
    }

    private var items: [Item] {
        let store = SessionStore.shared
        return store.upcoming.compactMap { row in
            guard matchID == nil || row.matchID == matchID, let session = SessionProposal(row) else { return nil }
            let profile = app.conversation(row.matchID.uuidString.lowercased())?.profile
            return Item(session: session, name: row.partner?.name ?? profile?.name ?? "",
                        photo: row.partner?.photo ?? profile?.portrait ?? "", mine: store.isMine(row),
                        news: store.needsAttention(row))
        }
    }

    /// The next confirmed session, as the feature card (the tab only).
    private var featured: Item? { matchID == nil ? items.first { $0.session.status == .accepted } : nil }

    /// Everything else: an answer to give first, then by date.
    private var listed: [Item] {
        items.filter { $0.session.id != featured?.session.id }
            .sorted { a, b in
                let (turnA, turnB) = (a.session.status == .pending && !a.mine, b.session.status == .pending && !b.mine)
                return turnA == turnB ? a.session.date < b.session.date : turnA
            }
    }

    var body: some View {
        VStack(spacing: DS.Space.md) {
            if items.isEmpty {
                empty
            } else {
                if let featured { nextUp(featured) }
                if !listed.isEmpty { list }
            }
        }
    }

    // MARK: Next up

    private func nextUp(_ item: Item) -> some View {
        let s = item.session
        return VStack(alignment: .leading, spacing: DS.Space.lg) {
            // How far off it is on the left, where it stands on the right: confirmed, in the sports' green.
            HStack(alignment: .center, spacing: DS.Space.sm) {
                if let soon = s.date.sessionCountdown {
                    Text(soon)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(.white.opacity(0.12), in: .capsule)
                }
                Spacer(minLength: DS.Space.sm)
                HStack(spacing: 5) {
                    Image("check")
                        .font(.system(size: 11, weight: .heavy))
                    Text("Confirmed")
                        .font(.footnote.weight(.bold))
                }
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(DS.Palette.onLike)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(DS.Palette.like, in: .capsule)
            }

            // The moment: the day as the title, the hour under it.
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text(s.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.app)).sentenceCased)
                    .font(.display(32, relativeTo: .largeTitle))
                    .displayLeading(32)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(s.timeText)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }

            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)

            // The sport and the person are one sentence, at one level: "[ski] Ski with [photo] Dylan".
            HStack(spacing: DS.Space.sm) {
                Image(s.sport.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.Palette.night)
                    .frame(width: 32, height: 32)
                    .background(.white, in: .circle)
                    .accessibilityHidden(true)
                Text(s.sport.name)
                Text("with").foregroundStyle(.white.opacity(0.7))
                Avatar(name: item.photo, size: 32)
                Text(item.name)
                Spacer(minLength: 0)
            }
            .font(.headline)
            .foregroundStyle(.white)

            Button { onOpen(s.id) } label: { Text("Open session") }
                .buttonStyle(.drafftPrimary)
        }
        .padding(DS.Space.xl - 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightBlock(radius: DS.Radius.xl + 4)
        .accessibilityElement(children: .contain)
    }

    // MARK: List

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(listed.enumerated()), id: \.element.session.id) { index, item in
                if index > 0 { Rectangle().fill(DS.Palette.hairline).frame(height: 1).padding(.leading, 64) }
                row(item)
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .frame(maxWidth: .infinity)
        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
    }

    /// One session: its sport as the mark and the title, with whom under it; on the right the state at the
    /// top, then when. Nothing shares a line with the person's name, so it never breaks.
    private func row(_ item: Item) -> some View {
        let s = item.session
        return Button { onOpen(s.id) } label: {
            HStack(spacing: DS.Space.md) {
                Image(s.sport.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: 52, height: 52)
                    .background(DS.Palette.canvasSoft, in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.sport.name)
                        .font(.headline)
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text("with").fixedSize()
                        Avatar(name: item.photo, size: 20)
                        Text(item.name).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.body)
                }
                Spacer(minLength: DS.Space.sm)
                VStack(alignment: .trailing, spacing: 6) {
                    stateChip(item)
                    when(s)
                }
                // News the person hasn't looked at (the other person confirmed it): a red dot, inside the row.
                if item.news && s.status == .accepted {
                    Circle().fill(DS.Palette.negative).frame(width: 10, height: 10)
                        .accessibilityLabel("New")
                }
            }
            .padding(.vertical, DS.Space.md)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// "Reply" when the answer is the person's, "Waiting" when it is the other's; nothing once confirmed.
    @ViewBuilder
    private func stateChip(_ item: Item) -> some View {
        if item.session.status == .pending {
            Text(item.mine ? "Waiting" : "Reply")
                .font(.caption.weight(.heavy))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(item.mine ? DS.Palette.body : DS.Palette.onLime)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(item.mine ? AnyShapeStyle(DS.Palette.canvasSoft) : AnyShapeStyle(DS.Palette.lime), in: .capsule)
        }
    }

    /// The day over the hour, or how many times are offered over the first day.
    private func when(_ s: SessionProposal) -> some View {
        let multiple = s.status == .pending && s.options.count > 1
        let day = s.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(.app))
        return VStack(alignment: .trailing, spacing: 1) {
            Text(multiple ? L("From \(day)") : day)
                .font(.footnote)
                .foregroundStyle(DS.Palette.body)
            Text(multiple ? L("\(s.options.count) times") : s.timeText)
                .font(.headline.monospacedDigit())
                .foregroundStyle(DS.Palette.ink)
        }
        .lineLimit(1)
        .fixedSize()
    }
}
