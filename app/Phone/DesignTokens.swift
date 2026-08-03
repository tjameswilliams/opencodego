import SwiftUI

/// Spacing tokens for the transcript and its surroundings.
///
/// The transcript has no divider lines; every boundary in it is made of
/// space, so these values *are* the structure and they belong in one place
/// rather than scattered as literals. The density ladder, tightest to
/// loosest — line < list item < block < part < turn — is inherited from
/// Tomte's reading styleguide (app/STYLEGUIDE.md) and holds here for the
/// same reason: a reader needs the gap between two thoughts to be visibly
/// larger than the gap between two lines of one thought.
///
/// Full spec: docs/design-spec.md.
enum Space {
    /// Between consecutive parts of the same turn (a tool call, then text).
    static let betweenParts: CGFloat = 14
    /// Between one speaker's turn and the next. Deliberately about double
    /// `betweenParts` — this is the only cue that a turn ended.
    static let betweenTurns: CGFloat = 28
    /// The transcript's side margin.
    static let gutter: CGFloat = 16
}
