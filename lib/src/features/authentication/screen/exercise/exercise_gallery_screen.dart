import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/authentication/screen/exercise/exercise_duration_utils.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/exercise_api_service.dart';
import 'package:selfcare_projects/src/services/image_storage_service.dart';

typedef ExerciseGalleryPageLoader = Future<ExerciseHistoryPage> Function({
  required int page,
  required int perPage,
});

/// A date-organized, lazy gallery of the current user's exercise photos.
///
/// The loader is injectable for focused widget tests. Production callers use
/// the paged API so opening the gallery never requests the full photo history.
class ExerciseGalleryScreen extends StatefulWidget {
  const ExerciseGalleryScreen({
    super.key,
    this.pageLoader,
  });

  final ExerciseGalleryPageLoader? pageLoader;

  @override
  State<ExerciseGalleryScreen> createState() => _ExerciseGalleryScreenState();
}

class _ExerciseGalleryScreenState extends State<ExerciseGalleryScreen> {
  static const int _pageSize = 18;

  final ExerciseApiService _exerciseApi = ExerciseApiService.instance;
  final ScrollController _scrollController = ScrollController();

  List<ExerciseHistoryLog> _logs = const <ExerciseHistoryLog>[];
  int _nextPage = 1;
  bool _hasMore = true;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  Object? _initialError;
  Object? _moreError;
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  Future<ExerciseHistoryPage> _loadPage(int page) {
    final loader = widget.pageLoader;
    if (loader != null) {
      return loader(page: page, perPage: _pageSize);
    }
    return _exerciseApi.fetchGalleryHistory(page: page, perPage: _pageSize);
  }

  Future<void> _loadInitial() async {
    final requestVersion = ++_requestVersion;
    setState(() {
      _isLoadingInitial = true;
      _isLoadingMore = false;
      _initialError = null;
      _moreError = null;
      _logs = const <ExerciseHistoryLog>[];
      _nextPage = 1;
      _hasMore = true;
    });

    try {
      final page = await _loadPage(1);
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _logs = page.logs;
        _nextPage = page.page + 1;
        _hasMore = page.hasMore;
        _isLoadingInitial = false;
      });
    } catch (error) {
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _initialError = error;
        _isLoadingInitial = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingInitial || _isLoadingMore || !_hasMore) return;

    final requestVersion = _requestVersion;

    setState(() {
      _isLoadingMore = true;
      _moreError = null;
    });

    try {
      final page = await _loadPage(_nextPage);
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        // A page retry should not show duplicate tiles if the network
        // response arrived after a successful retry.
        final knownIds = _logs.map((log) => log.id).toSet();
        _logs = [
          ..._logs,
          ...page.logs.where((log) => !knownIds.contains(log.id)),
        ];
        _nextPage = page.page + 1;
        _hasMore = page.hasMore;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _moreError = error;
        _isLoadingMore = false;
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 420) {
      _loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, theme) {
        return Scaffold(
          backgroundColor: theme.backgroundColor,
          appBar: AppBar(
            backgroundColor: theme.isDark ? theme.surfaceColor : Colors.white,
            foregroundColor: theme.isDark ? theme.inkColor : null,
            surfaceTintColor: Colors.transparent,
            title: const Text('Exercise Gallery'),
          ),
          body: _buildBody(theme),
        );
      },
    );
  }

  Widget _buildBody(CompanyThemeData theme) {
    if (_isLoadingInitial) {
      return Center(
          child: CircularProgressIndicator(color: theme.primaryColor));
    }

    if (_initialError != null) {
      return _GalleryStateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load exercise photos.',
        detail: 'Check your connection and try again.',
        actionLabel: 'Retry',
        onAction: _loadInitial,
        theme: theme,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final groups = groupExerciseGalleryPhotos(_logs);
        final columns = _columnCountForWidth(constraints.maxWidth);
        final slivers = <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: _GalleryIntro(theme: theme),
            ),
          ),
        ];

        if (groups.isEmpty) {
          slivers.add(
            SliverFillRemaining(
              hasScrollBody: false,
              child: _GalleryStateMessage(
                icon: Icons.photo_library_outlined,
                title: 'No exercise photos yet',
                detail:
                    'Photos you add when starting or stopping an exercise will appear here.',
                theme: theme,
              ),
            ),
          );
        } else {
          for (final group in groups) {
            slivers.add(
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                  child: Text(
                    formatExerciseGalleryDate(group.date),
                    style: TextStyle(
                      color: theme.inkColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            );
            slivers.add(
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _GalleryPhotoTile(
                      photo: group.photos[index],
                      theme: theme,
                    ),
                    childCount: group.photos.length,
                  ),
                ),
              ),
            );
          }
        }

        if (_isLoadingMore) {
          slivers.add(
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(color: theme.primaryColor),
                ),
              ),
            ),
          );
        } else if (_moreError != null) {
          slivers.add(
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
                child: Center(
                  child: OutlinedButton.icon(
                    onPressed: _loadMore,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry loading more photos'),
                  ),
                ),
              ),
            ),
          );
        } else {
          slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 28)));
        }

        return RefreshIndicator(
          color: theme.primaryColor,
          onRefresh: _loadInitial,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: slivers,
          ),
        );
      },
    );
  }
}

int _columnCountForWidth(double width) {
  if (width >= 1120) return 5;
  if (width >= 760) return 4;
  if (width >= 520) return 3;
  return 2;
}

class ExerciseGalleryDayGroup {
  ExerciseGalleryDayGroup({
    required this.dateKey,
    required this.date,
    required this.photos,
  });

  final String dateKey;
  final DateTime? date;
  final List<ExerciseGalleryPhoto> photos;
}

/// Flattens each logged session into its available start/end photos while
/// preserving API order. A log's explicit date wins over its creation time,
/// which keeps historical photos grouped correctly after timezone changes.
List<ExerciseGalleryDayGroup> groupExerciseGalleryPhotos(
  List<ExerciseHistoryLog> logs,
) {
  final groups = <String, ExerciseGalleryDayGroup>{};
  for (final log in logs) {
    final date = log.displayDate;
    final key = exerciseGalleryDateKey(date);
    final group = groups.putIfAbsent(
      key,
      () => ExerciseGalleryDayGroup(
        dateKey: key,
        date: date,
        photos: <ExerciseGalleryPhoto>[],
      ),
    );
    group.photos.addAll(log.galleryPhotos);
  }
  return groups.values.toList(growable: false);
}

String exerciseGalleryDateKey(DateTime? date) {
  if (date == null) return 'unknown';
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String formatExerciseGalleryDate(DateTime? date, {DateTime? today}) {
  if (date == null) return 'Undated exercise';
  final formattedDate = DateFormat('EEEE, MMMM d, y').format(date);
  final referenceDate = today ?? DateTime.now();
  return DateUtils.isSameDay(date, referenceDate)
      ? 'Today · $formattedDate'
      : formattedDate;
}

class _GalleryIntro extends StatelessWidget {
  const _GalleryIntro({required this.theme});

  final CompanyThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.photo_library_outlined,
              color: theme.primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Your start and finish photos are organized by workout day.',
              style: TextStyle(
                color: theme.mutedInkColor,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryPhotoTile extends StatelessWidget {
  const _GalleryPhotoTile({
    required this.photo,
    required this.theme,
  });

  final ExerciseGalleryPhoto photo;
  final CompanyThemeData theme;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        final cacheWidth = (constraints.maxWidth * devicePixelRatio)
            .round()
            .clamp(1, 1600)
            .toInt();
        final url = ImageStorageService.normalizeMediaUrl(photo.url);

        return Semantics(
          button: true,
          label: '${photo.kind.label} for ${photo.log.type}',
          child: Material(
            color: theme.surfaceColor,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              key: ValueKey<String>(photo.heroTag),
              onTap: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (context) => ExerciseGalleryDetailScreen(
                      photo: photo,
                      theme: theme,
                    ),
                  ),
                );
              },
              child: Ink(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.primaryColor.withValues(alpha: 0.16),
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: photo.heroTag,
                      child: _GalleryNetworkImage(
                        url: url,
                        cacheWidth: cacheWidth,
                        theme: theme,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          photo.kind.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GalleryNetworkImage extends StatelessWidget {
  const _GalleryNetworkImage({
    required this.url,
    required this.theme,
    required this.fit,
    this.cacheWidth,
  });

  final String url;
  final CompanyThemeData theme;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return _MissingExercisePhoto(theme: theme);
    }

    return Image.network(
      url,
      fit: fit,
      cacheWidth: cacheWidth,
      filterQuality: FilterQuality.low,
      errorBuilder: (context, error, stackTrace) =>
          _MissingExercisePhoto(theme: theme),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: theme.primaryColor.withValues(alpha: 0.08)),
            const Center(child: CircularProgressIndicator.adaptive()),
          ],
        );
      },
    );
  }
}

class _MissingExercisePhoto extends StatelessWidget {
  const _MissingExercisePhoto({required this.theme});

  final CompanyThemeData theme;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: theme.primaryColor.withValues(alpha: 0.08),
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: theme.mutedInkColor,
          size: 30,
        ),
      ),
    );
  }
}

class _GalleryStateMessage extends StatelessWidget {
  const _GalleryStateMessage({
    required this.icon,
    required this.title,
    required this.detail,
    required this.theme,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final CompanyThemeData theme;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: theme.primaryColor, size: 42),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.inkColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.mutedInkColor, height: 1.4),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ExerciseGalleryDetailScreen extends StatelessWidget {
  const ExerciseGalleryDetailScreen({
    super.key,
    required this.photo,
    required this.theme,
  });

  final ExerciseGalleryPhoto photo;
  final CompanyThemeData theme;

  @override
  Widget build(BuildContext context) {
    final log = photo.log;
    final date = formatExerciseGalleryDate(log.displayDate);
    final duration = formatExerciseDuration(
      exerciseLogDuration(
        durationMinutes: log.durationMinutes,
        durationSeconds: log.durationSeconds,
      ),
    );
    final url = ImageStorageService.normalizeMediaUrl(photo.url);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.isDark ? theme.surfaceColor : Colors.white,
        foregroundColor: theme.isDark ? theme.inkColor : null,
        surfaceTintColor: Colors.transparent,
        title: Text(photo.kind.label),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Hero(
                tag: photo.heroTag,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: SizedBox.expand(
                    child: _GalleryNetworkImage(
                      url: url,
                      theme: theme,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '${photo.kind.label} · ${log.type}',
            style: TextStyle(
              color: theme.inkColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          _GalleryDetailRow(
            icon: Icons.calendar_today_outlined,
            label: 'Date',
            value: date,
            theme: theme,
          ),
          _GalleryDetailRow(
            icon: Icons.timer_outlined,
            label: 'Duration',
            value: duration,
            theme: theme,
          ),
          _GalleryDetailRow(
            icon: Icons.local_fire_department_outlined,
            label: 'Intensity',
            value: _intensityLabel(log.intensity),
            theme: theme,
          ),
          if (log.notes != null) ...[
            const SizedBox(height: 12),
            Text(
              'Notes',
              style: TextStyle(
                color: theme.inkColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              log.notes!,
              style: TextStyle(color: theme.mutedInkColor, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

String _intensityLabel(int intensity) {
  switch (intensity) {
    case 3:
      return 'High';
    case 2:
      return 'Moderate';
    case 1:
      return 'Light';
    default:
      return 'Not recorded';
  }
}

class _GalleryDetailRow extends StatelessWidget {
  const _GalleryDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final String value;
  final CompanyThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: theme.primaryColor, size: 20),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: TextStyle(
              color: theme.mutedInkColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: theme.inkColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
