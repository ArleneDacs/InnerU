import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/services/meditation_streak_service.dart';

class MeditationStreakRewardsScreen extends StatefulWidget {
  const MeditationStreakRewardsScreen({
    super.key,
    this.activityType = ActivityStreakType.meditation,
  });

  final ActivityStreakType activityType;

  @override
  State<MeditationStreakRewardsScreen> createState() =>
      _MeditationStreakRewardsScreenState();
}

class _MeditationStreakRewardsScreenState
    extends State<MeditationStreakRewardsScreen> {
  final PageController _pageController = PageController(viewportFraction: 0.78);
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final milestones = ActivityStreakService.milestonesFor(widget.activityType);

    return Scaffold(
      backgroundColor: const Color(0xFF080B18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080B18),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('${widget.activityType.label} Rewards'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: UserService.getUserData(),
        builder: (context, snapshot) {
          final data = snapshot.data ?? <String, dynamic>{};
          final currentField = ActivityStreakService.currentFieldFor(
            widget.activityType,
          );
          final longestField = ActivityStreakService.longestFieldFor(
            widget.activityType,
          );
          final lastDateField = ActivityStreakService.lastDateFieldFor(
            widget.activityType,
          );
          final rewardsField = ActivityStreakService.rewardsFieldFor(
            widget.activityType,
          );
          final storedCurrentStreak = ActivityStreakService.readInt(
            data[currentField] ?? data[_snakeToCamel(currentField)],
          );
          final currentStreak = ActivityStreakService.activeCurrentStreak(
            lastDate: data[lastDateField] ?? data[_snakeToCamel(lastDateField)],
            currentStreak: storedCurrentStreak,
          );
          final longestStreak = ActivityStreakService.readInt(
            data[longestField] ?? data[_snakeToCamel(longestField)],
          );
          final rewards = ActivityStreakService.readRewards(
            data[rewardsField] ?? data[_snakeToCamel(rewardsField)],
          );
          final unlockedCount = milestones
              .where((milestone) => rewards.containsKey(milestone.id))
              .length;
          final nextMilestone = _nextMilestone(
            rewards.keys.toSet(),
            milestones,
          );
          final progressTarget = nextMilestone?.days ?? milestones.last.days;
          final progress = progressTarget == 0
              ? 0.0
              : (currentStreak / progressTarget).clamp(0.0, 1.0);

          return SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                  child: _ProgressHeader(
                    unlockedCount: unlockedCount,
                    totalCount: milestones.length,
                    currentStreak: currentStreak,
                    longestStreak: longestStreak,
                    progress: progress,
                    nextMilestone: nextMilestone,
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() {
                        _page = index;
                      });
                    },
                    itemCount: milestones.length,
                    itemBuilder: (context, index) {
                      final milestone = milestones[index];
                      final unlockedAt = rewards[milestone.id];
                      final unlocked = unlockedAt != null;

                      return AnimatedScale(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutBack,
                        scale: unlocked ? 1.0 : 0.88,
                        child: _RewardPage(
                          milestone: milestone,
                          unlocked: unlocked,
                          unlockedLabel: _formatUnlockedAt(unlockedAt),
                          selected: _page == index,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                _PageDots(
                  currentIndex: _page,
                  itemCount: milestones.length,
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  ActivityStreakMilestone? _nextMilestone(
    Set<String> unlockedRewardIds,
    List<ActivityStreakMilestone> milestones,
  ) {
    for (final milestone in milestones) {
      if (!unlockedRewardIds.contains(milestone.id)) {
        return milestone;
      }
    }
    return null;
  }

  String? _formatUnlockedAt(Object? value) {
    if (value == null) return null;
    final date = DateTime.tryParse(value.toString());
    if (date == null) return value.toString();
    return DateFormat('MMM d, yyyy').format(date);
  }

  String _snakeToCamel(String value) {
    final parts = value.split('_');
    return parts.first +
        parts.skip(1).map((part) {
          if (part.isEmpty) return part;
          return part[0].toUpperCase() + part.substring(1);
        }).join();
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.unlockedCount,
    required this.totalCount,
    required this.currentStreak,
    required this.longestStreak,
    required this.progress,
    required this.nextMilestone,
  });

  final int unlockedCount;
  final int totalCount;
  final int currentStreak;
  final int longestStreak;
  final double progress;
  final ActivityStreakMilestone? nextMilestone;

  @override
  Widget build(BuildContext context) {
    final remaining = totalCount - unlockedCount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111734),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF1D2757)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 28,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$unlockedCount of $totalCount unlocked',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                remaining == 0 ? 'All earned' : '$remaining still to earn',
                style: const TextStyle(
                  color: Color(0xFFAEB7D5),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StreakStat(label: 'Current', value: '$currentStreak days'),
              const SizedBox(width: 16),
              _StreakStat(label: 'Best', value: '$longestStreak days'),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: progress,
              backgroundColor: const Color(0xFF060918),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFF7C344)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            nextMilestone == null
                ? 'Every meditation reward is unlocked.'
                : '${math.max(nextMilestone!.days - currentStreak, 0)} days until ${nextMilestone!.title}',
            style: const TextStyle(
              color: Color(0xFFAEB7D5),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakStat extends StatelessWidget {
  const _StreakStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF080C21),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFAEB7D5),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RewardPage extends StatelessWidget {
  const _RewardPage({
    required this.milestone,
    required this.unlocked,
    required this.unlockedLabel,
    required this.selected,
  });

  final ActivityStreakMilestone milestone;
  final bool unlocked;
  final String? unlockedLabel;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = _tierColor(milestone.tier);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      margin: EdgeInsets.symmetric(
        horizontal: 8,
        vertical: selected ? 14 : 30,
      ),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: unlocked ? const Color(0xFF111734) : const Color(0xFF101218),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: unlocked
              ? color.withValues(alpha: 0.55)
              : const Color(0xFF242834),
          width: unlocked ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: unlocked
                ? color.withValues(alpha: 0.18)
                : const Color(0x66000000),
            blurRadius: unlocked ? 34 : 18,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              milestone.tier.toUpperCase(),
              style: TextStyle(
                color: unlocked ? color : const Color(0xFF6D7282),
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
          const Spacer(),
          _Medal(
            color: color,
            unlocked: unlocked,
            days: milestone.days,
          ),
          const SizedBox(height: 30),
          Text(
            milestone.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: unlocked ? Colors.white : const Color(0xFF777D8D),
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            milestone.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              color:
                  unlocked ? const Color(0xFFCCD3EA) : const Color(0xFF646A78),
              fontSize: 15,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: unlocked
                  ? color.withValues(alpha: 0.12)
                  : const Color(0xFF0A0D16),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              unlocked
                  ? 'Unlocked ${unlockedLabel ?? ''}'.trim()
                  : 'Keep a ${milestone.days}-day streak',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: unlocked ? color : const Color(0xFF777D8D),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _tierColor(String tier) {
    return switch (tier) {
      'Bronze' => const Color(0xFFCE7A34),
      'Silver' => const Color(0xFFB9C8E3),
      'Gold' => const Color(0xFFF7C344),
      'Platinum' => const Color(0xFF9FE6FF),
      _ => const Color(0xFFF7C344),
    };
  }
}

class _Medal extends StatelessWidget {
  const _Medal({
    required this.color,
    required this.unlocked,
    required this.days,
  });

  final Color color;
  final bool unlocked;
  final int days;

  @override
  Widget build(BuildContext context) {
    final medalSize = unlocked ? 174.0 : 128.0;
    final ribbonWidth = unlocked ? 58.0 : 42.0;
    final ribbonHeight = unlocked ? 82.0 : 60.0;
    final totalHeight = medalSize + (unlocked ? 42.0 : 34.0);
    final mutedColor = const Color(0xFF2C3140);
    final borderColor =
        unlocked ? Colors.white.withValues(alpha: 0.55) : Colors.white12;

    return AnimatedSize(
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutBack,
      child: SizedBox(
        width: medalSize,
        height: totalHeight,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              top: 0,
              left: unlocked ? 30 : 22,
              child: Transform.rotate(
                angle: -0.16,
                child: _MedalRibbon(
                  width: ribbonWidth,
                  height: ribbonHeight,
                  color: unlocked ? color : mutedColor,
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: unlocked ? 30 : 22,
              child: Transform.rotate(
                angle: 0.16,
                child: _MedalRibbon(
                  width: ribbonWidth,
                  height: ribbonHeight,
                  color: unlocked ? color : mutedColor,
                ),
              ),
            ),
            ClipPath(
              clipper: const _MedalBodyClipper(),
              child: Container(
                width: medalSize,
                height: medalSize,
                padding: EdgeInsets.all(unlocked ? 5 : 3),
                decoration: BoxDecoration(color: borderColor),
                child: ClipPath(
                  clipper: const _MedalBodyClipper(),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: unlocked
                          ? RadialGradient(
                              colors: [
                                color.withValues(alpha: 0.95),
                                color.withValues(alpha: 0.72),
                                const Color(0xFF111734),
                              ],
                            )
                          : const RadialGradient(
                              colors: [
                                Color(0xFF252A36),
                                Color(0xFF151923),
                                Color(0xFF0B0E16),
                              ],
                            ),
                      boxShadow: [
                        BoxShadow(
                          color: unlocked
                              ? color.withValues(alpha: 0.34)
                              : Colors.transparent,
                          blurRadius: 36,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned(
                          top: unlocked ? 20 : 16,
                          child: Icon(
                            unlocked ? Icons.star_rounded : Icons.lock_rounded,
                            color: unlocked
                                ? Colors.white
                                : const Color(0xFF6D7282),
                            size: unlocked ? 38 : 30,
                          ),
                        ),
                        Text(
                          '$days',
                          style: TextStyle(
                            color: unlocked
                                ? Colors.white
                                : const Color(0xFF6D7282),
                            fontSize: unlocked ? 52 : 38,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Positioned(
                          bottom: unlocked ? 30 : 22,
                          child: Text(
                            'DAYS',
                            style: TextStyle(
                              color: unlocked
                                  ? Colors.white
                                  : const Color(0xFF6D7282),
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MedalRibbon extends StatelessWidget {
  const _MedalRibbon({
    required this.width,
    required this.height,
    required this.color,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const _MedalRibbonClipper(),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.95),
              Color.alphaBlend(Colors.black.withValues(alpha: 0.36), color),
            ],
          ),
        ),
      ),
    );
  }
}

class _MedalBodyClipper extends CustomClipper<Path> {
  const _MedalBodyClipper();

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width * 0.5, 0)
      ..lineTo(size.width * 0.73, size.height * 0.08)
      ..lineTo(size.width * 0.92, size.height * 0.28)
      ..lineTo(size.width, size.height * 0.56)
      ..lineTo(size.width * 0.84, size.height * 0.86)
      ..lineTo(size.width * 0.5, size.height)
      ..lineTo(size.width * 0.16, size.height * 0.86)
      ..lineTo(0, size.height * 0.56)
      ..lineTo(size.width * 0.08, size.height * 0.28)
      ..lineTo(size.width * 0.27, size.height * 0.08)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _MedalRibbonClipper extends CustomClipper<Path> {
  const _MedalRibbonClipper();

  @override
  Path getClip(Size size) {
    return Path()
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width * 0.5, size.height * 0.76)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.currentIndex, required this.itemCount});

  final int currentIndex;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(itemCount, (index) {
        final active = currentIndex == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: active ? 22 : 7,
          height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFF7C344) : const Color(0xFF343A52),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}
