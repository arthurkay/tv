import 'package:flutter_test/flutter_test.dart';
import 'package:vieo_tv/main.dart';

void main() {
  testWidgets('App loads the channel list', (WidgetTester tester) async {
    await tester.pumpWidget(const VieoApp());

    // The playlist is parsed asynchronously, so the first frame is the spinner.
    await tester.pumpAndSettle();

    expect(find.text('Vieo TV'), findsOneWidget);
  });
}
