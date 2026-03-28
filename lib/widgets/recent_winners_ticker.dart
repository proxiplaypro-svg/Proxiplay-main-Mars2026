import 'dart:async';

import '/flutter_flow/flutter_flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RecentWinnersTicker extends StatefulWidget {
  const RecentWinnersTicker({
    super.key,
    required this.messages,
  });

  final List<String> messages;

  @override
  State<RecentWinnersTicker> createState() => _RecentWinnersTickerState();
}

class _RecentWinnersTickerState extends State<RecentWinnersTicker> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _sequenceKey = GlobalKey();
  Timer? _retryTimer;
  bool _isAutoScrolling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restartAutoScroll());
  }

  @override
  void didUpdateWidget(covariant RecentWinnersTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages.join('|') != widget.messages.join('|')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restartAutoScroll());
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _restartAutoScroll() {
    _retryTimer?.cancel();
    if (!_scrollController.hasClients) {
      _retryTimer = Timer(
        const Duration(milliseconds: 400),
        _restartAutoScroll,
      );
      return;
    }
    if (_scrollController.offset != 0.0) {
      _scrollController.jumpTo(0.0);
    }
    _ensureAutoScroll();
  }

  Future<void> _ensureAutoScroll() async {
    if (!mounted || _isAutoScrolling || !_scrollController.hasClients) {
      return;
    }
    final loopExtent = _singleSequenceWidth;
    if (loopExtent <= 0 || _scrollController.position.maxScrollExtent <= 0) {
      _retryTimer?.cancel();
      _retryTimer = Timer(
        const Duration(milliseconds: 600),
        _restartAutoScroll,
      );
      return;
    }

    _isAutoScrolling = true;
    try {
      while (mounted && _scrollController.hasClients) {
        final extent = _singleSequenceWidth;
        if (extent <= 0 || _scrollController.position.maxScrollExtent <= 0) {
          break;
        }
        final durationSeconds = (extent / 12.0).clamp(24.0, 54.0).round();
        await _scrollController.animateTo(
          extent,
          duration: Duration(seconds: durationSeconds),
          curve: Curves.linear,
        );
        if (!mounted || !_scrollController.hasClients) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
        _scrollController.jumpTo(0.0);
      }
    } finally {
      _isAutoScrolling = false;
    }
  }

  double get _singleSequenceWidth {
    final context = _sequenceKey.currentContext;
    if (context == null) {
      return 0.0;
    }
    final renderBox = context.findRenderObject();
    if (renderBox is! RenderBox || !renderBox.hasSize) {
      return 0.0;
    }
    return renderBox.size.width;
  }

  Widget _buildMessageSequence(FlutterFlowTheme theme, {Key? key}) {
    return Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 8.0),
        ...widget.messages.map(
          (message) => Padding(
            padding: const EdgeInsets.only(right: 34.0),
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.visible,
              style: theme.bodySmall.override(
                font: GoogleFonts.inter(
                  fontWeight: FontWeight.w500,
                  fontStyle: theme.bodySmall.fontStyle,
                ),
                color: const Color(0xFF2C2F5B).withValues(alpha: 0.86),
                letterSpacing: 0.0,
                fontWeight: FontWeight.w500,
                fontStyle: theme.bodySmall.fontStyle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12.0),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.messages.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = FlutterFlowTheme.of(context);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 60.0),
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FB),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: const Color(0xFFA0134D).withValues(alpha: 0.14),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2C2F5B).withValues(alpha: 0.06),
            blurRadius: 14.0,
            offset: const Offset(0.0, 6.0),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38.0,
            height: 38.0,
            decoration: BoxDecoration(
              color: const Color(0xFFF7E6EE),
              borderRadius: BorderRadius.circular(11.0),
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: Color(0xFFA0134D),
              size: 18.0,
            ),
          ),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ils ont gagné',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.titleMedium.override(
                    font: GoogleFonts.interTight(
                      fontWeight: FontWeight.w700,
                      fontStyle: theme.titleMedium.fontStyle,
                    ),
                    color: const Color(0xFF2C2F5B),
                    letterSpacing: 0.0,
                    fontWeight: FontWeight.w700,
                    fontStyle: theme.titleMedium.fontStyle,
                  ),
                ),
                const SizedBox(height: 4.0),
                SizedBox(
                  height: 18.0,
                  child: ClipRect(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Row(
                        children: [
                          _buildMessageSequence(theme, key: _sequenceKey),
                          _buildMessageSequence(theme),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
