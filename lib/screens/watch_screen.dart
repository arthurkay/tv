import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/channel.dart';
import '../services/thumbnail_service.dart';
import '../widgets/channel_shelf.dart';
import '../theme/app_theme.dart';

class WatchScreen extends StatefulWidget {
  final Channel channel;
  final List<Channel> channels;
  final VoidCallback onBack;
  final ValueChanged<Channel> onChannelSwitch;

  const WatchScreen({
    super.key,
    required this.channel,
    required this.channels,
    required this.onBack,
    required this.onChannelSwitch,
  });

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  static const _controlsTimeout = Duration(seconds: 4);

  late final Player _player;
  late final VideoController _controller;

  /// Owned by the state, not rebuilt in `build`: a node created inside `build`
  /// leaks and re-steals focus from the shelf on every rebuild.
  final FocusNode _keyFocusNode = FocusNode(debugLabel: 'WatchScreenKeys');

  /// Where D-pad focus lands when the controls are summoned with a key, so the
  /// viewer always has a visible starting point to navigate from.
  final FocusNode _playButtonFocus = FocusNode(debugLabel: 'PlayPause');

  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _hideTimer;
  Timer? _thumbnailTimer;

  bool _shelfOpen = false;
  bool _controlsVisible = true;
  bool _buffering = true;
  bool _playing = false;

  /// Set once this player has produced video. Until then a failure is real;
  /// after it, an error event is either transient or belongs to another player.
  bool _hasVideo = false;
  Timer? _startupTimer;
  String? _error;
  BoxFit _fit = BoxFit.contain;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // The viewer's stream gets the bandwidth, and this also stops background
    // capture errors leaking onto this player's error stream.
    ThumbnailService.suspend();

    _player = Player();
    // On Android the default (vo=gpu, hwdec=auto-safe) becomes mediacodec-copy:
    // every decoded frame is copied to CPU memory and re-uploaded, which
    // stutters on TV-class chips. mediacodec_embed renders straight into the
    // surface. The trade-off is that mpv can no longer screenshot this player,
    // so the free frame grab below becomes best-effort (it already tolerates a
    // null result).
    _controller = VideoController(
      _player,
      configuration: defaultTargetPlatform == TargetPlatform.android
          ? const VideoControllerConfiguration(
              vo: 'mediacodec_embed',
              hwdec: 'mediacodec',
            )
          : const VideoControllerConfiguration(),
    );

    _subscriptions.addAll([
      _player.stream.buffering.listen((buffering) {
        if (mounted) setState(() => _buffering = buffering);
      }),
      _player.stream.playing.listen((playing) {
        if (!mounted) return;
        setState(() {
          _playing = playing;
          // A paused picture with no controls is a dead end on a TV.
          if (!playing) _controlsVisible = true;
        });
        if (playing) {
          _startHideTimer();
        } else {
          _hideTimer?.cancel();
        }
      }),
      // `playing` goes true while the stream is still buffering, so the frame
      // grab waits for video dimensions — the first point a frame exists.
      _player.stream.height.listen((height) {
        if (!mounted || (height ?? 0) <= 0) return;
        _startupTimer?.cancel();
        if (!_hasVideo || _error != null) {
          setState(() {
            _hasVideo = true;
            _error = null;
          });
        }
        _scheduleThumbnailCapture();
      }),
      _player.stream.error.listen((error) {
        // mpv reports ffmpeg's errors from a process-global log, so once this
        // channel is on screen an error is not reliably ours to show.
        if (!mounted || _hasVideo) return;
        _fail(error);
      }),
    ]);

    _player.open(Media(widget.channel.url));
    _startHideTimer();
    _startStartupWatchdog();
  }

  /// A stream that never answers produces no error event at all, so without
  /// this the viewer would watch the spinner forever.
  void _startStartupWatchdog() {
    _startupTimer?.cancel();
    _startupTimer = Timer(const Duration(seconds: 25), () {
      if (!mounted || _hasVideo) return;
      _fail('The stream did not start within 25 seconds.');
    });
  }

  void _fail(String message) {
    setState(() {
      _error = message;
      _buffering = false;
      _controlsVisible = true;
    });
    _hideTimer?.cancel();
  }

  @override
  void dispose() {
    ThumbnailService.resume();
    _hideTimer?.cancel();
    _thumbnailTimer?.cancel();
    _startupTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _keyFocusNode.dispose();
    _playButtonFocus.dispose();
    _player.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// This player already has the channel decoded, so its frames cost nothing.
  /// One shortly after the first frame arrives, then one per cache lifetime.
  void _scheduleThumbnailCapture() {
    if (_thumbnailTimer != null) return;
    Timer(const Duration(seconds: 3), _captureThumbnail);
    _thumbnailTimer = Timer.periodic(ThumbnailService.ttl, (_) => _captureThumbnail());
  }

  Future<void> _captureThumbnail() async {
    if (!mounted || _error != null) return;
    try {
      final bytes = await _player
          .screenshot(format: 'image/jpeg')
          .timeout(const Duration(seconds: 10), onTimeout: () => null);
      if (bytes != null && bytes.isNotEmpty) {
        ThumbnailService.put(
          widget.channel,
          await ThumbnailService.scaleFrame(bytes),
        );
      }
    } catch (error) {
      debugPrint('[thumbnail] live capture failed for ${widget.channel.name}: $error');
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_controlsTimeout, () {
      if (!mounted || _shelfOpen || _error != null || !_playing) return;
      setState(() => _controlsVisible = false);
    });
  }

  /// [focusPlay] hands D-pad focus to the play/pause button once the bar has
  /// been built, so the next arrow press moves between visible controls rather
  /// than into nothing.
  void _revealControls({bool focusPlay = false}) {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _startHideTimer();
    if (focusPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controlsVisible) _playButtonFocus.requestFocus();
      });
    }
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _toggleShelf() {
    setState(() {
      _shelfOpen = !_shelfOpen;
      if (_shelfOpen) _controlsVisible = true;
    });

    if (_shelfOpen) {
      _hideTimer?.cancel();
    } else {
      // Focus was on a shelf card that has just left the tree.
      _keyFocusNode.requestFocus();
      _startHideTimer();
    }
  }

  void _togglePlayPause() {
    _player.playOrPause();
    _revealControls(focusPlay: true);
  }

  /// Wraps around, so channel-up off the end of the list returns to the start.
  void _stepChannel(int delta) {
    final channels = widget.channels;
    if (channels.length < 2) return;
    final index = channels.indexWhere((c) => c.id == widget.channel.id);
    if (index < 0) return;
    widget.onChannelSwitch(channels[(index + delta) % channels.length]);
  }

  void _toggleFit() {
    setState(() => _fit = _fit == BoxFit.contain ? BoxFit.cover : BoxFit.contain);
    _startHideTimer();
  }

  void _retry() {
    setState(() {
      _error = null;
      _buffering = true;
      _controlsVisible = true;
      _hasVideo = false;
    });
    _keyFocusNode.requestFocus();
    _player.open(Media(widget.channel.url));
    _startHideTimer();
    _startStartupWatchdog();
  }

  /// mpv's error text can come from another player, so the detail line is only
  /// shown when it mentions this channel's host.
  String? get _errorDetailForThisChannel {
    final error = _error;
    if (error == null) return null;
    final host = Uri.tryParse(widget.channel.url)?.host;
    if (host == null || host.isEmpty) return null;
    return error.contains(host) ? error : null;
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;

    // Only Escape (desktop) is handled here. Android's BACK belongs to the
    // Navigator now: handling it here too would pop twice on one press.
    if (key == LogicalKeyboardKey.escape) {
      if (_shelfOpen) {
        _toggleShelf();
      } else {
        widget.onBack();
      }
      return;
    }

    // OK reaches here only when no control has focus (a focused button
    // handles it itself), so it is the remote's play/pause. Many Google TV
    // remotes have no dedicated media keys at all.
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      _togglePlayPause();
      return;
    }

    if (key == LogicalKeyboardKey.mediaStop) {
      widget.onBack();
      return;
    }

    // Remote channel and track keys step through the list the viewer came from.
    if (key == LogicalKeyboardKey.channelUp ||
        key == LogicalKeyboardKey.mediaTrackNext) {
      _stepChannel(1);
      return;
    }
    if (key == LogicalKeyboardKey.channelDown ||
        key == LogicalKeyboardKey.mediaTrackPrevious) {
      _stepChannel(-1);
      return;
    }

    if (key == LogicalKeyboardKey.arrowDown && !_shelfOpen) {
      _toggleShelf();
      return;
    }
    if (key == LogicalKeyboardKey.arrowUp && _shelfOpen) {
      _toggleShelf();
      return;
    }

    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      _revealControls(focusPlay: !_controlsVisible);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: KeyboardListener(
        focusNode: _keyFocusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video. Wakelock is handled by this screen, so the widget's own
            // wakelock is off — otherwise pausing would release it.
            Center(
              child: Video(
                controller: _controller,
                controls: NoVideoControls,
                fit: _fit,
                wakelock: false,
              ),
            ),

            // Tap area
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _toggleControls,
                onDoubleTap: _togglePlayPause,
              ),
            ),

            if (_buffering && _error == null)
              _BufferingIndicator(channel: widget.channel),

            if (_error != null)
              _ErrorOverlay(
                channel: widget.channel,
                message: _errorDetailForThisChannel,
                onRetry: _retry,
                onBack: widget.onBack,
              ),

            // Top bar
            if (_controlsVisible)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _TopBar(
                  channel: widget.channel,
                  channelCount: widget.channels.length,
                  playing: _playing,
                  playFocusNode: _playButtonFocus,
                  zoomed: _fit == BoxFit.cover,
                  shelfOpen: _shelfOpen,
                  onBack: widget.onBack,
                  onToggleShelf: _toggleShelf,
                  onTogglePlay: _togglePlayPause,
                  onToggleFit: _toggleFit,
                ),
              ),

            // Bottom gradient
            if (_controlsVisible)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 80,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

            // Shelf
            if (_shelfOpen)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ChannelShelf(
                  channels: widget.channels,
                  activeChannelId: widget.channel.id,
                  onChannelSelect: (channel) {
                    if (channel.id == widget.channel.id) {
                      _toggleShelf();
                      return;
                    }
                    // The shell re-keys this screen, which builds a fresh
                    // player for the new URL — opening it here as well would
                    // pull the stream twice.
                    widget.onChannelSwitch(channel);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BufferingIndicator extends StatelessWidget {
  final Channel channel;

  const _BufferingIndicator({required this.channel});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(color: AppTheme.textPrimary, strokeWidth: 2),
          ),
          const SizedBox(height: 14),
          Text(
            'Tuning in to ${channel.name}',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textPrimary.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  final Channel channel;
  final String? message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  const _ErrorOverlay({
    required this.channel,
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.signal_wifi_statusbar_null_rounded,
                  size: 40, color: AppTheme.textMuted),
              const SizedBox(height: 16),
              Text(
                "${channel.name} isn't playing",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                channel.geoBlocked
                    ? 'This channel is geo-blocked, so it may be unavailable from your region.'
                    : 'The stream did not respond. Free channels change URLs often.',
                style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                textAlign: TextAlign.center,
              ),
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(
                  message!,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _BarIconButton(
                    icon: Icons.refresh_rounded,
                    label: 'Try again',
                    autofocus: true,
                    onTap: onRetry,
                  ),
                  const SizedBox(width: 12),
                  _BarIconButton(
                    icon: Icons.grid_view_rounded,
                    label: 'All channels',
                    onTap: onBack,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final Channel channel;
  final int channelCount;
  final bool playing;
  final FocusNode playFocusNode;
  final bool zoomed;
  final bool shelfOpen;
  final VoidCallback onBack;
  final VoidCallback onToggleShelf;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleFit;

  const _TopBar({
    required this.channel,
    required this.channelCount,
    required this.playing,
    required this.playFocusNode,
    required this.zoomed,
    required this.shelfOpen,
    required this.onBack,
    required this.onToggleShelf,
    required this.onTogglePlay,
    required this.onToggleFit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.black.withValues(alpha: 0.4),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          _BarIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            label: 'Back',
            onTap: onBack,
          ),
          const SizedBox(width: 16),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.textMuted),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'LIVE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            channel.name,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (channel.geoBlocked) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.surfaceHover,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppTheme.border),
              ),
              child: const Text(
                'GEO',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                ),
              ),
            ),
          ],

          const Spacer(),

          if (channelCount > 1) ...[
            const Text(
              'CH ▲▼ to change channel',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textMuted,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 14),
          ],

          _BarIconButton(
            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            label: playing ? 'Pause' : 'Play',
            focusNode: playFocusNode,
            onTap: onTogglePlay,
          ),
          const SizedBox(width: 8),

          _BarIconButton(
            icon: Icons.grid_view_rounded,
            selected: shelfOpen,
            onTap: onToggleShelf,
          ),
          const SizedBox(width: 8),

          // Zoom to fill: the player is already fullscreen on a TV, so this
          // switches how the picture fills it instead.
          _BarIconButton(
            icon: zoomed ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
            selected: zoomed,
            onTap: onToggleFit,
          ),
        ],
      ),
    );
  }
}

class _BarIconButton extends StatefulWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final bool selected;
  final bool autofocus;
  final FocusNode? focusNode;

  const _BarIconButton({
    required this.icon,
    required this.onTap,
    this.label,
    this.selected = false,
    this.autofocus = false,
    this.focusNode,
  });

  @override
  State<_BarIconButton> createState() => _BarIconButtonState();
}

class _BarIconButtonState extends State<_BarIconButton> {
  FocusNode? _ownNode;
  bool _focused = false;

  FocusNode get _focusNode => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _ownNode?.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    // Focus inverts the button outright: at ten feet a slightly lighter grey
    // is invisible. A selected-but-unfocused toggle keeps a light border.
    final bg = _focused
        ? AppTheme.textPrimary
        : widget.selected
            ? AppTheme.surfaceHover
            : AppTheme.surface;
    final fg = _focused ? AppTheme.surface : AppTheme.textPrimary;

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.select)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused || widget.selected
                  ? AppTheme.textPrimary
                  : AppTheme.border,
              width: _focused ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 18, color: fg),
              if (widget.label != null) ...[
                const SizedBox(width: 6),
                Text(widget.label!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
