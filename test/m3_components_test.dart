import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overmorrow/pages/settings_pages/settings_page.dart';
import 'package:overmorrow/search_screens.dart';

void main() {
  testWidgets('WeatherSearchBar is available and does not shadow Flutter SearchBar',
      (WidgetTester tester) async {
    final recommend = ValueNotifier<List<String>>([]);
    final favorites = ValueNotifier<List<String>>([]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              // Verifies Flutter SDK Material 3 SearchBar can coexist without symbol collision
              const SearchBar(
                hintText: 'Search Flutter M3',
              ),
              // Verifies custom WeatherSearchBar is accessible and renders
              WeatherSearchBar(
                recommend: recommend,
                updateLocation: () {},
                updateFav: () {},
                favorites: favorites,
                updateRec: () {},
                place: 'Hanoi',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(SearchBar), findsOneWidget);
    expect(find.byType(WeatherSearchBar), findsOneWidget);
    expect(find.text('Hanoi'), findsOneWidget);
  });

  testWidgets('MainSettingEntry renders Material InkWell state layer for ripple feedback',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MainSettingEntry(
            title: 'Appearance',
            desc: 'Customize app look and feel',
            icon: Icons.palette_outlined,
          ),
        ),
      ),
    );

    expect(find.byType(InkWell), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Customize app look and feel'), findsOneWidget);
  });
}
