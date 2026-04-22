import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

class SpotifyEmbedPlayer extends StatefulWidget {
  const SpotifyEmbedPlayer({
    super.key,
    required this.trackId,
  });

  final String trackId;

  @override
  State<SpotifyEmbedPlayer> createState() => SpotifyEmbedPlayerState();
}

class SpotifyEmbedPlayerState extends State<SpotifyEmbedPlayer> {
  late final WebViewController _controller;
  bool _isReady = false;
  String? _pendingAction;

  @override
  void initState() {
    super.initState();
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'FlutterSpotify',
        onMessageReceived: (message) {
          if (message.message == 'ready') {
            _isReady = true;
            _flushPendingAction();
          }
        },
      )
      ..loadHtmlString(_buildHtml(widget.trackId));

    if (_controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (_controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
  }

  @override
  void didUpdateWidget(covariant SpotifyEmbedPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackId != widget.trackId) {
      _isReady = false;
      _pendingAction = null;
      _controller.loadHtmlString(_buildHtml(widget.trackId));
    }
  }

  Future<void> play() => _runCommand('play');

  Future<void> pause() => _runCommand('pause');

  Future<void> stopPlayback() => _runCommand('stop');

  Future<void> _runCommand(String command) async {
    if (!_isReady) {
      _pendingAction = command;
      return;
    }

    final jsCommand = switch (command) {
      'play' => 'window.spotifyMeditationPlayer.play();',
      'pause' => 'window.spotifyMeditationPlayer.pause();',
      'stop' => 'window.spotifyMeditationPlayer.stop();',
      _ => '',
    };

    if (jsCommand.isEmpty) return;

    try {
      await _controller.runJavaScript(jsCommand);
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Spotify embed command failed: $command');
      }
    }
  }

  Future<void> _flushPendingAction() async {
    final action = _pendingAction;
    _pendingAction = null;
    if (action != null) {
      await _runCommand(action);
    }
  }

  String _buildHtml(String trackId) {
    final spotifyUri = 'spotify:track:$trackId';
    return '''
<!DOCTYPE html>
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
    <style>
      html, body {
        margin: 0;
        padding: 0;
        background: transparent;
        overflow: hidden;
      }
      #embed-iframe {
        width: 100%;
        height: 180px;
      }
    </style>
  </head>
  <body>
    <div id="embed-iframe"></div>
    <script src="https://open.spotify.com/embed/iframe-api/v1" async></script>
    <script>
      let embedController = null;
      let restartingTrack = false;
      window.spotifyMeditationPlayer = {
        play: function() {
          if (embedController) embedController.play();
        },
        pause: function() {
          if (embedController) embedController.pause();
        },
        stop: function() {
          if (!embedController) return;
          embedController.pause();
          embedController.restart();
        }
      };

      window.onSpotifyIframeApiReady = (IFrameAPI) => {
        const element = document.getElementById('embed-iframe');
        const options = {
          width: '100%',
          height: '180',
          uri: '$spotifyUri'
        };
        IFrameAPI.createController(element, options, (controller) => {
          embedController = controller;
          embedController.addListener('playback_update', (event) => {
            const data = event && event.data ? event.data : null;
            if (!data) return;
            const duration = Number(data.duration || 0);
            const position = Number(data.position || 0);
            const isPaused = Boolean(data.isPaused);

            if (
              !isPaused &&
              duration > 0 &&
              position >= Math.max(0, duration - 1200) &&
              !restartingTrack
            ) {
              restartingTrack = true;
              embedController.restart();
              embedController.play();
              setTimeout(() => {
                restartingTrack = false;
              }, 800);
            }
          });
          FlutterSpotify.postMessage('ready');
        });
      };
    </script>
  </body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 180,
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}
