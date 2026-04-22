import 'dart:async';

import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/services/audio_helper.dart';
import 'package:selfcare_projects/src/services/spotify_helper.dart';
import 'package:selfcare_projects/src/services/user_preferences.dart';

class MeditationSong extends StatefulWidget {
  const MeditationSong({super.key});

  @override
  State<MeditationSong> createState() => _MeditationSongState();
}

class _MeditationSongState extends State<MeditationSong>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  Timer? _spotifySearchDebounce;
  int? _savedSongIndex;
  int? _playingIndex;
  String? _savedSpotifyTitle;
  String _searchQuery = '';
  bool _spotifyLoading = false;
  String? _spotifyError;
  List<SpotifyTrack> _spotifyTracks = const [];

  final List<Map<String, String>> songs = const [
    {
      "title": "Under the Shining Sun",
      "assetImage": "assets/images/forest_birds.jpg",
      "assetPath": "audio/Forest_Birds.mp3",
    },
    {
      "title": "Call of the Waves",
      "assetImage": "assets/images/ocean_waves.jpg",
      "assetPath": "audio/Ocean_Waves.mp3",
    },
    {
      "title": "It's Raining Gently",
      "assetImage": "assets/images/rain.jpg",
      "assetPath": "audio/Rain_Sounds.mp3",
    },
    {
      "title": "Beside the Fireplace",
      "assetImage": "assets/images/night_firepit.jpg",
      "assetPath": "audio/Night_Firepit.mp3",
    },
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!mounted || _tabController.indexIsChanging) return;
      setState(() {});
      if (_tabController.index == 1) {
        _scheduleSpotifySearch(immediate: true);
      }
    });
    _loadSavedSong();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      _stopPreview();
    }
  }

  Future<void> _loadSavedSong() async {
    final username = await UserPreferences.loadUsername();
    if (username == null) return;

    final savedSong = await UserPreferences.loadFavoriteSong(username);
    final savedSource =
        (await UserPreferences.loadFavoriteSongSource(username)) ?? 'default';
    if (!mounted) return;

    final index = songs.indexWhere((song) => song["title"] == savedSong);
    setState(() {
      _savedSongIndex = index == -1 ? null : index;
      _savedSpotifyTitle = savedSource == 'spotify' ? savedSong : null;
      _tabController.index = savedSource == 'spotify' ? 1 : 0;
    });

    if (_tabController.index == 1) {
      _scheduleSpotifySearch(immediate: true);
    }
  }

  Future<void> _selectSong(
    int index, {
    required String source,
  }) async {
    final username = await UserPreferences.loadUsername();
    if (username != null) {
      await UserPreferences.saveFavoriteSong(username, songs[index]["title"]!);
      await UserPreferences.saveFavoriteSongSource(username, source);
      await UserPreferences.saveFavoriteSpotifyUrl(username, '');
    }

    if (!mounted) return;
    setState(() {
      _savedSongIndex = index;
    });

    Navigator.pop(context, {
      'title': songs[index]["title"]!,
      'source': source,
    });
  }

  Future<void> _selectSpotifyTrack(SpotifyTrack track) async {
    final username = await UserPreferences.loadUsername();
    if (username != null) {
      await UserPreferences.saveFavoriteSong(username, track.title);
      await UserPreferences.saveFavoriteSongSource(username, 'spotify');
      await UserPreferences.saveFavoriteSpotifyUrl(username, track.spotifyUrl);
    }

    if (!mounted) return;
    setState(() {
      _savedSongIndex = null;
      _savedSpotifyTitle = track.title;
    });

    Navigator.pop(context, {
      'title': track.title,
      'source': 'spotify',
      'spotifyUrl': track.spotifyUrl,
    });
  }

  void _stopPreview() {
    AudioHelper.stopAudio();
    if (!mounted) return;
    setState(() {
      _playingIndex = null;
    });
  }

  Future<void> _togglePreview(int index) async {
    final song = songs[index];
    await AudioHelper.togglePlayPause(
      song["title"]!,
      song["assetPath"]!,
      (playingSong) {
        if (!mounted) return;
        setState(() {
          _playingIndex = playingSong == null ? null : index;
        });
      },
    );
  }

  void _scheduleSpotifySearch({bool immediate = false}) {
    _spotifySearchDebounce?.cancel();

    if (immediate) {
      _performSpotifySearch();
      return;
    }

    _spotifySearchDebounce = Timer(
      const Duration(milliseconds: 450),
      _performSpotifySearch,
    );
  }

  Future<void> _performSpotifySearch() async {
    final queryAtStart = _searchQuery.trim();
    setState(() {
      _spotifyLoading = true;
      _spotifyError = null;
    });

    try {
      final tracks = await SpotifyHelper.fetchMeditationTracks(
        query: queryAtStart,
      );
      if (!mounted || queryAtStart != _searchQuery.trim()) return;
      setState(() {
        _spotifyTracks = tracks;
      });
    } catch (error) {
      if (!mounted || queryAtStart != _searchQuery.trim()) return;
      setState(() {
        _spotifyError = '$error';
        _spotifyTracks = const [];
      });
    } finally {
      if (mounted && queryAtStart == _searchQuery.trim()) {
        setState(() {
          _spotifyLoading = false;
        });
      }
    }
  }

  List<Map<String, String>> get _filteredDefaultSongs {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return songs;
    }

    return songs.where((song) {
      final title = (song["title"] ?? '').toLowerCase();
      return title.contains(query);
    }).toList();
  }

  Widget _buildSongList({
    required bool spotifyMode,
  }) {
    final visibleSongs = _filteredDefaultSongs;
    if (visibleSongs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No default music matched your search.'),
        ),
      );
    }

    return ListView.builder(
      itemCount: visibleSongs.length,
      itemBuilder: (context, index) {
        final song = visibleSongs[index];
        final originalIndex = songs.indexOf(song);
        final isSelected = _savedSongIndex == originalIndex;
        final isPreviewPlaying = _playingIndex == originalIndex;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                song["assetImage"]!,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
              ),
            ),
            title: Text(
              song["title"]!,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              spotifyMode
                  ? 'Select this to use Spotify from the meditation timer.'
                  : 'Select this to use the app music player.',
            ),
            trailing: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                if (!spotifyMode)
                  IconButton(
                    icon: Icon(
                      isPreviewPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    tooltip: 'Preview default music',
                    onPressed: () => _togglePreview(originalIndex),
                  ),
                IconButton(
                  icon: Icon(
                    isSelected ? Icons.check_circle : Icons.check_circle_outline,
                    color: isSelected ? const Color(0xFF59BDB3) : null,
                  ),
                  tooltip: spotifyMode
                      ? 'Use Spotify music'
                      : 'Use default music',
                  onPressed: () => _selectSong(
                    originalIndex,
                    source: spotifyMode ? 'spotify' : 'default',
                  ),
                ),
              ],
            ),
            onTap: () => _selectSong(
              originalIndex,
              source: spotifyMode ? 'spotify' : 'default',
            ),
          ),
        );
      },
    );
  }

  Widget _buildSpotifyTrackList() {
    if (_spotifyLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_spotifyError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load Spotify tracks right now.\n$_spotifyError',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_spotifyTracks.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.trim().isEmpty
              ? 'No suggested Spotify songs found right now.'
              : 'No Spotify songs matched "${_searchQuery.trim()}".',
        ),
      );
    }

    return ListView.builder(
      itemCount: _spotifyTracks.length,
      itemBuilder: (context, index) {
        final track = _spotifyTracks[index];
        final isSelected = _savedSpotifyTitle == track.title;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: track.albumImageUrl.isNotEmpty
                  ? Image.network(
                      track.albumImageUrl,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 52,
                      height: 52,
                      color: Colors.green.shade100,
                      alignment: Alignment.center,
                      child: const Icon(Icons.music_note),
                    ),
            ),
            title: Text(
              track.title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              track.artistNames,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: Icon(
                isSelected ? Icons.check_circle : Icons.check_circle_outline,
                color: isSelected ? const Color(0xFF59BDB3) : null,
              ),
              tooltip: 'Use this Spotify track',
              onPressed: () => _selectSpotifyTrack(track),
            ),
            onTap: () => _selectSpotifyTrack(track),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _spotifySearchDebounce?.cancel();
    _searchController.dispose();
    _stopPreview();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Music'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Default Music'),
            Tab(text: 'Spotify Music'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              _tabController.index == 1
                  ? 'Choose a real Spotify track to use when you start meditation.'
                  : 'Choose a track to use the app music player during meditation.',
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: _tabController.index == 1
                    ? 'Search Spotify songs'
                    : 'Search default music',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.trim().isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _spotifyTracks = const [];
                            _spotifyError = null;
                            _spotifyLoading = false;
                          });
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
                if (_tabController.index == 1) {
                  _scheduleSpotifySearch();
                }
              },
              onSubmitted: (_) {
                if (_tabController.index == 1) {
                  _scheduleSpotifySearch(immediate: true);
                }
              },
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSongList(spotifyMode: false),
                _buildSpotifyTrackList(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
