import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/channel.dart';
import '../services/thumbnail_service.dart';
import '../theme/app_theme.dart';

class ChannelCard extends StatefulWidget {
  final Channel channel;
  final bool isActive;
  final bool autofocus;
  final VoidCallback onSelect;

  const ChannelCard({
    super.key,
    required this.channel,
    required this.onSelect,
    this.isActive = false,
    this.autofocus = false,
  });

  @override
  State<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<ChannelCard> {
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
    final borderColor = _focused
        ? AppTheme.textPrimary
        : widget.isActive
            ? AppTheme.borderFocus
            : AppTheme.border;

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.select)) {
          widget.onSelect();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedScale(
          scale: _focused ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: borderColor,
                width: _focused || widget.isActive ? 2 : 1,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ChannelThumbnail(channel: widget.channel),

                  // Scrim, so the caption stays readable over any frame.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Color(0xE6000000),
                          Color(0x66000000),
                          Color(0x00000000),
                        ],
                        stops: [0.0, 0.45, 0.75],
                      ),
                    ),
                  ),

                  // Caption
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 9,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.channel.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.channel.category.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary.withValues(alpha: 0.55),
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (widget.channel.geoBlocked)
                    const Positioned(top: 8, right: 8, child: _Badge(label: 'GEO')),

                  if (widget.isActive)
                    const Positioned(top: 8, left: 8, child: _NowPlayingBadge()),

                  if (_focused)
                    Center(
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.textPrimary.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 26,
                          color: AppTheme.surface,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the channel's latest captured frame, falling back to a generated tile
/// until one arrives. A newer frame cross-fades in over the placeholder and
/// then swaps in place (`gaplessPlayback`), so the card never blanks out while
/// a refresh decodes.
class _ChannelThumbnail extends StatefulWidget {
  final Channel channel;

  const _ChannelThumbnail({required this.channel});

  @override
  State<_ChannelThumbnail> createState() => _ChannelThumbnailState();
}

class _ChannelThumbnailState extends State<_ChannelThumbnail> {
  @override
  void initState() {
    super.initState();
    ThumbnailService.request(widget.channel);
  }

  @override
  void didUpdateWidget(covariant _ChannelThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.url != widget.channel.url) {
      ThumbnailService.request(widget.channel);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Uint8List?>(
      valueListenable: ThumbnailService.frameOf(widget.channel),
      builder: (context, frame, _) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: frame == null
              ? _ThumbnailPlaceholder(
                  key: const ValueKey('placeholder'),
                  channel: widget.channel,
                )
              : Image.memory(
                  frame,
                  key: const ValueKey('frame'),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  // Decode at card scale, not stream scale.
                  cacheWidth: 480,
                  filterQuality: FilterQuality.low,
                ),
        );
      },
    );
  }
}

/// A deterministic tile per channel — same channel, same shade every launch —
/// kept desaturated so it reads as texture inside the monochrome theme.
class _ThumbnailPlaceholder extends StatelessWidget {
  final Channel channel;

  const _ThumbnailPlaceholder({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    final hash = channel.name.codeUnits.fold<int>(7, (acc, c) => (acc * 31 + c) & 0xFFFF);
    final hue = (hash % 360).toDouble();
    final top = HSLColor.fromAHSL(1, hue, 0.10, 0.20).toColor();
    final bottom = HSLColor.fromAHSL(1, hue, 0.08, 0.11).toColor();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ),
      ),
      child: Center(
        child: Text(
          channel.name.isNotEmpty ? channel.name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary.withValues(alpha: 0.22),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;

  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary.withValues(alpha: 0.75),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _NowPlayingBadge extends StatelessWidget {
  const _NowPlayingBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 6,
            height: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(color: AppTheme.surface, shape: BoxShape.circle),
            ),
          ),
          SizedBox(width: 5),
          Text(
            'ON NOW',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: AppTheme.surface,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
