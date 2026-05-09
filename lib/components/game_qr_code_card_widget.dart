import '/backend/schema/games_record.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/utils/share_links.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
  final GlobalKey _qrBoundaryKey = GlobalKey();
  bool _isSharing = false;

  String get _qrLink => buildGameQrLink(widget.game.reference.id);

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _qrLink));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Lien QR copie.'),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    // TODO(Proxiplay): ajouter l'export image / PDF via RepaintBoundary.
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
        ],
      ),
    );
  }
}
