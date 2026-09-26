/// How the next rising row should be laid out. Chosen by the Director, built
/// by `RiseController`.
enum RowStyle {
  /// Today's rules, unchanged: adjacent gaps for the first minute, scattered
  /// after that.
  normal,

  /// One gap, directly under the column the player is keeping open. Dropping
  /// into the well then finishes two rows at once, which reads as a plan
  /// coming together rather than as a handout.
  gift,

  /// Adjacent gaps, lined up with the player's well when they have one.
  friendly,

  /// Scattered gaps, each shifted at least two columns off the previous row's.
  tough,
}

class RowPlan {
  const RowPlan(this.style, {this.wellColumn});

  static const normal = RowPlan(RowStyle.normal);

  final RowStyle style;

  /// Where the gap(s) should go, when the style cares.
  final int? wellColumn;
}
