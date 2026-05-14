with open("lib/src/features/authentication/screen/dashboard/dashboard_screen.dart", "r") as f:
    content = f.read()

old = """Expanded(
              child: _buildMiniOverviewCard(
                icon: CupertinoIcons.heart_solid,
                title: "Mood",
                value: currentUserEmotion == null ? "Check in" : currentUserEmotion!,
                accent: const Color(0xFFE8DCC9),
              ),
            ),"""

new = """Expanded(
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EmotionTrackerPage(),
                    ),
                  );
                },
                child: _buildMiniOverviewCard(
                  icon: CupertinoIcons.heart_solid,
                  title: "Mood",
                  value: currentUserEmotion == null ? "Check in" : currentUserEmotion!,
                  accent: const Color(0xFFE8DCC9),
                ),
              ),
            ),"""

content = content.replace(old, new)
with open("lib/src/features/authentication/screen/dashboard/dashboard_screen.dart", "w") as f:
    f.write(content)
print("Done")
