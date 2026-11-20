import 'dart:ui';

/// Paints a filled Powerline cap from the cell geometry, as terminal builtins do.
void paintPowerlineCap(
  Canvas canvas,
  Rect cell,
  Color color, {
  required bool left,
}) {
  // A cubic from (0, 0) to (0, h), with controls at 4w/3, reaches x=w
  // at its midpoint. Mirror it for a cap joined to the right-hand cell.
  final edge = left ? cell.right : cell.left;
  final control = edge + (left ? -1 : 1) * cell.width * 4 / 3;
  final path = Path()
    ..moveTo(edge, cell.top)
    ..cubicTo(control, cell.top, control, cell.bottom, edge, cell.bottom)
    ..close();
  canvas.drawPath(path, Paint()..color = color);
}
