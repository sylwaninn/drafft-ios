import SwiftUI

// MARK: - Session card in the thread

/// A session in the conversation, said in order of what matters: a sentence of context (who did what), then
/// a card whose disc carries the state, then the sport and when, and a caret that says "open". Nothing to
/// answer here: the session's own page (`SessionDetailView`) is one tap away. The card sits on the side of
/// whoever proposed it.
struct SessionRefCard: View {
    let session: SessionProposal
    /// Proposed by the person (not by `name`).
    let mine: Bool
    let name: String
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
            Text(caption)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.Palette.mute)
                .multilineTextAlignment(mine ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
            // The chat decides when a touch is a tap: a long press (the reactions) or a slide (the reply)
            // just before the release never reach `onOpen` (`MessageRow`).
            Button(action: onOpen) { card }
                .buttonStyle(PressScaleStyle(scale: 0.98))
        }
        .frame(maxWidth: 320, alignment: mine ? .trailing : .leading)
        // Air above, like between groups of bubbles: the sentence belongs to its card, not to the bubble before.
        .padding(.top, DS.Space.md)
        .accessibilityElement(children: .contain)
    }

    private var card: some View {
        HStack(spacing: DS.Space.md) {
            Image(stateIcon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(discInk)
                .frame(width: 48, height: 48)
                .background(discFill, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.sport.name)
                    .font(.headline)
                    .foregroundStyle(DS.Palette.ink)
                Text(when)
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.body)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(isOver ? 0.55 : 1)
            Spacer(minLength: DS.Space.sm)
            Image("alt-arrow-right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(DS.Palette.ink)
                .frame(width: 32, height: 32)
                .background(DS.Palette.canvasSoft, in: .circle)
                .accessibilityHidden(true)
        }
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.white, in: .rect(cornerRadius: DS.Radius.xl + 2))
        .contentShape(.rect(cornerRadius: DS.Radius.xl + 2))
        .accessibilityElement(children: .combine)
        .accessibilityHint(caption)
    }

    /// The state, as the card's mark: an answer to give and a confirmed session are filled, the rest soft.
    private var stateIcon: String {
        switch session.status {
        case .pending: mine ? "hourglass" : "reply"
        case .accepted: "check"
        case .declined: "close"
        case .countered: "undo-left"
        case .cancelled: "calendar-minus"
        }
    }

    /// Confirmed is the sports' green; an answer to give is the accent; the rest sits soft.
    private var discFill: AnyShapeStyle {
        if session.status == .accepted { return AnyShapeStyle(DS.Palette.like) }
        return isActive ? AnyShapeStyle(DS.Palette.lime) : AnyShapeStyle(DS.Palette.canvasSoft)
    }

    private var discInk: Color {
        if session.status == .accepted { return DS.Palette.onLike }
        return isActive ? DS.Palette.onLime : DS.Palette.ink
    }

    private var isActive: Bool {
        switch session.status {
        case .accepted: true
        case .pending: !mine
        default: false
        }
    }

    private var isOver: Bool {
        switch session.status {
        case .declined, .countered, .cancelled: true
        case .pending, .accepted: false
        }
    }

    /// Its time, or how many times are offered.
    private var when: String {
        if session.status == .pending, session.options.count > 1 {
            return L("\(session.options.count) times offered")
        }
        return session.whenText
    }

    /// Who did what, in a sentence.
    private var caption: String {
        switch session.status {
        case .pending:
            if mine { return L("You proposed a session to \(name)") }
            return L("\(name) proposes a session")
        case .accepted:
            if mine { return L("\(name) confirmed your session") }
            return L("You confirmed \(name)'s session")
        case .declined:
            if mine { return L("\(name) declined your session") }
            return L("You declined \(name)'s session")
        case .countered:
            if mine { return L("\(name) suggested other times") }
            return L("You suggested other times to \(name)")
        case .cancelled:
            return L("Session cancelled")
        }
    }
}
