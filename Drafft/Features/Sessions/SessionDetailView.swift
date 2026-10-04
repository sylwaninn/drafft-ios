import SwiftUI

/// A session as a page of its own, reached from the Sessions tab, a person's list or the chat. The one
/// place where a session is answered, changed, called off or added to the calendar; the chat only points
/// here. It shows the session as the server has it (`SessionStore`), live.
/// A session to show in a sheet over the chat (`sheet(item:)` needs an identifiable value).
struct SessionSheet: Identifiable {
    let id: UUID
}

struct SessionDetailView: View {
    let sessionID: UUID
    /// "Open chat", for a page opened from the Sessions tab. Nil when the person came from the chat: Back
    /// already returns there, a second way would be noise.
    var openChat: (() -> Void)?
    /// Shown in a sheet over the chat (a card, the banner): it has its own Close, top right.
    var presented = false

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var selected: Date?
    @State private var confirmCancel = false
    @State private var counterTo: SessionProposal?
    @State private var showSafety = false
    /// A new invite shows "Meet safely" before itself: the page stays hidden until that sheet is gone.
    @State private var gated = false
    @State private var profileFor: Profile?

    private var store: SessionStore { .shared }
    private var record: SessionRecord? { store.record(sessionID) }
    private var session: SessionProposal? { record.flatMap(SessionProposal.init) }
    private var chatID: String? { record.map { $0.matchID.uuidString.lowercased() } }
    private var profile: Profile? { chatID.flatMap { app.conversation($0)?.profile } }
    private var name: String { record?.partner?.name ?? profile?.name ?? "" }
    private var photo: String { record?.partner?.photo ?? profile?.portrait ?? "" }
    private var mine: Bool { record.map(store.isMine) ?? false }
    private var busy: Bool { store.isBusy(sessionID) }
    /// An invite that arrived and waits on the person.
    private var waitsOnMe: Bool { session?.status == .pending && !mine && store.me != nil }

    var body: some View {
        ScrollView {
            if let session { page(session) }
        }
        .scrollIndicators(.hidden)
        .opacity(gated ? 0 : 1)
        .background(DS.Palette.canvasSoft)
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .blurredNavigationEdge()
        .toolbar {
            // Close sits on the right, like every other sheet in the app.
            if presented {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", image: .icon("close")) { dismiss() }
                }
            }
        }
        .bottomBar { if !gated { footer } }
        .trackScreen(.session)
        .task {
            store.need(sessionID)
            await store.refresh()
            checkSafetyGate()
        }
        .onChange(of: waitsOnMe, initial: true) { _, _ in checkSafetyGate() }
        // Looked at as it stands: no longer news, and whatever changes while it's on screen isn't either.
        .onAppear { store.markSeen(sessionID) }
        .onChange(of: record?.updatedAt) { _, _ in store.markSeen(sessionID) }
        .onDisappear { store.markSeen(sessionID) }
        .animation(Motion.snappy, value: session?.status)
        .drafftConfirm(isPresented: $confirmCancel, icon: "calendar-minus",
                       title: L("Cancel this session?"),
                       message: L("\(name) will be told it's off."),
                       cancelTitle: L("Keep it"),
                       actions: [ConfirmAction(title: L("Cancel session"), kind: .destructive) {
                           app.cancelSession(sessionID)
                       }])
        .sheet(item: $counterTo) { original in
            if let profile, let chatID {
                Group {
                    ProposeSessionSheet(profile: profile, me: app.publicMe, sendTitle: L("Send new times"), counterTo: original) { p in
                        app.counterSession(original.id, in: chatID, with: p)
                    }
                }
                .sheetSurface()
            }
        }
        .sheet(isPresented: $showSafety, onDismiss: {
            store.markSafetyShown(sessionID)
            gated = false
        }, content: {
            SessionSafetySheet().sheetSurface()
        })
        .sheet(item: $profileFor) { person in
            Group {
                NavigationStack { ProfileDetailView(profile: person, mode: .sheet) }
            }
            .sheetSurface()
        }
    }

    /// A new invite: "Meet safely" slides in first, once, before the person sees what is proposed.
    private func checkSafetyGate() {
        guard waitsOnMe, !store.hasShownSafety(sessionID), !showSafety else { return }
        gated = true
        showSafety = true
    }

    // MARK: Page

    /// Content straight on the page, not in a card: who and what they propose, the title, what they
    /// wrote, then one block for what the person can do.
    private func page(_ s: SessionProposal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(s)

            if s.status == .accepted, let when = s.chosen {
                confirmedDate(when)
                    .padding(.top, DS.Space.xxl)
                if !s.title.isEmpty {
                    Text(s.title)
                        .font(.display(22, relativeTo: .title3))
                        .displayLeading(22)
                        .foregroundStyle(DS.Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Space.xl)
                }
            } else if !s.title.isEmpty {
                Text(s.title)
                    .font(.display(32, relativeTo: .largeTitle))
                    .displayLeading(32)
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.xl)
            }

            if !s.note.isEmpty {
                Text(s.note)
                    .font(.title3)
                    .foregroundStyle(DS.Palette.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.lg)
            }

            block(s)
                .padding(.top, DS.Space.xl)

            if s.status == .pending || s.status == .accepted {
                Button("Cancel session") { confirmCancel = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.mute)
                    .buttonStyle(.textLink(fullWidth: true))
                    .disabled(busy)
                    .padding(.top, DS.Space.sm)
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.top, DS.Space.md)
        .padding(.bottom, 120)
        .accessibilityElement(children: .contain)
    }

    /// The sport leads, as the mark and the name; the person is a line under it ("with", their photo, their
    /// name) and opens their profile. The state sits at the top right.
    private func header(_ s: SessionProposal) -> some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Image(s.sport.symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(DS.Palette.onLime)
                .frame(width: 64, height: 64)
                .background(DS.Palette.lime, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(s.sport.name)
                    .font(.display(22, relativeTo: .title2))
                    .displayLeading(22)
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if let profile { profileFor = profile }
                } label: {
                    HStack(spacing: 6) {
                        Text("with")
                        Avatar(name: photo, size: 24)
                        Text(name)
                            .fontWeight(.semibold)
                            .foregroundStyle(DS.Palette.ink)
                    }
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.body)
                    .frame(minHeight: 32)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(profile == nil)
            }
            Spacer(minLength: DS.Space.sm)
            statusChip(s)
        }
    }

    /// Where the session stands: filled when an answer is the person's.
    private func statusChip(_ s: SessionProposal) -> some View {
        let waitingOnMe = s.status == .pending && !mine
        let confirmed = s.status == .accepted
        return Text(statusText(s))
            .font(.footnote.weight(.bold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(confirmed ? DS.Palette.onLike : (waitingOnMe ? DS.Palette.onLime : DS.Palette.body))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(chipFill(confirmed: confirmed, waitingOnMe: waitingOnMe), in: .capsule)
            .padding(.top, 4)
            .contentTransition(.opacity)
    }

    /// Confirmed is the sports' green everywhere; an answer to give is the accent; the rest sits soft.
    private func chipFill(confirmed: Bool, waitingOnMe: Bool) -> AnyShapeStyle {
        if confirmed { return AnyShapeStyle(DS.Palette.like) }
        if waitingOnMe { return AnyShapeStyle(DS.Palette.lime) }
        return AnyShapeStyle(DS.Palette.canvas)
    }

    private func statusText(_ s: SessionProposal) -> String {
        switch s.status {
        case .pending:
            if mine { return L("Waiting") }
            return L("New invite")
        case .accepted: return L("Confirmed")
        case .declined: return L("Declined")
        case .countered: return L("Other times suggested")
        case .cancelled: return L("Cancelled")
        }
    }

    /// The moment, as one block: the day, then the hour in the same size, then how far off it is.
    private func confirmedDate(_ when: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(when.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.app)).sentenceCased)
                .font(.display(32, relativeTo: .largeTitle))
                .displayLeading(32)
                .foregroundStyle(DS.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(when.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(.app)))
                .font(.display(32, relativeTo: .largeTitle))
                .displayLeading(32)
                .foregroundStyle(DS.Palette.ink)
            if let soon = when.sessionCountdown {
                Text(soon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.mute)
                    .padding(.top, DS.Space.sm)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Block

    @ViewBuilder
    private func block(_ s: SessionProposal) -> some View {
        switch s.status {
        case .pending where !mine:
            VStack(alignment: .leading, spacing: DS.Space.md) {
                if s.options.count > 1 {
                    Text("Pick the time that works for you")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(DS.Palette.mute)
                        .accessibilityAddTraits(.isHeader)
                }
                VStack(spacing: DS.Space.sm) {
                    ForEach(s.options, id: \.self) { d in
                        Button {
                            Haptics.select()
                            withAnimation(Motion.select) { selected = d }
                        } label: { timeTile(d, selectable: true) }
                        .buttonStyle(PressScaleStyle(scale: 0.98))
                        .accessibilityAddTraits(selected == d ? .isSelected : [])
                    }
                }
                // Stacked, full width: each label on one line in every language.
                VStack(spacing: DS.Space.xs) {
                    Button { counterTo = s } label: { Text("Other times") }
                        .buttonStyle(DrafftButtonStyle(kind: .secondary))
                    Button("Not this time") { app.respondToSession(s.id, accept: false) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.mute)
                        .buttonStyle(.textLink(fullWidth: true))
                }
                .disabled(busy || profile == nil)
                .padding(.top, DS.Space.xs)
            }
            .padding(DS.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
            .onAppear { if s.options.count == 1 { selected = s.options.first } }

        case .pending:
            VStack(alignment: .leading, spacing: DS.Space.md) {
                if s.options.count > 1 {
                    Text("\(s.options.count) times offered")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(DS.Palette.mute)
                        .accessibilityAddTraits(.isHeader)
                }
                VStack(spacing: DS.Space.sm) {
                    ForEach(s.options, id: \.self) { timeTile($0, selectable: false) }
                }
                Text("\(name) hasn't answered yet. They can pick one of your times or suggest others.")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))

        case .accepted:
            VStack(spacing: 0) {
                if let openChat {
                    actionRow("Open chat", icon: "chat-round-line", action: openChat)
                    Rectangle().fill(DS.Palette.hairline).frame(height: 1).padding(.leading, 52)
                }
                actionRow("Meet safely", icon: "shield-check") { showSafety = true }
            }
            .padding(.horizontal, DS.Space.lg)
            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))

        case .declined, .countered, .cancelled:
            // What was proposed stays readable, as plain rows (the agreed time when there was one).
            let dates = s.chosen.map { [$0] } ?? s.options
            VStack(alignment: .leading, spacing: DS.Space.md) {
                if dates.count > 1 {
                    Text("\(dates.count) times offered")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(DS.Palette.mute)
                        .accessibilityAddTraits(.isHeader)
                }
                VStack(spacing: DS.Space.sm) {
                    ForEach(dates, id: \.self) { timeTile($0, selectable: false) }
                }
            }
            .padding(DS.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
        }
    }

    private func actionRow(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: DS.Space.md) {
                Image(icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: 36, height: 36)
                    .background(DS.Palette.canvasSoft, in: .circle)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DS.Palette.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: DS.Space.sm)
                Image("alt-arrow-right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.Palette.mute)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 56)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// One offered time: the day on the left, the hour on the right, in the same size. Picked, it fills
    /// with the accent (selection is a fill, never a frame).
    private func timeTile(_ d: Date, selectable: Bool) -> some View {
        let on = selectable && selected == d
        return HStack(spacing: DS.Space.md) {
            VStack(alignment: .leading, spacing: 1) {
                Text(d.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.app)).sentenceCased)
                    .font(.headline)
                if let soon = d.sessionCountdown {
                    Text(soon)
                        .font(.footnote)
                        .opacity(0.65)
                }
            }
            Spacer(minLength: DS.Space.sm)
            Text(d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(.app)))
                .font(.headline.monospacedDigit())
            if selectable { CheckDisc(isOn: on, onLimeFill: true) }
        }
        .foregroundStyle(on ? DS.Palette.onLime : DS.Palette.ink)
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
        .frame(minHeight: 60)
        .background(on ? AnyShapeStyle(DS.Palette.lime) : AnyShapeStyle(DS.Palette.canvasSoft), in: .rect(cornerRadius: DS.Radius.lg))
        .contentShape(.rect(cornerRadius: DS.Radius.lg))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(d.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(.app)))
    }

    // MARK: Pinned action

    /// The one thing to do. Nothing when there is nothing to do: a page opened from the chat needs no
    /// "Open chat", Back is there.
    @ViewBuilder
    private var footer: some View {
        if let s = session, let chatID {
            Group {
                switch s.status {
                case .pending where !mine:
                    Button {
                        guard let selected else { return }
                        app.respondToSession(s.id, accept: true, pick: selected)
                    } label: {
                        // One line in every language: when the day doesn't fit, the time alone.
                        ViewThatFits(in: .horizontal) {
                            Text(selected.map(confirmTitle) ?? L("Pick a time above"))
                            Text(selected.map(confirmTimeTitle) ?? L("Pick a time above"))
                        }
                        .contentTransition(.opacity)
                    }
                    .buttonStyle(.drafftPrimary)
                    .disabled(selected == nil || busy)
                case .accepted:
                    CalendarButton(session: s, partner: name, chatID: chatID, onPage: true)
                default:
                    if let openChat {
                        Button(action: openChat) { Label("Open chat", image: "chat-round-line") }
                            .buttonStyle(.drafftPrimary)
                    }
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.bottom, DS.Space.sm)
        }
    }

    /// "Confirm Sat 12, 9:00" for the time picked.
    private func confirmTitle(_ d: Date) -> String {
        let day = d.formatted(.dateTime.weekday(.abbreviated).day().locale(.app))
        let time = d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(.app))
        return L("Confirm \(day), \(time)")
    }

    /// "Confirm 9:00": the short form, when the day doesn't fit on the button's line.
    private func confirmTimeTitle(_ d: Date) -> String {
        L("Confirm \(d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(.app)))")
    }
}

extension Date {
    /// "Today", "Tomorrow", "In 3 days": how far off a session is, within a week; nil beyond.
    var sessionCountdown: String? {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return L("Today") }
        if cal.isDateInTomorrow(self) { return L("Tomorrow") }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: self)).day ?? 0
        return (1..<7).contains(days) ? L("In \(days) days") : nil
    }
}
