import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'models/channel.dart';
import 'services/channel_search.dart';
import 'services/m3u_parser.dart';
import 'services/voice_search.dart';
import 'theme/app_theme.dart';
import 'screens/browse_screen.dart';
import 'screens/search_screen.dart';
import 'screens/watch_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const VieoApp());
}

class VieoApp extends StatelessWidget {
  const VieoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vieo TV',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: const AppShell(),
    );
  }
}

/// Owns the playlist and the browse grid, and pushes the other screens as real
/// routes.
///
/// Search and the player are pushed rather than swapped in place so that the
/// remote's BACK key works: on the root route Flutter tells Android it does not
/// handle back, and the system finishes the activity without ever consulting
/// the framework. With something on the stack, back is an ordinary pop.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  List<Channel> _channels = [];
  List<String> _categories = const ['All'];
  String _category = 'All';
  bool _voiceAvailable = false;
  bool _loading = true;

  /// An assistant query can arrive before the playlist has parsed.
  String? _deferredQuery;

  /// The query already acted on. A cold start can surface the same query twice
  /// — once as the launch intent, once through onNewIntent — and acting twice
  /// stacks a second player behind the first.
  String? _appliedQuery;

  @override
  void initState() {
    super.initState();
    _loadChannels();
    _initVoice();
    VoiceSearch.onSearchIntent(_handleAssistantQuery);
  }

  Future<void> _loadChannels() async {
    final channels = await M3uParser.load();
    if (!mounted) return;
    final categories = channels.map((c) => c.category).toSet().toList()..sort();
    setState(() {
      _channels = channels;
      _categories = ['All', ...categories];
      _loading = false;
    });

    final deferred = _deferredQuery;
    if (deferred != null) {
      _deferredQuery = null;
      _handleAssistantQuery(deferred);
    }
  }

  Future<void> _initVoice() async {
    final available = await VoiceSearch.isAvailable();
    if (mounted) setState(() => _voiceAvailable = available);

    final launchQuery = await VoiceSearch.takeLaunchQuery();
    if (launchQuery != null) _handleAssistantQuery(launchQuery);
  }

  List<Channel> get _visibleChannels => _category == 'All'
      ? _channels
      : _channels.where((c) => c.category == _category).toList();

  /// Fades rather than slides: a full-screen player sliding in from the edge
  /// reads as clumsy on a TV.
  ///
  /// [child] is built ONCE by the caller and handed over, because
  /// `pageBuilder` can run more than once per route — building the screen
  /// inside it spawns a second State, and for the player that means a second
  /// [Player] opening the same stream.
  PageRouteBuilder<void> _route(String name, Widget child) {
    return PageRouteBuilder<void>(
      settings: RouteSettings(name: name),
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (_, _, _) => child,
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  PageRouteBuilder<void> _watchRoute(Channel channel, List<Channel> list) {
    final navigator = Navigator.of(context);
    return _route(
      'watch/${channel.id}',
      WatchScreen(
        channel: channel,
        channels: list,
        onBack: () => navigator.maybePop(),
        // Replacing keeps the stack at one player, so back still lands on
        // whatever the viewer came from.
        onChannelSwitch: (next) =>
            navigator.pushReplacement(_watchRoute(next, list)),
      ),
    );
  }

  PageRouteBuilder<void> _searchRoute({String? initialQuery, bool autoListen = false}) {
    final navigator = Navigator.of(context);
    return _route(
      'search',
      SearchScreen(
        channels: _channels,
        voiceAvailable: _voiceAvailable,
        initialQuery: initialQuery,
        autoListen: autoListen,
        onClose: () => navigator.maybePop(),
        onPlay: (channel, results) =>
            navigator.push(_watchRoute(channel, results)),
      ),
    );
  }

  /// A query from the assistant is a request to watch something, so the best
  /// match starts playing with the rest of the results behind it.
  void _handleAssistantQuery(String query) {
    if (_channels.isEmpty) {
      _deferredQuery = query;
      return;
    }
    if (query == _appliedQuery) return;
    _appliedQuery = query;

    final results = ChannelSearch.run(_channels, query);

    // Never navigate mid-build: an intent can land during startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.popUntil((route) => route.isFirst);
      navigator.push(_searchRoute(initialQuery: query));
      if (results.isNotEmpty) {
        navigator.push(_watchRoute(results.first, results));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.surface,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.textMuted, strokeWidth: 2),
        ),
      );
    }

    return BrowseScreen(
      channels: _visibleChannels,
      categories: _categories,
      selectedCategory: _category,
      onCategorySelect: (category) => setState(() => _category = category),
      onChannelSelect: (channel) =>
          Navigator.of(context).push(_watchRoute(channel, _visibleChannels)),
      voiceAvailable: _voiceAvailable,
      onSearch: () => Navigator.of(context).push(_searchRoute()),
      onVoiceSearch: () =>
          Navigator.of(context).push(_searchRoute(autoListen: true)),
    );
  }
}
