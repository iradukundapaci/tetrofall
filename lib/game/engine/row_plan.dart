/// How the next rising row is laid out. Chosen by the Director, built by
/// `RiseController`.
enum RowStyle {
  /// Adjacent gaps for the first minute, scattered after that.
  normal,

  /// One gap, directly under the player's well.
  gift,

  /// Adjacent gaps, lined up with the player's well when they have one.
  friendly,

  /// Scattered gaps, each shifted at least two columns off the previous row's.
  tough,

  /// A single shaft that drifts by at most one column per row and slowly
  /// widens or pinches, instead of picking gaps fresh each row.
  meander,
}

class RowPlan {
  const RowPlan(this.style, {this.wellColumn});

  static const normal = RowPlan(RowStyle.normal);

  final RowStyle style;

  /// Where the gap(s) should go, for styles that care.
  final int? wellColumn;
}
