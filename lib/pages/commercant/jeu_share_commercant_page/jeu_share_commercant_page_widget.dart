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

  String get _gameId => (widget.gameId ?? '').trim();

  void _showSnackBar(String message) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _buildDisplayLink(String qrLink) {
    final uri = Uri.tryParse(qrLink);
    if (uri == null || uri.host.isEmpty) {
      return qrLink;
    }
    final segments = uri.pathSegments;
    if (segments.length < 2) {
      return '${uri.host}${uri.path}';
    }
    final gameId = segments.last;
    final shortId = gameId.length > 11
        ? '${gameId.substring(0, 5)}...${gameId.substring(gameId.length - 4)}'
        : gameId;
    return '${uri.host}/${segments.first}/$shortId';
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

  Future<void> _showPosterPreview({
    required GamesRecord game,
    required String qrLink,
  }) async {
    final GlobalKey posterBoundaryKey = GlobalKey();
    final enseigneName =
        game.enseigneName.isNotEmpty ? game.enseigneName : 'votre enseigne';

    _showSnackBar('Affiche générée ✓');
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
                  RepaintBoundary(
                    key: posterBoundaryKey,
                    child: GamePosterPreview(
                      gameName: game.name,
                      enseigneName: enseigneName,
                      qrLink: qrLink,
                      displayQrLink: _buildDisplayLink(qrLink),
                    ),
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
    if (!context.mounted) {
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
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : () async => onPressed(),
        style: ElevatedButton.styleFrom(
          backgroundColor: FlutterFlowTheme.of(context).primary,
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
  }) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () async => onPressed(),
        icon: Icon(icon, size: 18.0),
        label: Text(
          label,
          textAlign: TextAlign.center,
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 10.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
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
                'Affichez ce QR code en boutique ou publiez-le sur vos réseaux.',
          ),
          const SizedBox(height: 20.0),
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
          const SizedBox(height: 18.0),
          _buildPrimaryButton(
            label: _isSharing ? 'Ouverture du partage...' : 'Partager le jeu',
            icon: Icons.share_rounded,
            isLoading: _isSharing,
            onPressed: () => _shareText(shareText),
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

  Widget _buildSocialSection({
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
                icon: Icons.facebook_rounded,
                label: 'Facebook',
                onPressed: () => _shareToFacebook(qrLink),
              ),
              const SizedBox(width: 10.0),
              _buildSocialButton(
                icon: Icons.message_rounded,
                label: 'WhatsApp',
                onPressed: () => _shareToWhatsApp(readyText),
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
        ],
      ),
    );
  }

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
                        _buildQrSection(
                          game: game,
                          qrLink: qrLink,
                          shareText: readyText,
                        ),
                        const SizedBox(height: 18.0),
                        _buildTextSection(readyText),
                        const SizedBox(height: 18.0),
                        _buildSocialSection(
                          qrLink: qrLink,
                          readyText: readyText,
                        ),
                        const SizedBox(height: 18.0),
                        _buildAdviceSection(),
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
    required this.gameName,
    required this.enseigneName,
    required this.qrLink,
    required this.displayQrLink,
  });

  final String gameName;
  final String enseigneName;
  final String qrLink;
  final String displayQrLink;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420.0),
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/images/logo_D_secondaire_sans_html_avec_couleurs.svg',
            width: 180.0,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 20.0),
          Text(
            'Un jeu vous attend ici !',
            textAlign: TextAlign.center,
            style: theme.headlineSmall.override(
              font: GoogleFonts.interTight(
                fontWeight: FontWeight.w700,
                fontStyle: theme.headlineSmall.fontStyle,
              ),
              color: theme.primary,
              letterSpacing: 0.0,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10.0),
          Text(
            enseigneName,
            textAlign: TextAlign.center,
            style: theme.titleLarge.override(
              font: GoogleFonts.interTight(
                fontWeight: FontWeight.w700,
                fontStyle: theme.titleLarge.fontStyle,
              ),
              letterSpacing: 0.0,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8.0),
          Text(
            gameName,
            textAlign: TextAlign.center,
            style: theme.bodyLarge.override(
              font: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontStyle: theme.bodyLarge.fontStyle,
              ),
              letterSpacing: 0.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18.0),
          Text(
            'Scannez le QR code et tentez votre chance',
            textAlign: TextAlign.center,
            style: theme.bodyMedium.override(
              font: GoogleFonts.inter(
                fontWeight: theme.bodyMedium.fontWeight,
                fontStyle: theme.bodyMedium.fontStyle,
              ),
              color: theme.secondaryText,
              letterSpacing: 0.0,
            ),
          ),
          const SizedBox(height: 20.0),
          Container(
            padding: const EdgeInsets.all(18.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24.0),
              border: Border.all(color: const Color(0x140E1220)),
            ),
            child: QrImageView(
              data: qrLink,
              version: QrVersions.auto,
              size: 220.0,
              gapless: false,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 20.0),
          Text(
            'Jouez sur Proxiplay',
            textAlign: TextAlign.center,
            style: theme.titleMedium.override(
              font: GoogleFonts.interTight(
                fontWeight: FontWeight.w700,
                fontStyle: theme.titleMedium.fontStyle,
              ),
              color: theme.primary,
              letterSpacing: 0.0,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
