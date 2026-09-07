import 'package:flutter_test/flutter_test.dart';
import 'package:gov_gis_map/app/app.dart';

void main() {
  testWidgets('App basic load test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the login page is shown.
    expect(find.text('Field Survey Login'), findsOneWidget);
  });
}
