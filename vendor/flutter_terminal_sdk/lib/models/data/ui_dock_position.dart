// TODO: needs behavioral review - vendor enum names kept for SDK compatibility.
// ignore_for_file: constant_identifier_names
// Enum representing UI dock positions, Dart version
/// Mirrors io.nearpay.softpos.reader_ui.UiDockPosition
/// and provides Android Gravity-compatible ints for native interop.
enum UiDockPosition {
  BOTTOM_LEFT,
  BOTTOM_CENTER,
  BOTTOM_RIGHT,
  TOP_LEFT,
  TOP_CENTER,
  TOP_RIGHT,
  ABSOLUTE_CENTER,
  CENTER_LEFT,
  CENTER_RIGHT;

  /// True if the dock is on the bottom row.
  bool get isBottom =>
      this == UiDockPosition.BOTTOM_LEFT ||
          this == UiDockPosition.BOTTOM_CENTER ||
          this == UiDockPosition.BOTTOM_RIGHT;

  // ---- Android interop ----
  // Android Gravity ints (mirroring android.view.Gravity constants)
  // LEFT=3, RIGHT=5, TOP=48, BOTTOM=80, CENTER_HORIZONTAL=1, CENTER_VERTICAL=16, CENTER=17
  int get gravityAndroid {
    switch (this) {
      case UiDockPosition.BOTTOM_LEFT:
        return 80 | 3; // BOTTOM | LEFT  = 83
      case UiDockPosition.BOTTOM_CENTER:
        return 80 | 1; // BOTTOM | CENTER_HORIZONTAL = 81
      case UiDockPosition.BOTTOM_RIGHT:
        return 80 | 5; // BOTTOM | RIGHT = 85
      case UiDockPosition.TOP_LEFT:
        return 48 | 3; // TOP | LEFT     = 51
      case UiDockPosition.TOP_CENTER:
        return 48 | 1; // TOP | CENTER_HORIZONTAL = 49
      case UiDockPosition.TOP_RIGHT:
        return 48 | 5; // TOP | RIGHT    = 53
      case UiDockPosition.ABSOLUTE_CENTER:
        return 17;     // CENTER (H|V)
      case UiDockPosition.CENTER_LEFT:
        return 16 | 3; // CENTER_VERTICAL | LEFT = 19
      case UiDockPosition.CENTER_RIGHT:
        return 16 | 5; // CENTER_VERTICAL | RIGHT = 21
    }
  }
}
