import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/channel.dart';
import '../theme/app_theme.dart';
import '../widgets/channel_card.dart';
import '../widgets/category_filter.dart';
import '../widgets/vieo_mark.dart';

class BrowseScreen extends StatefulWidget {
  final List<Channel> channels;
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onCategorySelect;
  final int? activeChannelId;
  final ValueChanged<Channel> onChannelSelect;
  final bool voiceAvailable;
  final VoidCallback onSearch;
  final VoidCallback onVoiceSearch;

  const BrowseScreen({
    super.key,
    required this.channels,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelect,
    required this.onChannelSelect,
    required this.onSearch,
    required this.onVoiceSearch,
    this.voiceAvailable = false,
    this.activeChannelId,
  });

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  static const _logoHeight = 40.0;
  static const _logoGap = 14.0;

  /// The first card autofocuses once, on entry. Without the latch it would
  /// grab focus again every time the grid recycles that tile back into view.
  bool _initialFocusDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _initialFocusDone = true);
    });
  }

  /// The remote's SEARCH key, and `/` on a keyboard, open search from the grid.
  KeyEventResult _handleSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.browserSearch ||
        key == LogicalKeyboardKey.find ||
        key == LogicalKeyboardKey.slash) {
      widget.onSearch();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleSearchKey,
      child: Scaffold(
      backgroundColor: AppTheme.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.safeHorizontal,
              AppTheme.safeVertical,
              AppTheme.safeHorizontal,
              8,
            ),
            child: Row(
              children: [
                const VieoMark(height: _logoHeight),
                const SizedBox(width: _logoGap),
                const Text(
                  'Vieo TV',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const Spacer(),
                if (widget.voiceAvailable) ...[
                  _HeaderButton(
                    icon: Icons.mic_none_rounded,
                    label: 'Speak',
                    onTap: widget.onVoiceSearch,
                  ),
                  const SizedBox(width: 10),
                ],
                _HeaderButton(
                  icon: Icons.search_rounded,
                  label: 'Search',
                  onTap: widget.onSearch,
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: AppTheme.safeHorizontal + VieoMark.widthFor(_logoHeight) + _logoGap,
            ),
            child: Text(
              '${widget.channels.length} channels  •  '
              'D-pad to navigate, OK to play, Search to find a channel',
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Category filter
          CategoryFilter(
            categories: widget.categories,
            selected: widget.selectedCategory,
            onSelect: widget.onCategorySelect,
          ),
          const SizedBox(height: 12),

          // Channel grid — D-pad navigation is Flutter's directional traversal
          // over the Focus node each ChannelCard owns.
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.safeHorizontal,
                12,
                AppTheme.safeHorizontal,
                AppTheme.safeVertical,
              ),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 280,
                childAspectRatio: 16 / 9,
                crossAxisSpacing: 18,
                mainAxisSpacing: 18,
              ),
              itemCount: widget.channels.length,
              itemBuilder: (context, index) {
                final channel = widget.channels[index];
                return ChannelCard(
                  key: ValueKey(channel.id),
                  channel: channel,
                  isActive: channel.id == widget.activeChannelId,
                  autofocus: index == 0 && !_initialFocusDone,
                  onSelect: () => widget.onChannelSelect(channel),
                );
              },
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _HeaderButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_HeaderButton> createState() => _HeaderButtonState();
}

class _HeaderButtonState extends State<_HeaderButton> {
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _focused ? AppTheme.textPrimary : AppTheme.surfaceHover,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _focused ? AppTheme.textPrimary : AppTheme.border,
              width: _focused ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: _focused ? AppTheme.surface : AppTheme.textPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _focused ? AppTheme.surface : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
