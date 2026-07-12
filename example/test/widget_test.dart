import 'package:fluid_grid_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the photo gallery with square tiles', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    // Section headers from the seed data.
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);

    // Tiles are laid out square: height equals width.
    final tile = tester.getSize(find.byType(AspectRatio).first);
    expect(tile.width, moreOrLessEquals(tile.height, epsilon: 0.5));
  });
}
