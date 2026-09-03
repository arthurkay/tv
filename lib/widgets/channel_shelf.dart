import 'package:flutter/material.dart';
import '../models/channel.dart';
import '../theme/app_theme.dart';
import 'channel_card.dart';

class ChannelShelf extends StatefulWidget {
  final List<Channel> channels;
  final int activeChannelId;
  final ValueChanged<Channel> onChannelSelect;

  const ChannelShelf({
    super.key,
    required this.channels,
    required this.activeChannelId,
    required this.onChannelSelect,
  });

  @override
  State<ChannelShelf> createState() => _ChannelShelfState();
}

class _ChannelShelfState extends State<ChannelShelf> {
  static const _cardWidth = 220.0;
  static const _gap = 16.0;
  static const _horizontalPadding = AppTheme.safeHorizontal;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // The shelf is built fresh each time it opens, so this is the hook that
    // actually runs; didUpdateWidget only covers an in-place channel change.
    _scrollToActive();
  }

  @override
  void didUpdateWidget(covariant ChannelShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeChannelId != widget.activeChannelId) {
      _scrollToActive();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActive() {
    final idx = widget.channels.indexWhere((c) => c.id == widget.activeChannelId);
    if (idx < 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      final cardStart = _horizontalPadding + idx * (_cardWidth + _gap);
      final centered = cardStart + _cardWidth / 2 - position.viewportDimension / 2;
      _scrollController.animateTo(
        centered.clamp(position.minScrollExtent, position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 210 + AppTheme.safeVertical,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: AppTheme.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTheme.safeHorizontal, 12, AppTheme.safeHorizontal, 6),
            child: Row(
              children: [
                const Text(
                  'UP NEXT',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '← → to browse  •  OK to play  •  ↑ to close',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                  _horizontalPadding, 0, _horizontalPadding, AppTheme.safeVertical),
              itemCount: widget.channels.length,
              separatorBuilder: (context, index) => const SizedBox(width: _gap),
              itemBuilder: (context, index) {
                final channel = widget.channels[index];
                return SizedBox(
                  width: _cardWidth,
                  // Centred inside a taller row so the focus scale and shadow
                  // are not clipped by the viewport.
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ChannelCard(
                        key: ValueKey(channel.id),
                        channel: channel,
                        isActive: channel.id == widget.activeChannelId,
                        onSelect: () => widget.onChannelSelect(channel),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
