import 'package:flutter_test/flutter_test.dart';
import 'package:nauvim_flutter/nauvim.dart';

const zero = DisplayLength(value: 0, unit: DisplayLengthUnit.px);
const noMargins = DisplayMargins(
  top: zero,
  bottom: zero,
  left: zero,
  right: zero,
);
DisplayLength px(double value) =>
    DisplayLength(value: value, unit: DisplayLengthUnit.px);
DisplayLength em(double value) =>
    DisplayLength(value: value, unit: DisplayLengthUnit.em);

void main() {
  test(
    'resolves mixed lengths using horizontal and vertical cell dimensions',
    () {
      final options = DisplayWindowOptions(
        width: em(100),
        height: em(40),
        margin: DisplayMargins(
          top: em(0.5),
          bottom: em(1),
          left: px(8),
          right: em(0.5),
        ),
        decorations: DisplayDecorations.none,
        opacity: 0.8,
        startupMode: DisplayStartupMode.maximized,
      );
      expect(windowUsesCells(options), isTrue);
      final resolved = WindowOptions.resolve(
        options,
        cellWidth: 9.25,
        cellHeight: 18.5,
      );
      expect((resolved.width, resolved.height), (925, 740));
      expect(
        (
          resolved.margin.top,
          resolved.margin.bottom,
          resolved.margin.left,
          resolved.margin.right,
        ),
        (9, 19, 8, 5),
      );
      expect(
        (resolved.decorations, resolved.opacity, resolved.startupMode),
        (DisplayDecorations.none, 0.8, DisplayStartupMode.maximized),
      );
    },
  );

  test('preserves pixel values and omitted axes without measured cells', () {
    final options = DisplayWindowOptions(
      width: px(1920),
      margin: DisplayMargins(
        top: px(0),
        bottom: px(1),
        left: px(8),
        right: px(4294967295),
      ),
    );
    expect(windowUsesCells(options), isFalse);
    final resolved = WindowOptions.resolve(options);
    expect((resolved.width, resolved.height), (1920, null));
    expect(
      (
        resolved.margin.top,
        resolved.margin.bottom,
        resolved.margin.left,
        resolved.margin.right,
      ),
      (0, 1, 8, 4294967295),
    );
  });

  test('rounds half pixels up and preserves positive dimensions', () {
    final options = DisplayWindowOptions(
      width: em(0.01),
      height: em(1.25),
      margin: DisplayMargins(
        top: em(0.25),
        bottom: em(0.5),
        left: em(0),
        right: em(0.5),
      ),
    );
    final resolved = WindowOptions.resolve(
      options,
      cellWidth: 1,
      cellHeight: 2,
    );
    expect((resolved.width, resolved.height), (1, 3));
    expect(
      (
        resolved.margin.top,
        resolved.margin.bottom,
        resolved.margin.left,
        resolved.margin.right,
      ),
      (1, 1, 0, 1),
    );
  });

  test('caps oversized products without overflowing geometry', () {
    final options = DisplayWindowOptions(
      width: em(1e308),
      height: em(1e-300),
      margin: DisplayMargins(
        top: em(1e308),
        bottom: zero,
        left: zero,
        right: zero,
      ),
    );
    final resolved = WindowOptions.resolve(
      options,
      cellWidth: 1e308,
      cellHeight: 10,
    );
    expect(
      (resolved.width, resolved.height, resolved.margin.top),
      (4294967295, 1, 4294967295),
    );
  });

  test('requires finite positive measured cells for relative lengths', () {
    final options = DisplayWindowOptions(width: em(1), margin: noMargins);
    expect(() => WindowOptions.resolve(options), throwsArgumentError);
    for (final cell in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => WindowOptions.resolve(options, cellWidth: cell),
        throwsArgumentError,
      );
    }
    for (final value in [-1.0, double.nan, double.infinity]) {
      expect(
        () => WindowOptions.resolve(
          DisplayWindowOptions(width: em(value), margin: noMargins),
          cellWidth: 10,
        ),
        throwsArgumentError,
      );
    }
  });
}
