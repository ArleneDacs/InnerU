import 'package:flutter/material.dart';

/// Swipeable cards for a "My Coach" section with more than one assigned
/// coach. Owns its own page state so swiping doesn't rebuild (and
/// re-fetch) whatever section it's embedded in.
class CoachCarousel extends StatefulWidget {
  const CoachCarousel({
    super.key,
    required this.cards,
    required this.activeDotColor,
    required this.inactiveDotColor,
  });

  final List<Widget> cards;
  final Color activeDotColor;
  final Color inactiveDotColor;

  @override
  State<CoachCarousel> createState() => _CoachCarouselState();
}

class _CoachCarouselState extends State<CoachCarousel> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 260,
          child: PageView.builder(
            controller: PageController(viewportFraction: 0.94),
            itemCount: widget.cards.length,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            itemBuilder: (context, index) => Padding(
              padding: EdgeInsets.only(
                right: index == widget.cards.length - 1 ? 0 : 10,
              ),
              child: widget.cards[index],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.cards.length, (index) {
            final isActive = index == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: isActive ? 16 : 8,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: isActive ? widget.activeDotColor : widget.inactiveDotColor,
              ),
            );
          }),
        ),
      ],
    );
  }
}
