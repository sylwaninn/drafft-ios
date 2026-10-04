import SwiftUI

/// Under the chat's header while a session needs the person or waits on the other. A Liquid Glass capsule,
/// the material of the bar's own buttons: the sport first (its mark, its name), when, and on the right
/// what it means for the person: "Reply" when an answer is theirs, "Waiting" when it is the other's.
/// One tap opens the session's page. A confirmed session is settled and has no banner; with nothing
/// pending, the chat's session button is the one way to propose.
struct SessionBanner: View {
    let session: SessionProposal
    /// Proposed by the person: it waits on the other.
    let mine: Bool
    let onOpen: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            onOpen()
        } label: {
            HStack(spacing: DS.Space.md) {
                Image(session.sport.symbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(DS.Palette.onLime)
                    .frame(width: 44, height: 44)
                    .background(DS.Palette.lime, in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.sport.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(when)
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: DS.Space.sm)
                state
            }
            .padding(8)
            .padding(.trailing, DS.Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityElement(children: .combine)
    }

    /// The one time, or how many are offered.
    private var when: String {
        session.options.count > 1 ? L("\(session.options.count) times offered") : session.whenText
    }

    @ViewBuilder
    private var state: some View {
        if mine {
            Text("Waiting")
                .font(.footnote.weight(.bold))
                .foregroundStyle(DS.Palette.body)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(DS.Palette.ink.opacity(0.07), in: .capsule)
        } else {
            Text("Reply")
                .font(.footnote.weight(.bold))
                .foregroundStyle(DS.Palette.onLime)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(DS.Palette.lime, in: .capsule)
        }
    }
}
