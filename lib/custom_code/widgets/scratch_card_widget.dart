// Automatic FlutterFlow imports
// Imports other custom widgets
// Imports custom actions
// Imports custom functions
import 'package:flutter/material.dart';
// Begin custom widget code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:scratcher/scratcher.dart';

class ScratchCardWidget extends StatefulWidget {
  const ScratchCardWidget({
    super.key,
    this.width,
    this.height,
    required this.hiddenContent,
    required this.rewardText,
    required this.rewardTextBonus,
    required this.rewardImageUrl,
    required this.setCardRevealed,
    this.onScratchStart,
    this.onScratchEnd,
  });

  final double? width;
  final double? height;
  final String hiddenContent;
  final String rewardText;
  final String rewardTextBonus;
  final String rewardImageUrl;
  final Function() setCardRevealed;
  final VoidCallback? onScratchStart;
  final VoidCallback? onScratchEnd;

  @override
  State<ScratchCardWidget> createState() => _ScratchCardWidgetState();
}

class _ScratchCardWidgetState extends State<ScratchCardWidget> {
  bool _isRevealed = false;
  bool _hasScratchStarted = false;
  bool _hasReachedThreshold = false;

  void _logScratchTrace(String stage, {String? detail}) {
    final message = StringBuffer('[SCRATCH_CARD_TRACE] ')
      ..write('stage=$stage ')
      ..write('state=${identityHashCode(this)} ')
      ..write('mounted=$mounted ')
      ..write('revealed=$_isRevealed ')
      ..write('scratchStarted=$_hasScratchStarted ')
      ..write('thresholdReached=$_hasReachedThreshold ');
    if (detail != null && detail.isNotEmpty) {
      message.write(detail);
    }
    debugPrint(message.toString());
  }

  void _revealCardIfNeeded() {
    _logScratchTrace('reveal_if_needed_enter');
    if (!_hasScratchStarted || !_hasReachedThreshold || _isRevealed) {
      _logScratchTrace(
        'reveal_if_needed_skipped',
        detail:
            'reason=${!_hasScratchStarted ? 'scratch_not_started' : !_hasReachedThreshold ? 'threshold_not_reached' : 'already_revealed'}',
      );
      return;
    }

    setState(() {
      _isRevealed = true;
    });
    _logScratchTrace('reveal_if_needed_after_setState');
    widget.setCardRevealed();
    _logScratchTrace('reveal_if_needed_after_callback');
  }

  @override
  void initState() {
    super.initState();
    _logScratchTrace(
      'initState',
      detail:
          'imageUrl=${widget.rewardImageUrl} hiddenContent=${widget.hiddenContent} rewardText=${widget.rewardText} hasBonus=${widget.rewardTextBonus.isNotEmpty}',
    );
  }

  @override
  void didUpdateWidget(covariant ScratchCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _logScratchTrace(
      'didUpdateWidget',
      detail:
          'imageChanged=${oldWidget.rewardImageUrl != widget.rewardImageUrl} hiddenChanged=${oldWidget.hiddenContent != widget.hiddenContent} rewardChanged=${oldWidget.rewardText != widget.rewardText}',
    );
  }

  @override
  void dispose() {
    _logScratchTrace('dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _logScratchTrace('build');
    return GestureDetector(
      child: Scratcher(
        brushSize: 60.0,
        threshold: 50.0,
        image: Image.network(
          widget.rewardImageUrl,
          fit: BoxFit.cover,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            _logScratchTrace(
              'image_frameBuilder',
              detail:
                  'frame=$frame sync=$wasSynchronouslyLoaded childHash=${identityHashCode(child)}',
            );
            return child;
          },
          loadingBuilder: (context, child, loadingProgress) {
            _logScratchTrace(
              'image_loadingBuilder',
              detail:
                  'loading=${loadingProgress != null} cumulativeBytes=${loadingProgress?.cumulativeBytesLoaded} expectedBytes=${loadingProgress?.expectedTotalBytes}',
            );
            return child;
          },
          errorBuilder: (context, error, stackTrace) {
            _logScratchTrace(
              'image_errorBuilder',
              detail: 'error=$error stack=$stackTrace',
            );
            return Container(color: const Color(0xFFEDEDED));
          },
        ),
        onThreshold: () {
          _logScratchTrace('onThreshold_before');
          if (!_hasScratchStarted) {
            _logScratchTrace(
              'onThreshold_ignored',
              detail: 'reason=scratch_not_started',
            );
            return;
          }
          _hasReachedThreshold = true;
          _logScratchTrace('onThreshold_after');
        },
        onScratchStart: () {
          _logScratchTrace('onScratchStart_before');
          if (!_hasScratchStarted) {
            setState(() {
              _hasScratchStarted = true;
            });
            _logScratchTrace('onScratchStart_after_setState');
          }
          widget.onScratchStart?.call();
          _logScratchTrace('onScratchStart_after_callback');
        },
        onScratchEnd: () {
          _logScratchTrace('onScratchEnd_before');
          _revealCardIfNeeded();
          widget.onScratchEnd?.call();
          _logScratchTrace('onScratchEnd_after_callback');
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _isRevealed ? widget.rewardText : widget.hiddenContent,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              if (_isRevealed && widget.rewardTextBonus.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  widget.rewardTextBonus,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.normal,
                    color: Colors.green,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
