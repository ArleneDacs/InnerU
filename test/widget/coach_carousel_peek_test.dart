import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coaches/coach_carousel.dart';

void main() {
  // The real coach cards (_buildGlassSectionCard in dashboard_screen.dart)
  // are drawn with a 30dp corner radius. If the carousel's "peek" of the
  // next card is narrower than that radius, only the curved corner is ever
  // visible - it renders as a floating, disconnected blob instead of a
  // recognizable card edge. This locks in a minimum peek width comfortably
  // above that radius.
  const cardCornerRadius = 30.0;
  const narrowPhoneWidth = 335.0; // content width on a small phone

  testWidgets(
    'peeking next card is wider than the card corner radius',
    (tester) async {
      const card0Key = Key('card0');
      const card1Key = Key('card1');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: narrowPhoneWidth,
                child: CoachCarousel(
                  activeDotColor: Colors.black,
                  inactiveDotColor: Colors.grey,
                  cards: const [
                    ColoredBox(key: card0Key, color: Colors.blue),
                    ColoredBox(key: card1Key, color: Colors.green),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final carouselRect = tester.getRect(find.byType(CoachCarousel));
      final card0Rect = tester.getRect(find.byKey(card0Key));
      final card1Rect = tester.getRect(find.byKey(card1Key));
      final viewportWidth = carouselRect.width;
      final card0Left = card0Rect.left - carouselRect.left;
      final card1Left = card1Rect.left - carouselRect.left;
      final peekWidth = viewportWidth - card1Left;

      expect(
        card0Left,
        lessThan(1.0),
        reason: 'The first card should sit flush with the left edge, '
            'matching every other section on the dashboard, not be inset '
            'by the carousel\'s own leading peek space.',
      );
      expect(
        peekWidth,
        greaterThan(cardCornerRadius + 10),
        reason: 'Peek of the next card ($peekWidth logical px) must clear '
            'the card corner radius ($cardCornerRadius) with margin, or the '
            'sliver only ever shows the curve, never a real edge.',
      );
    },
  );
}
