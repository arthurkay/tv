import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';
import '../services/channel_search.dart';
import '../services/voice_search.dart';
import '../theme/app_theme.dart';
import '../widgets/channel_card.dart';

class SearchScreen extends StatefulWidget {
  final List<Channel> channels;
  final bool voiceAvailable;

  /// Seeded when the assistant handed over a query.
  final String? initialQuery;

  /// Opens the voice prompt as soon as the screen appears, for the Speak button.
  final bool autoListen;

  final void Function(Channel channel, List<Channel> results) onPlay;
  final VoidCallback onClose;

  const SearchScreen({
    super.key,
    required this.channels,
    required this.onPlay,
    required this.onClose,
    this.voiceAvailable = false,
    this.initialQuery,
    this.autoListen = false,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final TextEditingController _controller;
  final FocusNode _fieldFocus = FocusNode(debugLabel: 'SearchField');

  String _query = '';
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery ?? '';
    _controller = TextEditingController(text: _query);
    if (widget.autoListen && widget.voiceAvailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  List<Channel> get _results => ChannelSearch.run(widget.channels, _query);

  Future<void> _listen() async {
    setState(() => _listening = true);
    final heard = await VoiceSearch.listen();
    if (!mounted) return;
    setState(() {
      _listening = false;
      if (heard != null && heard.trim().isNotEmpty) {
        _query = heard;
        _controller.text = heard;
        _controller.selection = TextSelection.collapsed(offset: heard.length);
      }
    });
  }

  /// D-pad down out of the text field moves into the results. Without this the
  /// text-editing shortcuts swallow the arrow key and focus never leaves.
  KeyEventResult _handleFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select) {
      if (_results.isEmpty) return KeyEventResult.handled;
      FocusScope.of(context).focusInDirection(TraversalDirection.down);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.safeHorizontal,
          AppTheme.safeVertical,
          AppTheme.safeHorizontal,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _RoundButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: widget.onClose,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onKeyEvent: _handleFieldKey,
                    child: TextField(
                      controller: _controller,
                      focusNode: _fieldFocus,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      cursorColor: AppTheme.textPrimary,
                      style: const TextStyle(
                        fontSize: 18,
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: _listening ? 'Listening…' : 'Search channels',
                        hintStyle: const TextStyle(
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w400,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: AppTheme.textMuted),
                        filled: true,
                        fillColor: AppTheme.surfaceHover,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: AppTheme.textPrimary, width: 2),
                        ),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                      onSubmitted: (_) {
                        final results = _results;
                        if (results.isNotEmpty) {
                          widget.onPlay(results.first, results);
                        }
                      },
                    ),
                  ),
                ),
                if (widget.voiceAvailable) ...[
                  const SizedBox(width: 12),
                  _RoundButton(
                    icon: _listening
                        ? Icons.graphic_eq_rounded
                        : Icons.mic_none_rounded,
                    highlighted: _listening,
                    onTap: _listen,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            Text(
              _statusLine,
              style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _results.isEmpty
                  ? _EmptyState(
                      query: _query,
                      voiceAvailable: widget.voiceAvailable,
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.only(bottom: AppTheme.safeVertical),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 280,
                        childAspectRatio: 16 / 9,
                        crossAxisSpacing: 18,
                        mainAxisSpacing: 18,
                      ),
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final results = _results;
                        final channel = results[index];
                        return ChannelCard(
                          key: ValueKey(channel.id),
                          channel: channel,
                          onSelect: () => widget.onPlay(channel, results),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String get _statusLine {
    if (_query.trim().isEmpty) {
      return widget.voiceAvailable
          ? 'Type a channel name, or press the mic to speak'
          : 'Type a channel name';
    }
    final count = _results.length;
    return count == 1 ? '1 channel' : '$count channels';
  }
}

class _EmptyState extends StatelessWidget {
  final String query;
  final bool voiceAvailable;

  const _EmptyState({required this.query, required this.voiceAvailable});

  @override
  Widget build(BuildContext context) {
    final searching = query.trim().isNotEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            searching ? Icons.search_off_rounded : Icons.search_rounded,
            size: 40,
            color: AppTheme.textMuted,
          ),
          const SizedBox(height: 14),
          Text(
            searching ? 'No channels match “$query”' : 'Search channels',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            searching
                ? 'Try a shorter name, or a category like News or Sports.'
                : voiceAvailable
                    ? 'Say a channel name, or type one with the remote.'
                    : 'Type a channel name with the remote.',
            style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool highlighted;

  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  State<_RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<_RoundButton> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.highlighted;
    return Focus(
      focusNode: _focusNode,
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
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.textPrimary
                : _focused
                    ? AppTheme.surfaceHover
                    : AppTheme.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: _focused ? AppTheme.textPrimary : AppTheme.border,
              width: _focused ? 2 : 1,
            ),
          ),
          child: Icon(
            widget.icon,
            size: 20,
            color: selected ? AppTheme.surface : AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }
}
