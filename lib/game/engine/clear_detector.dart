import 'grid.dart';

abstract final class ClearDetector {
  static List<int> findFullRows(Grid grid) => [
    for (var r = 0; r < grid.visibleRows; r++)
      if (grid.isRowFull(r)) r,
  ];
}
