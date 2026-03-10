import 'package:fire_lens/providers/firebase_provider.dart';
import 'package:fire_lens/screens/connection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('ConnectionScreen renders correctly on first launch',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<FirebaseProvider>(
        create: (_) => FirebaseProvider(),
        child: const MaterialApp(home: ConnectionScreen()),
      ),
    );

    // App bar title is visible
    expect(find.text('FireLens — Connect to Firebase'), findsOneWidget);

    // All required config fields are present
    expect(find.text('API Key'), findsOneWidget);
    expect(find.text('Project ID'), findsOneWidget);
    expect(find.text('App ID'), findsOneWidget);
    expect(find.text('Messaging Sender ID'), findsOneWidget);
    expect(find.text('Storage Bucket'), findsOneWidget);

    // Connect button is present and enabled
    expect(find.text('Connect'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Connect'),
      ).enabled,
      isTrue,
    );
  });

  testWidgets('ConnectionScreen shows validation errors on empty submit',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<FirebaseProvider>(
        create: (_) => FirebaseProvider(),
        child: const MaterialApp(home: ConnectionScreen()),
      ),
    );

    // Tap Connect without filling anything
    await tester.tap(find.text('Connect'));
    await tester.pump();

    // Required-field errors should appear
    expect(find.text('API Key is required'), findsOneWidget);
    expect(find.text('Project ID is required'), findsOneWidget);
  });
}
