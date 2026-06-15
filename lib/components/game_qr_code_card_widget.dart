import '/backend/schema/games_record.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/utils/share_links.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

class GameQrCodeCard extends StatefulWidget {
  const GameQrCodeCard({
    super.key,
    required this.game,
    this.showLinkDetails = true,
    this.subtitle = 'A afficher en boutique',
  });

  final GamesRecord game;
  final bool showLinkDetails;
  final String subtitle;

  @override
  State<GameQrCodeCard> createState() => _GameQrCodeCardState();
}

class _GameQrCodeCardState extends State<GameQrCodeCard> {
  static const MethodChannel _mediaChannel = MethodChannel('proxiplay/media');

  final GlobalKey _qrBoundaryKey = GlobalKey();
  bool _isSharing = false;
  bool _isDownloadingFacebookVisual = false;

  String get _qrLink => buildGameQrLink(widget.game.reference.id);
  String get _enseigneName {
    final trimmed = widget.game.enseigneName.trim();
    return trimmed.isNotEmpty ? trimmed : 'votre enseigne';
  }

  String get _gameDescription {
    final trimmed = widget.game.description.trim();
    if (trimmed.isEmpty) {
      return 'Jouez gratuitement sur ProxiPlay.';
    }
    return trimmed.length > 160 ? '${trimmed.substring(0, 157)}...' : trimmed;
  }

  String? _buildAlcoholLegalMessage() {
    final source =
        '${widget.game.name} ${widget.game.description}'.toLowerCase();
    final alcoholPattern = RegExp(
      r'alcool|champagne|vin|biere|bière|whisky|rhum|vodka|gin|cidre|liqueur|aperitif|apéritif|spiritueux',
    );
    if (!alcoholPattern.hasMatch(source)) {
      return null;
    }
    return '⚠️ L\'abus d\'alcool est dangereux pour la santé. A consommer avec modération.';
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _buildFacebookPostText() {
    final endDate = widget.game.endDate != null
        ? dateTimeFormat(
            'd MMMM y',
            widget.game.endDate,
            locale: FFLocalizations.of(context).languageCode,
          )
        : 'bientot';
    final merchantHashtag = _enseigneName.replaceAll(RegExp(r'\s+'), '');
    final legalMessage = _buildAlcoholLegalMessage();
    final legalBlock = legalMessage != null ? '\n\n$legalMessage' : '';

    return '🎉 $_enseigneName vous propose un jeu gratuit sur ProxiPlay !\n\n'
        '🎁 A gagner : ${widget.game.name}\n\n'
        '📝 $_gameDescription\n'
        '📅 Jusqu\'au $endDate\n\n'
        '📱 Jouez gratuitement sur ProxiPlay :\n'
        '🔗 $_qrLink'
        '$legalBlock\n\n'
        '#ProxiPlay #$merchantHashtag #JeuGratuit #BonPlan';
  }

  String _buildFacebookVisualFooter() {
    final truncated = _enseigneName.length > 25
        ? '${_enseigneName.substring(0, 25)}...'
        : _enseigneName;
    return '$truncated • Jeu gratuit • ProxiPlay';
  }

  Future<void> _copyLink(BuildContext context) async {
    await _copyText(_qrLink, successMessage: 'Lien QR copie.');
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

  Future<void> _shareQrCode(BuildContext context) async {
    if (_isSharing) {
      return;
    }

    setState(() => _isSharing = true);
    try {
      final boundary = _qrBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('QR render boundary unavailable.');
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('QR image bytes unavailable.');
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final Directory tempDir = await getTemporaryDirectory();
      final File file =
          File('${tempDir.path}\\proxiplay-qr-${widget.game.reference.id}.png');
      await file.writeAsBytes(pngBytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: _qrLink,
        subject: 'QR code Proxiplay',
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Partage du QR code impossible : $error'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
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
    final File file = File('${tempDir.path}\\$fileName');
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

  Future<void> _downloadFacebookVisual({
    required GlobalKey visualBoundaryKey,
  }) async {
    if (_isDownloadingFacebookVisual) {
      return;
    }
    if (kIsWeb) {
      _showSnackBar('Telechargement indisponible sur cet appareil.');
      return;
    }

    setState(() => _isDownloadingFacebookVisual = true);
    try {
      final file = await _captureBoundaryToPng(
        boundaryKey: visualBoundaryKey,
        fileName: 'facebook-${widget.game.reference.id}.png',
      );
      await _saveImageInGallery(
        bytes: await file.readAsBytes(),
        fileName: 'facebook-${widget.game.reference.id}.png',
      );
      _showSnackBar('Visuel Facebook enregistre dans vos photos.');
    } on UnsupportedError {
      _showSnackBar('Telechargement indisponible sur cet appareil.');
    } catch (_) {
      _showSnackBar('Impossible de generer le visuel Facebook.');
    } finally {
      if (mounted) {
        setState(() => _isDownloadingFacebookVisual = false);
      }
    }
  }

  Future<void> _showFacebookPostDialog() async {
    final facebookText = _buildFacebookPostText();
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
                  Text(
                    'Creer le post Facebook',
                    style: FlutterFlowTheme.of(context).titleLarge.override(
                          font: GoogleFonts.interTight(
                            fontWeight: FontWeight.w700,
                            fontStyle: FlutterFlowTheme.of(context)
                                .titleLarge
                                .fontStyle,
                          ),
                          letterSpacing: 0.0,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6.0),
                  Text(
                    'Copiez le texte puis ajoutez le visuel manuellement sur Facebook.',
                    style: FlutterFlowTheme.of(context).bodyMedium.override(
                          font: GoogleFonts.inter(
                            fontWeight: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .fontWeight,
                            fontStyle: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .fontStyle,
                          ),
                          color: FlutterFlowTheme.of(context).secondaryText,
                          letterSpacing: 0.0,
                        ),
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
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _copyText(
                        facebookText,
                        successMessage: 'Texte Facebook copie.',
                      ),
                      icon: const Icon(Icons.content_copy_rounded, size: 18.0),
                      label: const Text('Copier le texte'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.0),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  RepaintBoundary(
                    key: visualBoundaryKey,
                    child: FacebookPostVisualPreview(
                      gameName: widget.game.name,
                      gameDescription: _gameDescription,
                      enseigneName: _enseigneName,
                      imageUrl: widget.game.photo,
                      endDateLabel: widget.game.endDate != null
                          ? dateTimeFormat(
                              'd/MM/y',
                              widget.game.endDate,
                              locale: FFLocalizations.of(context).languageCode,
                            )
                          : 'bientot',
                      footerLine: _buildFacebookVisualFooter(),
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isDownloadingFacebookVisual
                          ? null
                          : () => _downloadFacebookVisual(
                                visualBoundaryKey: visualBoundaryKey,
                              ),
                      icon: _isDownloadingFacebookVisual
                          ? const SizedBox(
                              width: 18.0,
                              height: 18.0,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download_rounded, size: 18.0),
                      label: Text(
                        _isDownloadingFacebookVisual
                            ? 'Telechargement du visuel...'
                            : 'Telecharger le visuel',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: FlutterFlowTheme.of(context).primary,
                        foregroundColor: Colors.white,
                        elevation: 0.0,
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.0),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded, size: 18.0),
                      label: const Text('Fermer'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.0),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'QR code boutique',
            style: FlutterFlowTheme.of(context).titleLarge.override(
                  font: GoogleFonts.interTight(
                    fontWeight: FontWeight.w700,
                    fontStyle: FlutterFlowTheme.of(context).titleLarge.fontStyle,
                  ),
                  letterSpacing: 0.0,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8.0),
          Text(
            widget.subtitle,
            style: FlutterFlowTheme.of(context).bodyMedium.override(
                  font: GoogleFonts.inter(
                    fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                    fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                  ),
                  letterSpacing: 0.0,
                ),
          ),
          const SizedBox(height: 18.0),
          Center(
            child: RepaintBoundary(
              key: _qrBoundaryKey,
              child: Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20.0),
                ),
                child: QrImageView(
                  data: _qrLink,
                  version: QrVersions.auto,
                  size: 220.0,
                  gapless: false,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16.0),
          if (widget.showLinkDetails) ...[
            SelectableText(
              _qrLink,
              style: FlutterFlowTheme.of(context).bodySmall.override(
                    font: GoogleFonts.inter(
                      fontWeight: FlutterFlowTheme.of(context).bodySmall.fontWeight,
                      fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                    ),
                    color: FlutterFlowTheme.of(context).secondaryText,
                    letterSpacing: 0.0,
                  ),
            ),
            const SizedBox(height: 12.0),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async => _copyLink(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14.0),
                  ),
                ),
                child: const Text('Copier le lien'),
              ),
            ),
            const SizedBox(height: 10.0),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _isSharing ? null : () async => _shareQrCode(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.0),
                ),
              ),
              child: Text(
                _isSharing ? 'Preparation du partage...' : 'Partager le QR code',
              ),
            ),
          ),
          const SizedBox(height: 10.0),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async => _showFacebookPostDialog(),
              icon: Icon(
                Icons.facebook_rounded,
                color: Colors.white,
              ),
              label: const Text('Creer le post Facebook'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1877F2),
                foregroundColor: Colors.white,
                elevation: 0.0,
                padding: const EdgeInsets.symmetric(vertical: 14.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.0),
                ),
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
    required this.gameDescription,
    required this.enseigneName,
    required this.imageUrl,
    required this.endDateLabel,
    required this.footerLine,
  });

  final String gameName;
  final String gameDescription;
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
                    Expanded(
                      child: SvgPicture.asset(
                        'assets/images/logo_D_secondaire_sans_html_avec_couleurs.svg',
                        height: 40.0,
                        fit: BoxFit.fitHeight,
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Flexible(
                      child: Align(
                        alignment: Alignment.topRight,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 116.0),
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
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  enseigneName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: const Color(0xFFF5A623),
                    fontSize: 14.0,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 6.0),
                Text(
                  gameName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.interTight(
                    color: Colors.white,
                    fontSize: 30.0,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 10.0),
                Text(
                  gameDescription,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 15.0,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14.0),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 10.0,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14.0),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    footerLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 13.0,
                      fontWeight: FontWeight.w600,
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
