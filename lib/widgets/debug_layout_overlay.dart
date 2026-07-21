import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DebugLayoutOverlay extends StatefulWidget {
  const DebugLayoutOverlay({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<DebugLayoutOverlay> createState() => _DebugLayoutOverlayState();
}

class _DebugLayoutOverlayState extends State<DebugLayoutOverlay> {
  static final ValueNotifier<bool> _enabled = ValueNotifier<bool>(false);
  static final ValueNotifier<String?> _lastOverflow = ValueNotifier<String?>(
    null,
  );
  static FlutterExceptionHandler? _previousOnError;
  static bool _errorHookInstalled = false;

  @override
  void initState() {
    super.initState();
    _installErrorHookIfNeeded();
  }

  static void _installErrorHookIfNeeded() {
    assert(() {
      if (_errorHookInstalled) {
        return true;
      }

      _previousOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (!_enabled.value) {
          _previousOnError?.call(details);
          return;
        }
        final message = details.exceptionAsString();
        if (message.contains('A RenderFlex overflowed') ||
            message.toLowerCase().contains('overflowed by')) {
          _lastOverflow.value = message;
        }
        _previousOnError?.call(details);
      };
      _errorHookInstalled = true;
      return true;
    }());
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return widget.child;
    }

    return Stack(
      children: [
        widget.child,
        Positioned(
          right: 12.0,
          bottom: 12.0,
          child: SafeArea(
            top: false,
            left: false,
            child: ValueListenableBuilder<bool>(
              valueListenable: _enabled,
              builder: (context, enabled, _) {
                return FloatingActionButton.small(
                  heroTag: 'debug-layout-toggle',
                  backgroundColor: enabled
                      ? const Color(0xFFC0392B)
                      : Colors.black.withValues(alpha: 0.68),
                  onPressed: () => _enabled.value = !enabled,
                  child: const Icon(Icons.fit_screen_outlined),
                );
              },
            ),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _enabled,
          builder: (context, enabled, _) {
            if (!enabled) {
              return const SizedBox.shrink();
            }

            final mediaQuery = MediaQuery.of(context);
            final topInset = mediaQuery.viewPadding.top;
            final bottomInset = mediaQuery.viewPadding.bottom;
            final keyboardInset = mediaQuery.viewInsets.bottom;

            return IgnorePointer(
              ignoring: true,
              child: Stack(
                children: [
                  if (topInset > 0)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: topInset,
                      child: Container(color: const Color(0x33FF9800)),
                    ),
                  if (bottomInset > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: keyboardInset,
                      height: bottomInset,
                      child: Container(color: const Color(0x334CAF50)),
                    ),
                  if (keyboardInset > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: keyboardInset,
                      child: Container(color: const Color(0x334296F3)),
                    ),
                  Positioned(
                    top: topInset + 8.0,
                    left: 8.0,
                    right: 8.0,
                    child: SafeArea(
                      bottom: false,
                      child: ValueListenableBuilder<String?>(
                        valueListenable: _lastOverflow,
                        builder: (context, overflow, __) {
                          final screenSize = mediaQuery.size;
                          final lines = <String>[
                            'screen ${screenSize.width.toStringAsFixed(0)} x ${screenSize.height.toStringAsFixed(0)}',
                            'safe top ${topInset.toStringAsFixed(0)} / bottom ${bottomInset.toStringAsFixed(0)}',
                            'keyboard ${keyboardInset.toStringAsFixed(0)} / text ${mediaQuery.textScaler.scale(1).toStringAsFixed(2)}x',
                            if (overflow != null) overflow,
                          ];

                          return DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(14.0),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Text(
                                lines.join('\n'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.0,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
