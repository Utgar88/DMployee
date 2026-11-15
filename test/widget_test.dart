import 'package:dmployee/main.dart';
import 'package:dmployee/ui/dice_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Die App startet mit dem Würfler-Bildschirm', (tester) async {
    await tester.pumpWidget(const DMployeeApp());

    expect(find.byType(DiceScreen), findsOneWidget);
    expect(find.text('Würfler'), findsOneWidget);
  });
}
