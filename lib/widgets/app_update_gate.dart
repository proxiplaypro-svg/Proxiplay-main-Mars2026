import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import '/services/app_update_service.dart';

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  bool _isChecking = false;
  bool _isDialogVisible = false;
  
  bool _hasCheckedOnce = false;

  @override
  void initState() {
    super.initState();
    debugPrint('🔥 AppUpdateGate initState');
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runUpdateCheck(trigger: 'startup');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _hasCheckedOnce) {
      _runUpdateCheck(trigger: 'resume');
    }
  }

  Future<void> _runUpdateCheck({required String trigger}) async {
    debugPrint('🔥 _runUpdateCheck lance trigger=$trigger');
    if (!mounted || _isChecking || _isDialogVisible) {
      return;
    }

    _isChecking = true;
    _hasCheckedOnce = true;
    try {
      final result = await AppUpdateService.instance.checkForUpdate();

      debugPrint(
        '[AppUpdateGate] trigger=$trigger status=${result.status.name} '
        'showDialog=${result.shouldShowDialog} reason=${result.debugReason}',
      );

      if (!mounted || !result.shouldShowDialog) {
        return;
      }

      print('APP_UPDATE_SHOW_DIALOG');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showUpdateDialog(result);
      });
    } catch (error, stackTrace) {
      debugPrint('[AppUpdateGate] erreur=$error');
      debugPrint('[AppUpdateGate] stack=$stackTrace');
    } finally {
      _isChecking = false;
    }
  }

  Future<void> _showUpdateDialog(AppUpdateCheckResult result) async {
    if (result.isRequired) {
      await _showRequiredUpdateDialog(result);
      return;
    }

    if (result.isOptional) {
      await _showOptionalUpdateDialog(result);
    }
  }

  Future<void> _showRequiredUpdateDialog(AppUpdateCheckResult result) async {
    _isDialogVisible = true;
    try {
      debugPrint('[AppUpdateGate] popup_affichee type=required');
      print('APP_UPDATE_DIALOG_OPEN required');
      final navigatorContext = widget.navigatorKey.currentContext;
      if (navigatorContext == null) {
        return;
      }
      await showDialog<void>(
        context: navigatorContext,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: _AppUpdateDialog(
            title: result.title ?? 'Mise à jour requise',
            message: result.message ??
                'Votre version de Proxiplay n’est plus compatible. Veuillez mettre à jour l’application pour continuer.',
            isRequired: true,
            onUpdatePressed: () async {
              final opened = await _openUpdate(result);
              if (!opened && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Impossible d’ouvrir le store pour le moment.',
                    ),
                  ),
                );
              }
            },
          ),
        ),
      );
    } finally {
      _isDialogVisible = false;
    }
  }

  Future<void> _showOptionalUpdateDialog(AppUpdateCheckResult result) async {
    _isDialogVisible = true;
    try {
      debugPrint('[AppUpdateGate] popup_affichee type=optional');
      print('APP_UPDATE_DIALOG_OPEN optional');
      final navigatorContext = widget.navigatorKey.currentContext;
      if (navigatorContext == null) {
        return;
      }
      await showDialog<void>(
        context: navigatorContext,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (context) => _AppUpdateDialog(
          title: result.title ?? 'Mise à jour disponible',
          message: result.message ??
              'Une nouvelle version de Proxiplay est disponible.',
          isRequired: false,
          onUpdatePressed: () async {
            final opened = await _openUpdate(result);
            if (context.mounted) {
              Navigator.of(context).pop();
            }
            if (!opened && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Impossible d’ouvrir le store pour le moment.',
                  ),
                ),
              );
            }
          },
          onLaterPressed: () async {
            await AppUpdateService.instance.markOptionalUpdateDismissed(
              latestVersion: result.latestVersion ?? '',
            );
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
      );
    } finally {
      _isDialogVisible = false;
    }
  }

  Future<bool> _openUpdate(AppUpdateCheckResult result) async {
    final launchedNative =
        await AppUpdateService.instance.tryStartNativeUpdate(result);
    if (launchedNative) {
      return true;
    }
    return AppUpdateService.instance.openStore(result);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AppUpdateDialog extends StatefulWidget {
  const _AppUpdateDialog({
    required this.title,
    required this.message,
    required this.isRequired,
    required this.onUpdatePressed,
    this.onLaterPressed,
  });

  final String title;
  final String message;
  final bool isRequired;
  final Future<void> Function() onUpdatePressed;
  final Future<void> Function()? onLaterPressed;

  @override
  State<_AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<_AppUpdateDialog> {
  bool _isSubmitting = false;

  Future<void> _handleUpdatePressed() async {
    if (_isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await widget.onUpdatePressed();
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24.0),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52.0,
              height: 52.0,
              decoration: BoxDecoration(
                color: widget.isRequired
                    ? const Color(0xFFFFF1F2)
                    : const Color(0xFFF4F1FF),
                borderRadius: BorderRadius.circular(16.0),
              ),
              alignment: Alignment.center,
              child: Icon(
                widget.isRequired
                    ? Icons.system_update_alt_rounded
                    : Icons.system_update_rounded,
                color: theme.primary,
                size: 28.0,
              ),
            ),
            const SizedBox(height: 18.0),
            Text(
              widget.title,
              style: GoogleFonts.inter(
                fontSize: 22.0,
                fontWeight: FontWeight.w700,
                color: theme.primaryText,
              ),
            ),
            const SizedBox(height: 10.0),
            Text(
              widget.message,
              style: GoogleFonts.inter(
                fontSize: 14.0,
                fontWeight: FontWeight.w500,
                color: theme.secondaryText,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24.0),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _handleUpdatePressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0.0,
                  padding: const EdgeInsets.symmetric(vertical: 14.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14.0),
                  ),
                ),
                child: Text(
                  'Mettre à jour',
                  style: GoogleFonts.inter(
                    fontSize: 15.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (!widget.isRequired) ...[
              const SizedBox(height: 10.0),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _isSubmitting ? null : widget.onLaterPressed,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.secondaryText,
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.0),
                    ),
                  ),
                  child: Text(
                    'Plus tard',
                    style: GoogleFonts.inter(
                      fontSize: 14.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
