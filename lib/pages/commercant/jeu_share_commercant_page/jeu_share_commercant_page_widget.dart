import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import '/backend/backend.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/utils/share_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class JeuShareCommercantPageWidget extends StatefulWidget {
  const JeuShareCommercantPageWidget({
    super.key,
    required this.gameId,
    this.initialGame,
  });

  final String? gameId;
  final GamesRecord? initialGame;

  static String routeName = 'JeuShareCommercantPage';
  static String routePath = 'commercant/game-share/:gameId';

  @override
  State<JeuShareCommercantPageWidget> createState() =>
      _JeuShareCommercantPageWidgetState();
}

class _JeuShareCommercantPageWidgetState
    extends State<JeuShareCommercantPageWidget> {
  static const MethodChannel _mediaChannel = MethodChannel('proxiplay/media');

  final GlobalKey _qrBoundaryKey = GlobalKey();
  bool _isSharing = false;
  bool _isDownloadingQr = false;
  bool _isSharingPoster = false;
  bool _isDownloadingPoster = false;
  bool _isDownloadingFacebookVisual = false;
  OverlayEntry? _toastEntry;
  Timer? _toastTimer;

  String get _gameId => (widget.gameId ?? '').trim();

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    _toastTimer?.cancel();
    _toastEntry?.remove();

    final overlay = Overlay.of(context, rootOverlay: true);
    _toastEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: 20.0,
        right: 20.0,
        bottom: 28.0,
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: SafeArea(
              top: false,
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 520.0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xEE1F1F1F),
                    borderRadius: BorderRadius.circular(14.0),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 14.0,
                        offset: Offset(0.0, 6.0),
                      ),
                    ],
                  ),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: FlutterFlowTheme.of(context).bodyMedium.override(
                          font: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontStyle: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .fontStyle,
                          ),
                          color: Colors.white,
                          letterSpacing: 0.0,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_toastEntry!);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      _toastEntry?.remove();
      _toastEntry = null;
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _toastEntry?.remove();
    super.dispose();
  }

  String _buildReadyToPostText({
    required String enseigneName,
    required String qrLink,
  }) {
    return '🎁 Un jeu vous attend chez $enseigneName !\n\n'
        'Scannez le QR code en boutique ou cliquez ici :\n'
        '$qrLink\n\n'
        'À vous de jouer sur Proxiplay.';
  }

  // ignore: unused_element
  String _buildFacebookPostText({
    required GamesRecord game,
    required String enseigneName,
    required String gameLink,
  }) {
    final merchantHashtag = enseigneName.replaceAll(RegExp(r'\s+'), '');
    final endDate = game.endDate != null
        ? dateTimeFormat(
            'd MMMM y',
            game.endDate,
            locale: FFLocalizations.of(context).languageCode,
          )
        : 'bientôt';

    return '🎉 $enseigneName vous offre une chance de gagner !\n\n'
        '🎁 ${game.name}\n'
        '📍 Rendez-vous chez $enseigneName\n'
        '📱 Scannez le QR code sur place et tentez votre chance !\n'
        '🆓 C\'est 100% gratuit\n'
        '⏰ Jusqu\'au $endDate\n'
        '🔗 $gameLink\n\n'
        '#Proxiplay #Dunkerque #$merchantHashtag #JeuGratuit #BonPlan';
  }

  // ignore: unused_element
  String _buildFacebookVisualFooter(String enseigneName) {
    const fallback = 'votre enseigne';
    final trimmed = enseigneName.trim().isEmpty ? fallback : enseigneName.trim();
    final truncated =
        trimmed.length > 25 ? '${trimmed.substring(0, 25)}...' : trimmed;
    return 'Chez $truncated • Gratuit • Jouez sur ProxiPlay';
  }

  String _buildNeutralFacebookPostText({
    required GamesRecord game,
    required String enseigneName,
    required String gameLink,
  }) {
    final merchantHashtag = enseigneName.replaceAll(RegExp(r'\s+'), '');
    final endDate = game.endDate != null
        ? dateTimeFormat(
            'd MMMM y',
            game.endDate,
            locale: FFLocalizations.of(context).languageCode,
          )
        : 'bientot';
    final description = game.description.trim().isEmpty
        ? 'Jouez gratuitement sur ProxiPlay.'
        : game.description.trim();
    final legalMessage = _buildAlcoholLegalMessage(game);
    final legalBlock = legalMessage != null ? '\n\n$legalMessage' : '';

    return '🎉 $enseigneName vous propose un jeu gratuit sur ProxiPlay !\n\n'
        '🎁 A gagner : ${game.name}\n\n'
        '📝 $description\n'
        '📅 Jusqu\'au $endDate\n\n'
        '📱 Jouez gratuitement sur ProxiPlay :\n'
        '🔗 $gameLink'
        '$legalBlock\n\n'
        '#Proxiplay #$merchantHashtag #JeuGratuit #BonPlan';
  }

  String? _buildAlcoholLegalMessage(GamesRecord game) {
    final source = '${game.name} ${game.description}'.toLowerCase();
    final alcoholPattern = RegExp(
      r'alcool|champagne|vin|biere|bière|whisky|rhum|vodka|gin|cidre|liqueur|aperitif|apéritif|spiritueux',
    );
    if (!alcoholPattern.hasMatch(source)) {
      return null;
    }
    return '⚠️ L\'abus d\'alcool est dangereux pour la santé. A consommer avec modération.';
  }

  String _buildNeutralFacebookVisualFooter(String enseigneName) {
    const fallback = 'votre enseigne';
    final trimmed = enseigneName.trim().isEmpty ? fallback : enseigneName.trim();
    final truncated =
        trimmed.length > 25 ? '${trimmed.substring(0, 25)}...' : trimmed;
    return '$truncated • Jeu gratuit • ProxiPlay';
  }

  Future<void> _copyText(
    String text, {
    required String successMessage,
  }) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      _showSnackBar(successMessage);
    } catch (_) {
      _showSnackBar('Impossible de copier.');
    }
  }

  Future<void> _shareText(String text) async {
    if (_isSharing) {
      return;
    }
    setState(() => _isSharing = true);
    try {
      await Share.share(text);
    } catch (_) {
      _showSnackBar('Le partage n’a pas pu être ouvert.');
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  // ignore: unused_element
  Future<void> _shareToFacebook(String qrLink) async {
    final facebookUri = Uri.https(
      'www.facebook.com',
      '/sharer/sharer.php',
      {'u': qrLink},
    );
    try {
      final opened = await launchUrl(
        facebookUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        _showSnackBar('Le partage n’a pas pu être ouvert.');
      }
    } catch (_) {
      _showSnackBar('Le partage n’a pas pu être ouvert.');
    }
  }

  Future<void> _shareToWhatsApp(String text) async {
    final whatsappUri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(text)}',
    );
    try {
      final opened = await launchUrl(
        whatsappUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        await _shareText(text);
      }
    } catch (_) {
      await _shareText(text);
    }
  }

  Future<File> _captureBoundaryToPng({
    required GlobalKey boundaryKey,
    required String fileName,
  }) async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('Boundary unavailable.');
    }

    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('PNG bytes unavailable.');
    }

    final Directory tempDir = await getTemporaryDirectory();
    final File file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    return file;
  }

  Future<void> _saveImageInGallery({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      throw UnsupportedError('Gallery save unavailable on this platform.');
    }

    await _mediaChannel.invokeMethod<String>(
      'saveImageToGallery',
      <String, dynamic>{
        'bytes': bytes,
        'fileName': fileName,
      },
    );
  }

  Future<void> _downloadQrCode(String gameId) async {
    if (_isDownloadingQr) {
      return;
    }
    if (kIsWeb) {
      _showSnackBar('Téléchargement indisponible sur cet appareil.');
      return;
    }

    setState(() => _isDownloadingQr = true);
    try {
      final file = await _captureBoundaryToPng(
        boundaryKey: _qrBoundaryKey,
        fileName: 'proxiplay-qr-$gameId.png',
      );
      await _saveImageInGallery(
        bytes: await file.readAsBytes(),
        fileName: 'proxiplay-qr-$gameId.png',
      );
      _showSnackBar('QR enregistré dans vos photos ✓');
    } on UnsupportedError {
      _showSnackBar('Téléchargement indisponible sur cet appareil.');
    } catch (_) {
      _showSnackBar('Téléchargement du QR impossible.');
    } finally {
      if (mounted) {
        setState(() => _isDownloadingQr = false);
      }
    }
  }

  Future<void> _sharePoster({
    required GlobalKey posterBoundaryKey,
    required GamesRecord game,
  }) async {
    if (_isSharingPoster) {
      return;
    }
    setState(() => _isSharingPoster = true);
    try {
      final file = await _captureBoundaryToPng(
        boundaryKey: posterBoundaryKey,
        fileName: 'proxiplay-poster-${game.reference.id}.png',
      );
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'Voici le QR code du jeu ${game.name} sur Proxiplay',
        subject: 'Affiche Proxiplay',
      );
      _showSnackBar('Affiche partagée ✓');
    } catch (_) {
      _showSnackBar('Impossible de générer l’affiche.');
    } finally {
      if (mounted) {
        setState(() => _isSharingPoster = false);
      }
    }
  }

  Future<void> _downloadPoster({
    required GlobalKey posterBoundaryKey,
    required GamesRecord game,
  }) async {
    if (_isDownloadingPoster) {
      return;
    }
    if (kIsWeb) {
      _showSnackBar('Téléchargement indisponible sur cet appareil.');
      return;
    }

    setState(() => _isDownloadingPoster = true);
    try {
      final file = await _captureBoundaryToPng(
        boundaryKey: posterBoundaryKey,
        fileName: 'proxiplay-poster-${game.reference.id}.png',
      );
      await _saveImageInGallery(
        bytes: await file.readAsBytes(),
        fileName: 'proxiplay-poster-${game.reference.id}.png',
      );
      _showSnackBar('Affiche enregistrée dans vos photos ✓');
    } on UnsupportedError {
      _showSnackBar('Téléchargement indisponible sur cet appareil.');
    } catch (_) {
      _showSnackBar('Impossible de générer l’affiche.');
    } finally {
      if (mounted) {
        setState(() => _isDownloadingPoster = false);
      }
    }
  }

  Future<void> _downloadFacebookVisual({
    required GlobalKey visualBoundaryKey,
    required GamesRecord game,
  }) async {
    if (_isDownloadingFacebookVisual) {
      return;
    }
    if (kIsWeb) {
      _showSnackBar('Téléchargement indisponible sur cet appareil.');
      return;
    }

    setState(() => _isDownloadingFacebookVisual = true);
    try {
      final file = await _captureBoundaryToPng(
        boundaryKey: visualBoundaryKey,
        fileName: 'facebook-${game.reference.id}.png',
      );
      await _saveImageInGallery(
        bytes: await file.readAsBytes(),
        fileName: 'facebook-${game.reference.id}.png',
      );
      _showSnackBar('Visuel Facebook enregistré dans vos photos ✓');
    } on UnsupportedError {
      _showSnackBar('Téléchargement indisponible sur cet appareil.');
    } catch (_) {
      _showSnackBar('Impossible de générer le visuel Facebook.');
    } finally {
      if (mounted) {
        setState(() => _isDownloadingFacebookVisual = false);
      }
    }
  }

  Future<void> _showFacebookPostDialog({
    required GamesRecord game,
    required String enseigneName,
    required String gameLink,
  }) async {
    final facebookText = _buildNeutralFacebookPostText(
      game: game,
      enseigneName: enseigneName,
      gameLink: gameLink,
    );
    final GlobalKey visualBoundaryKey = GlobalKey();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 20.0,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).secondaryBackground,
              borderRadius: BorderRadius.circular(24.0),
            ),
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle(
                    'Créer le post Facebook',
                    subtitle:
                        'Copiez le texte puis ajoutez le visuel manuellement sur Facebook.',
                  ),
                  const SizedBox(height: 16.0),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: FlutterFlowTheme.of(context).primaryBackground,
                      borderRadius: BorderRadius.circular(18.0),
                    ),
                    child: SelectableText(
                      facebookText,
                      style: FlutterFlowTheme.of(context).bodyMedium.override(
                            font: GoogleFonts.inter(
                              fontWeight: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .fontWeight,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .fontStyle,
                            ),
                            letterSpacing: 0.0,
                          ),
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  _buildSecondaryButton(
                    label: 'Copier le texte',
                    icon: Icons.content_copy_rounded,
                    onPressed: () => _copyText(
                      facebookText,
                      successMessage: 'Texte Facebook copié ✓',
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  RepaintBoundary(
                    key: visualBoundaryKey,
                    child: FacebookPostVisualPreview(
                      gameName: game.name,
                      enseigneName: enseigneName,
                      imageUrl: game.photo,
                      endDateLabel: game.endDate != null
                          ? dateTimeFormat(
                              'd/MM/y',
                              game.endDate,
                              locale: FFLocalizations.of(context).languageCode,
                            )
                          : 'bientôt',
                      footerLine: _buildNeutralFacebookVisualFooter(enseigneName),
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  _buildPrimaryButton(
                    label: _isDownloadingFacebookVisual
                        ? 'Téléchargement du visuel...'
                        : 'Télécharger le visuel',
                    icon: Icons.download_rounded,
                    isLoading: _isDownloadingFacebookVisual,
                    onPressed: () => _downloadFacebookVisual(
                      visualBoundaryKey: visualBoundaryKey,
                      game: game,
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  _buildSecondaryButton(
                    label: 'Fermer',
                    icon: Icons.close_rounded,
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showPosterPreview({
    required GamesRecord game,
    required String qrLink,
  }) async {
    final GlobalKey posterBoundaryKey = GlobalKey();
    // ignore: unused_local_variable
    final enseigneName =
        game.enseigneName.isNotEmpty ? game.enseigneName : 'votre enseigne';

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 20.0,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).secondaryBackground,
              borderRadius: BorderRadius.circular(24.0),
            ),
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final previewWidth =
                          constraints.maxWidth.clamp(220.0, 420.0).toDouble();
                      final previewHeight =
                          MediaQuery.sizeOf(context).height * 0.48;
                      return Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: previewWidth,
                            maxHeight: previewHeight,
                          ),
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: RepaintBoundary(
                              key: posterBoundaryKey,
                              child: GamePosterPreview(
                                game: game,
                                qrLink: qrLink,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16.0),
                  _buildPrimaryButton(
                    label: _isSharingPoster
                        ? 'Partage de l’affiche...'
                        : 'Partager l’affiche',
                    icon: Icons.share_rounded,
                    isLoading: _isSharingPoster,
                    onPressed: () => _sharePoster(
                      posterBoundaryKey: posterBoundaryKey,
                      game: game,
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  _buildSecondaryButton(
                    label: _isDownloadingPoster
                        ? 'Téléchargement de l’affiche...'
                        : 'Télécharger l’affiche',
                    icon: Icons.download_rounded,
                    isLoading: _isDownloadingPoster,
                    onPressed: () => _downloadPoster(
                      posterBoundaryKey: posterBoundaryKey,
                      game: game,
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  _buildSecondaryButton(
                    label: 'Fermer',
                    icon: Icons.close_rounded,
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openGameDetails(GamesRecord game) async {
    if (game.enseigneId == null) {
      return;
    }
    final enseigne = await EnseignesRecord.getDocumentOnce(game.enseigneId!);
    if (!mounted) {
      return;
    }
    context.pushNamed(
      JeuDetailCommercantPageWidget.routeName,
      queryParameters: {
        'gameDoc': serializeParam(game, ParamType.Document),
        'enseigneDoc': serializeParam(enseigne, ParamType.Document),
      }.withoutNulls,
      extra: <String, dynamic>{
        'gameDoc': game,
        'enseigneDoc': enseigne,
      },
    );
  }

  Widget _buildCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(20.0),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(24.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0E1220),
            blurRadius: 16.0,
            offset: Offset(0.0, 6.0),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionTitle(String title, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: FlutterFlowTheme.of(context).titleLarge.override(
                font: GoogleFonts.interTight(
                  fontWeight: FontWeight.w700,
                  fontStyle: FlutterFlowTheme.of(context).titleLarge.fontStyle,
                ),
                letterSpacing: 0.0,
                fontWeight: FontWeight.w700,
              ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6.0),
          Text(
            subtitle,
            style: FlutterFlowTheme.of(context).bodyMedium.override(
                  font: GoogleFonts.inter(
                    fontWeight:
                        FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                    fontStyle:
                        FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                  ),
                  color: FlutterFlowTheme.of(context).secondaryText,
                  letterSpacing: 0.0,
                ),
          ),
        ],
      ],
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required Future<void> Function() onPressed,
    IconData? icon,
    bool isLoading = false,
    Color? backgroundColor,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : () async => onPressed(),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              backgroundColor ?? FlutterFlowTheme.of(context).primary,
          foregroundColor: Colors.white,
          elevation: 0.0,
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18.0),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 18.0,
                height: 18.0,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            else if (icon != null) ...[
              Icon(icon, size: 18.0),
              const SizedBox(width: 8.0),
            ],
            Flexible(child: Text(label, textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondaryButton({
    required String label,
    required Future<void> Function() onPressed,
    IconData? icon,
    bool isLoading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: isLoading ? null : () async => onPressed(),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 15.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18.0),
          ),
          side: BorderSide(
            color: FlutterFlowTheme.of(context).alternate,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(
                width: 18.0,
                height: 18.0,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: FlutterFlowTheme.of(context).primary,
                ),
              )
            else if (icon != null) ...[
              Icon(icon, size: 18.0),
              const SizedBox(width: 8.0),
            ],
            Flexible(child: Text(label, textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialButton({
    required IconData icon,
    required String label,
    required Future<void> Function() onPressed,
    bool isPrimary = false,
    Color? backgroundColor,
    Color? foregroundColor,
    Color? borderColor,
  }) {
    final resolvedIsPrimary =
        isPrimary || label.toLowerCase().contains('facebook');
    final resolvedBackgroundColor = backgroundColor ??
        (resolvedIsPrimary ? const Color(0xFF1877F2) : Colors.transparent);
    final resolvedForegroundColor = foregroundColor ??
        (resolvedIsPrimary
            ? Colors.white
            : FlutterFlowTheme.of(context).primaryText);
    final resolvedBorderColor = borderColor ??
        (resolvedIsPrimary
            ? const Color(0xFF1877F2)
            : FlutterFlowTheme.of(context).alternate);

    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () async => onPressed(),
        icon: Icon(
          icon,
          size: 18.0,
          color: resolvedForegroundColor,
        ),
        label: Text(
          label,
          textAlign: TextAlign.center,
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: resolvedBackgroundColor,
          foregroundColor: resolvedForegroundColor,
          padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 10.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          side: BorderSide(
            color: resolvedBorderColor,
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    return _buildCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56.0,
            height: 56.0,
            decoration: BoxDecoration(
              color: const Color(0x14A0134D),
              borderRadius: BorderRadius.circular(18.0),
            ),
            child: Icon(
              Icons.redeem_rounded,
              color: FlutterFlowTheme.of(context).primary,
              size: 28.0,
            ),
          ),
          const SizedBox(width: 16.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Votre jeu est prêt',
                  style: FlutterFlowTheme.of(context).headlineSmall.override(
                        font: GoogleFonts.interTight(
                          fontWeight: FontWeight.w700,
                          fontStyle: FlutterFlowTheme.of(context)
                              .headlineSmall
                              .fontStyle,
                        ),
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8.0),
                Text(
                  'Invitez vos clients à y participer !',
                  style: FlutterFlowTheme.of(context).bodyLarge.override(
                        font: GoogleFonts.inter(
                          fontWeight:
                              FlutterFlowTheme.of(context).bodyLarge.fontWeight,
                          fontStyle:
                              FlutterFlowTheme.of(context).bodyLarge.fontStyle,
                        ),
                        letterSpacing: 0.0,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildQrSection({
    required GamesRecord game,
    required String qrLink,
    required String shareText,
  }) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            'Partage immédiat',
            subtitle:
                'Commencez par votre affiche, puis partagez le QR code si besoin.',
          ),
          const SizedBox(height: 20.0),
          _buildPrimaryButton(
            label: 'Créer le post Facebook',
            icon: Icons.facebook_rounded,
            backgroundColor: const Color(0xFF1877F2),
            onPressed: () => _showFacebookPostDialog(
              game: game,
              enseigneName: game.enseigneName.trim().isEmpty
                  ? 'votre enseigne'
                  : game.enseigneName.trim(),
              gameLink: buildGameQrLink(game.reference.id),
            ),
          ),
          const SizedBox(height: 12.0),
          _buildPrimaryButton(
            label: 'Générer une affiche',
            icon: Icons.auto_awesome_rounded,
            onPressed: () => _showPosterPreview(
              game: game,
              qrLink: qrLink,
            ),
          ),
          const SizedBox(height: 12.0),
          _buildSecondaryButton(
            label: _isSharing ? 'Ouverture du partage...' : 'Partager le jeu',
            icon: Icons.share_rounded,
            isLoading: _isSharing,
            onPressed: () => _shareText(shareText),
          ),
          const SizedBox(height: 18.0),
          Center(
            child: RepaintBoundary(
              key: _qrBoundaryKey,
              child: Container(
                padding: const EdgeInsets.all(18.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28.0),
                ),
                child: QrImageView(
                  data: qrLink,
                  version: QrVersions.auto,
                  size: 248.0,
                  gapless: false,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12.0),
          _buildPrimaryButton(
            label: 'Générer une affiche',
            icon: Icons.auto_awesome_rounded,
            onPressed: () => _showPosterPreview(
              game: game,
              qrLink: qrLink,
            ),
          ),
          const SizedBox(height: 12.0),
          _buildSecondaryButton(
            label: 'Copier le lien',
            icon: Icons.link_rounded,
            onPressed: () => _copyText(
              qrLink,
              successMessage: 'Lien copié ✓',
            ),
          ),
          const SizedBox(height: 12.0),
          _buildSecondaryButton(
            label: _isDownloadingQr
                ? 'Téléchargement du QR...'
                : 'Télécharger le QR',
            icon: Icons.download_rounded,
            isLoading: _isDownloadingQr,
            onPressed: () => _downloadQrCode(game.reference.id),
          ),
        ],
      ),
    );
  }

  Widget _buildTextSection(String readyText) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Texte prêt à publier'),
          const SizedBox(height: 16.0),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).primaryBackground,
              borderRadius: BorderRadius.circular(18.0),
            ),
            child: SelectableText(
              readyText,
              style: FlutterFlowTheme.of(context).bodyMedium.override(
                    font: GoogleFonts.inter(
                      fontWeight:
                          FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                      fontStyle:
                          FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                    ),
                    letterSpacing: 0.0,
                  ),
            ),
          ),
          const SizedBox(height: 16.0),
          _buildSecondaryButton(
            label: 'Copier le texte',
            icon: Icons.content_copy_rounded,
            onPressed: () => _copyText(
              readyText,
              successMessage: 'Texte prêt à publier copié ✓',
            ),
          ),
          const SizedBox(height: 12.0),
          _buildSecondaryButton(
            label: 'Partager ce texte',
            icon: Icons.send_rounded,
            onPressed: () => _shareText(readyText),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildSocialSection({
    required GamesRecord game,
    required String enseigneName,
    required String qrLink,
    required String readyText,
  }) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            'Publier sur vos réseaux',
            subtitle:
                'Choisissez le canal le plus rapide pour faire venir vos clients.',
          ),
          const SizedBox(height: 16.0),
          Row(
            children: [
              _buildSocialButton(
                icon: Icons.auto_awesome_rounded,
                label: 'Générer une affiche',
                onPressed: () => _showPosterPreview(
                  game: game,
                  qrLink: qrLink,
                ),
              ),
              const SizedBox(width: 10.0),
              _buildSocialButton(
                icon: Icons.send_rounded,
                label: 'Partager le texte',
                onPressed: () => _shareText(readyText),
              ),
            ],
          ),
          const SizedBox(height: 14.0),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).primaryBackground,
              borderRadius: BorderRadius.circular(18.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Instagram',
                  style: FlutterFlowTheme.of(context).titleMedium.override(
                        font: GoogleFonts.interTight(
                          fontWeight: FontWeight.w700,
                          fontStyle:
                              FlutterFlowTheme.of(context).titleMedium.fontStyle,
                        ),
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8.0),
                Text(
                  'Instagram ne permet pas de préremplir automatiquement une publication. Copiez le texte, ajoutez le QR code en image, puis publiez en story ou en post.',
                  style: FlutterFlowTheme.of(context).bodyMedium.override(
                        font: GoogleFonts.inter(
                          fontWeight:
                              FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                          fontStyle:
                              FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                        ),
                        letterSpacing: 0.0,
                      ),
                ),
                const SizedBox(height: 14.0),
                _buildSecondaryButton(
                  label: 'Copier pour Instagram',
                  icon: Icons.camera_alt_outlined,
                  onPressed: () => _copyText(
                    readyText,
                    successMessage: 'Texte prêt à publier copié ✓',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14.0),
          Row(
            children: [
              _buildSocialButton(
                icon: Icons.message_rounded,
                label: 'Partager sur WhatsApp',
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                borderColor: const Color(0xFF25D366),
                onPressed: () => _shareToWhatsApp(readyText),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQrSectionOrdered({
    required GamesRecord game,
    required String qrLink,
    required String shareText,
  }) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            'Partage immédiat',
            subtitle:
                'Commencez par les actions les plus utiles, puis utilisez le QR code si besoin.',
          ),
          const SizedBox(height: 20.0),
          _buildPrimaryButton(
            label: 'Créer le post Facebook',
            icon: Icons.facebook_rounded,
            backgroundColor: const Color(0xFF1877F2),
            onPressed: () => _showFacebookPostDialog(
              game: game,
              enseigneName: game.enseigneName.trim().isEmpty
                  ? 'votre enseigne'
                  : game.enseigneName.trim(),
              gameLink: buildGameQrLink(game.reference.id),
            ),
          ),
          const SizedBox(height: 12.0),
          _buildPrimaryButton(
            label: 'Générer une affiche',
            icon: Icons.auto_awesome_rounded,
            onPressed: () => _showPosterPreview(
              game: game,
              qrLink: qrLink,
            ),
          ),
          const SizedBox(height: 12.0),
          _buildSecondaryButton(
            label: _isSharing ? 'Ouverture du partage...' : 'Partager le jeu',
            icon: Icons.share_rounded,
            isLoading: _isSharing,
            onPressed: () => _shareText(shareText),
          ),
          const SizedBox(height: 18.0),
          Center(
            child: RepaintBoundary(
              key: _qrBoundaryKey,
              child: Container(
                padding: const EdgeInsets.all(18.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28.0),
                ),
                child: QrImageView(
                  data: qrLink,
                  version: QrVersions.auto,
                  size: 248.0,
                  gapless: false,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12.0),
          _buildSecondaryButton(
            label: _isDownloadingQr
                ? 'Téléchargement du QR...'
                : 'Télécharger le QR',
            icon: Icons.download_rounded,
            isLoading: _isDownloadingQr,
            onPressed: () => _downloadQrCode(game.reference.id),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialSectionOrdered({
    required String readyText,
  }) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            'Publier sur vos réseaux',
            subtitle:
                'Choisissez le canal le plus rapide pour faire venir vos clients.',
          ),
          const SizedBox(height: 14.0),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).primaryBackground,
              borderRadius: BorderRadius.circular(18.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Instagram',
                  style: FlutterFlowTheme.of(context).titleMedium.override(
                        font: GoogleFonts.interTight(
                          fontWeight: FontWeight.w700,
                          fontStyle:
                              FlutterFlowTheme.of(context).titleMedium.fontStyle,
                        ),
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8.0),
                Text(
                  'Instagram ne permet pas de préremplir automatiquement une publication. Copiez le texte, ajoutez le QR code en image, puis publiez en story ou en post.',
                  style: FlutterFlowTheme.of(context).bodyMedium.override(
                        font: GoogleFonts.inter(
                          fontWeight:
                              FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                          fontStyle:
                              FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                        ),
                        letterSpacing: 0.0,
                      ),
                ),
                const SizedBox(height: 14.0),
                _buildSecondaryButton(
                  label: 'Copier pour Instagram',
                  icon: Icons.camera_alt_outlined,
                  onPressed: () => _copyText(
                    readyText,
                    successMessage: 'Texte prêt à publier copié ✓',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14.0),
          Row(
            children: [
              _buildSocialButton(
                icon: Icons.message_rounded,
                label: 'Partager sur WhatsApp',
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                borderColor: const Color(0xFF25D366),
                onPressed: () => _shareToWhatsApp(readyText),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildAdviceSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('3 endroits où afficher votre QR code'),
          const SizedBox(height: 14.0),
          _buildAdviceItem('En caisse'),
          _buildAdviceItem('En vitrine'),
          _buildAdviceItem('En story Instagram / Facebook'),
        ],
      ),
    );
  }

  Widget _buildAdviceItem(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: FlutterFlowTheme.of(context).primary,
            size: 18.0,
          ),
          const SizedBox(width: 10.0),
          Expanded(
            child: Text(
              label,
              style: FlutterFlowTheme.of(context).bodyLarge.override(
                    font: GoogleFonts.inter(
                      fontWeight:
                          FlutterFlowTheme.of(context).bodyLarge.fontWeight,
                      fontStyle:
                          FlutterFlowTheme.of(context).bodyLarge.fontStyle,
                    ),
                    letterSpacing: 0.0,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gameRef = _gameId.isEmpty ? null : GamesRecord.collection.doc(_gameId);

    return Scaffold(
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      appBar: AppBar(
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        elevation: 0.0,
        centerTitle: false,
        title: Text(
          'Partage du jeu',
          style: FlutterFlowTheme.of(context).headlineSmall.override(
                font: GoogleFonts.interTight(
                  fontWeight: FontWeight.w700,
                  fontStyle:
                      FlutterFlowTheme.of(context).headlineSmall.fontStyle,
                ),
                letterSpacing: 0.0,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
      body: SafeArea(
        child: _gameId.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    'Impossible de charger ce partage pour le moment.',
                    textAlign: TextAlign.center,
                    style: FlutterFlowTheme.of(context).bodyLarge.override(
                          font: GoogleFonts.inter(
                            fontWeight:
                                FlutterFlowTheme.of(context).bodyLarge.fontWeight,
                            fontStyle:
                                FlutterFlowTheme.of(context).bodyLarge.fontStyle,
                          ),
                          letterSpacing: 0.0,
                        ),
                  ),
                ),
              )
            : StreamBuilder<DocumentSnapshot>(
                stream: gameRef?.snapshots(),
                builder: (context, snapshot) {
                  final gameDoc = snapshot.data;
                  final game = gameDoc != null && gameDoc.exists
                      ? GamesRecord.fromSnapshot(gameDoc)
                      : widget.initialGame;

                  if (snapshot.connectionState == ConnectionState.waiting &&
                      game == null) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (game == null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          'Impossible de charger ce jeu pour le moment.',
                          textAlign: TextAlign.center,
                          style: FlutterFlowTheme.of(context).bodyLarge.override(
                                font: GoogleFonts.inter(
                                  fontWeight: FlutterFlowTheme.of(context)
                                      .bodyLarge
                                      .fontWeight,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .bodyLarge
                                      .fontStyle,
                                ),
                                letterSpacing: 0.0,
                              ),
                        ),
                      ),
                    );
                  }

                  final qrLink = game.qrLink.isNotEmpty
                      ? game.qrLink
                      : buildGameQrLink(game.reference.id);
                  final enseigneName = game.enseigneName.isNotEmpty
                      ? game.enseigneName
                      : 'votre enseigne';
                  final readyText = _buildReadyToPostText(
                    enseigneName: enseigneName,
                    qrLink: qrLink,
                  );

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20.0, 8.0, 20.0, 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeroCard(),
                        const SizedBox(height: 18.0),
                        _buildQrSectionOrdered(
                          game: game,
                          qrLink: qrLink,
                          shareText: readyText,
                        ),
                        const SizedBox(height: 18.0),
                        _buildSocialSectionOrdered(
                          readyText: readyText,
                        ),
                        const SizedBox(height: 18.0),
                        _buildTextSection(readyText),
                        const SizedBox(height: 18.0),
                        _buildPrimaryButton(
                          label: 'Voir mon jeu',
                          icon: Icons.visibility_rounded,
                          onPressed: () => _openGameDetails(game),
                        ),
                        const SizedBox(height: 12.0),
                        _buildSecondaryButton(
                          label: 'Retour à mes jeux',
                          icon: Icons.arrow_back_rounded,
                          onPressed: () async {
                            context.goNamed(JeuxCommercantPageWidget.routeName);
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class GamePosterPreview extends StatelessWidget {
  const GamePosterPreview({
    super.key,
    required this.game,
    required this.qrLink,
  });

  final GamesRecord game;
  final String qrLink;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final theme = FlutterFlowTheme.of(context);
    final enseigneName = game.enseigneName.trim().isEmpty
        ? 'Votre commerce'
        : game.enseigneName.trim();
    final prizeTitle = game.name.trim().isEmpty ? 'Un cadeau surprise' : game.name.trim();
    final description = game.description.trim();
    final periodLabel = game.startDate != null && game.endDate != null
        ? '${dateTimeFormat('d/MM/y', game.startDate, locale: FFLocalizations.of(context).languageCode)} au ${dateTimeFormat('d/MM/y', game.endDate, locale: FFLocalizations.of(context).languageCode)}'
        : game.endDate != null
            ? 'Jusqu\'au ${dateTimeFormat('d/MM/y', game.endDate, locale: FFLocalizations.of(context).languageCode)}'
            : 'Disponible en ce moment';
    final endDateLabel = game.endDate != null
        ? dateTimeFormat(
            'd/MM/y',
            game.endDate,
            locale: FFLocalizations.of(context).languageCode,
          )
        : 'Bientot';
    final secondaryPrizeLabel = game.secondaryPrizeDescription.trim().isNotEmpty
        ? game.secondaryPrizeDescription.trim()
        : game.secondaryPrizes.isNotEmpty
            ? (game.secondaryPrizes.first['name'] ?? game.secondaryPrizes.first['presentation'] ?? '')
                .toString()
                .trim()
            : 'Voir les dotations en jeu';
    final heroDescription = description.isNotEmpty
        ? description
        : 'hors soldes et promotions, selon les conditions du commercant';
    final legalCaption = game.endDate != null
        ? 'Offre valable jusqu\'au ${dateTimeFormat('d MMMM y', game.endDate, locale: FFLocalizations.of(context).languageCode)}'
        : 'Jeu disponible sur ProxiPlay';

    return Container(
      width: 420.0,
      height: 594.0,
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140E1220),
            blurRadius: 20.0,
            offset: Offset(0.0, 8.0),
          ),
        ],
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 388.0,
            height: 582.0,
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SvgPicture.asset(
                      'assets/images/logo_D_secondaire_sans_html_avec_couleurs.svg',
                      width: 170.0,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 8.0),
                    Text(
                      'SCANNEZ, JOUEZ, GAGNEZ',
                      style: GoogleFonts.inter(
                        color: const Color(0xFFA0134D),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    RichText(
                      text: TextSpan(
                        style: GoogleFonts.interTight(
                          fontSize: 22.0,
                          fontWeight: FontWeight.w800,
                          height: 1.02,
                        ),
                        children: [
                          TextSpan(
                            text: '${prizeTitle.toUpperCase()} ',
                            style: const TextStyle(color: Color(0xFF2F2B79)),
                          ),
                          const TextSpan(
                            text: '\u00C0 GAGNER !',
                            style: TextStyle(color: Color(0xFFA0134D)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10.0),
                    RichText(
                      text: TextSpan(
                        style: GoogleFonts.inter(
                          color: const Color(0xFF2F2B79),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                        children: [
                          const TextSpan(
                            text: 'C\'est ',
                          ),
                          const TextSpan(
                            text: 'gratuit.',
                            style: TextStyle(color: Color(0xFFA0134D)),
                          ),
                          TextSpan(text: ' Jouez maintenant chez $enseigneName.'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      heroDescription,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: const Color(0xFF6F7188),
                        fontSize: 11.0,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12.0),
              Container(
                width: 102.0,
                padding: const EdgeInsets.fromLTRB(11.0, 10.0, 11.0, 10.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF2F2B79),
                  borderRadius: BorderRadius.circular(18.0),
                ),
                child: Column(
                  children: [
                    Text(
                      'TENTEZ VOTRE\nCHANCE',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 10.0,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    Container(
                      padding: const EdgeInsets.all(7.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: QrImageView(
                        data: qrLink,
                        version: QrVersions.auto,
                        size: 70.0,
                        gapless: false,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 6.0,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5A623),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: Text(
                        'Fin le\n$endDateLabel',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: const Color(0xFF2F2B79),
                          fontSize: 10.0,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18.0),
                      child: SizedBox(
                        height: 130.0,
                        width: double.infinity,
                        child: game.photo.trim().isNotEmpty
                            ? Image.network(
                                game.photo,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                  color: const Color(0xFFF7F3EF),
                                ),
                              )
                            : Container(
                                color: const Color(0xFFF7F3EF),
                              ),
                      ),
                    ),
                    Positioned(
                      right: 10.0,
                      top: 10.0,
                      child: Container(
                        width: 62.0,
                        height: 62.0,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF5B223),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '100 %\nGRATUIT',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                flex: 3,
                child: Column(
                  children: const [
                    _PosterStepItem(
                      number: '1',
                      title: 'SCANNEZ',
                      description: 'Scannez le QR code avec votre telephone.',
                    ),
                    SizedBox(height: 10.0),
                    _PosterStepItem(
                      number: '2',
                      title: 'JOUEZ',
                      description: 'Jouez tout de suite gratuitement.',
                    ),
                    SizedBox(height: 10.0),
                    _PosterStepItem(
                      number: '3',
                      title: 'GAGNEZ',
                      description: 'Decouvrez immediatement si vous avez gagne.',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          Text(
            legalCaption,
            style: GoogleFonts.inter(
              color: const Color(0xFF70738A),
              fontSize: 10.0,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6.0),
          Row(
            children: [
              Expanded(
                child: _PosterInfoCard(
                  label: 'PERIODE',
                  value: periodLabel,
                ),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: _PosterInfoCard(
                  label: 'COMMERCANT',
                  value: enseigneName,
                ),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: _PosterInfoCard(
                  label: 'LOT PRINCIPAL',
                  value: prizeTitle,
                ),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: _PosterInfoCard(
                  label: 'LOTS SECONDAIRES',
                  value: secondaryPrizeLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          Container(
            height: 8.0,
            width: double.infinity,
            color: Colors.white,
          ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PosterStepItem extends StatelessWidget {
  const _PosterStepItem({
    required this.number,
    required this.title,
    required this.description,
  });

  final String number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 10.0),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0xFFE7E7EF),
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22.0,
            height: 22.0,
            decoration: const BoxDecoration(
              color: Color(0xFFA0134D),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 11.0,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: const Color(0xFF2F2B79),
                    fontSize: 11.0,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2.0),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    color: const Color(0xFF6E718A),
                    fontSize: 10.2,
                    height: 1.25,
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

class _PosterInfoCard extends StatelessWidget {
  const _PosterInfoCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52.0,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FB),
        borderRadius: BorderRadius.circular(14.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: const Color(0xFFA0134D),
              fontSize: 7.2,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 1.0),
          Expanded(
            child: Text(
              value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: const Color(0xFF2F2B79),
                fontSize: 9.2,
                fontWeight: FontWeight.w700,
                height: 0.98,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FacebookPostVisualPreview extends StatelessWidget {
  const FacebookPostVisualPreview({
    super.key,
    required this.gameName,
    required this.enseigneName,
    required this.imageUrl,
    required this.endDateLabel,
    required this.footerLine,
  });

  final String gameName;
  final String enseigneName;
  final String imageUrl;
  final String endDateLabel;
  final String footerLine;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360.0,
      height: 360.0,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28.0),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl.trim().isNotEmpty)
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFFFF5E8),
                      Color(0xFFF6D3A8),
                    ],
                  ),
                ),
              ),
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFF5E8),
                    Color(0xFFF6D3A8),
                  ],
                ),
              ),
            ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x00000000),
                  Color(0x3D000000),
                  Color(0xB3000000),
                ],
                stops: [0.0, 0.48, 1.0],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SvgPicture.asset(
                      'assets/images/logo_D_secondaire_sans_html_avec_couleurs.svg',
                      height: 40.0,
                      fit: BoxFit.contain,
                    ),
                    const Spacer(),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 9.0,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5A623),
                          borderRadius: BorderRadius.circular(14.0),
                        ),
                        child: Text(
                          'Fin le\n$endDateLabel',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 13.0,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  gameName,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.interTight(
                    color: Colors.white,
                    fontSize: 32.0,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 8.0),
                Text(
                  'À GAGNER !',
                  style: GoogleFonts.interTight(
                    color: const Color(0xFFF5A623),
                    fontSize: 24.0,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 10.0),
                Text(
                  footerLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14.0,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic,
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
