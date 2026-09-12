import '/components/merchant_pickup_point.dart';
import '/widgets/proxiplay_network_image.dart';
import 'dart:async';
import '/backend/backend.dart';
import '/components/custom_nav_bar_joueur_widget.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lot_detail_joueur_page_model.dart';
export 'lot_detail_joueur_page_model.dart';

/// page avec detail du lot gagné avec code a montrer au commercant pour
/// récupérer le lot
class LotDetailJoueurPageWidget extends StatefulWidget {
  const LotDetailJoueurPageWidget({
    super.key,
    required this.lot,
  });

  final PrizesRecord? lot;

  static String routeName = 'lotDetailJoueurPage';
  static String routePath = 'lotDetailJoueurPage';

  @override
  State<LotDetailJoueurPageWidget> createState() =>
      _LotDetailJoueurPageWidgetState();
}

class _LotDetailJoueurPageWidgetState extends State<LotDetailJoueurPageWidget> {
  late LotDetailJoueurPageModel _model;

  PrizesRecord? _lot;
  StreamSubscription? _lotSubscription;
  Timer? _expirationTimer;
  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _lot = widget.lot;
    _lotSubscription = widget.lot?.reference.snapshots().listen((snapshot) {
      if (mounted) {
        setState(() {
          _lot = snapshot.exists ? PrizesRecord.fromSnapshot(snapshot) : null;
        });
      }
    }, onError: (Object error) {
      if (mounted) {
        setState(() {
          _lot = null;
        });
      }
    });
    _expirationTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _model = createModel(context, () => LotDetailJoueurPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'lotDetailJoueurPage'});
  }

  @override
  void dispose() {
    _lotSubscription?.cancel();
    _expirationTimer?.cancel();
    _model.dispose();

    super.dispose();
  }

  Future<void> _copyClaimCode() async {
    final claimCode = _lot?.claimCode;
    if (claimCode == null || claimCode.isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: claimCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Code copié'),
        backgroundColor: FlutterFlowTheme.of(context).primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static const ink = Color(0xFF2B285F);
  static const accent = Color(0xFFA0134D);

  Widget _card({required String title, required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: const Color(0xFFFEFFFE),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFF0ECF1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: ink, fontSize: 21, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          child,
        ]),
      );

  Widget _badge(String text, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: const Color(0xFFF9EAF1),
            borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 8),
          Flexible(
              child: Text(text,
                  style: const TextStyle(
                      color: accent, fontWeight: FontWeight.w600))),
        ]),
      );

  void _showConditions(String description) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFFEFFFE),
      builder: (context) => SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Conditions d’utilisation',
                        style: TextStyle(
                            color: ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    SelectableText(description,
                        style: const TextStyle(color: ink, height: 1.5)),
                  ]))),
    );
  }

  Widget _content({String? gamePhoto}) {
    final prize = _lot;
    if (prize == null) return const Center(child: Text('Lot indisponible.'));
    final status = prize.claimed
        ? 'Retiré'
        : prize.isExpired
            ? 'Expiré'
            : 'À récupérer';
    final deadline = prize.usageDeadline;
    final description = prize.description.trim();
    final photo = gamePhoto?.trim() ?? '';
    final photoUri = Uri.tryParse(photo);
    final hasPhoto = photoUri != null &&
        (photoUri.scheme == 'https' || photoUri.scheme == 'http') &&
        photoUri.host.isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
              color: const Color(0xFFFEFFFE),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFF0ECF1))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (hasPhoto)
              AspectRatio(
                  key: const ValueKey('lot-game-hero'),
                  aspectRatio: 16 / 9,
                  child: ProxiplayNetworkImage(
                      imageUrl: photo, fit: BoxFit.cover)),
            Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          prize.name.trim().isEmpty
                              ? 'Votre lot'
                              : prize.name.trim(),
                          style: const TextStyle(
                              color: ink,
                              fontSize: 26,
                              fontWeight: FontWeight.w700)),
                      if (prize.enseigneName.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('chez ${prize.enseigneName.trim()}',
                            style: const TextStyle(color: ink, fontSize: 16)),
                      ],
                      const SizedBox(height: 16),
                      _badge(
                          status,
                          prize.isAvailable
                              ? Icons.card_giftcard_outlined
                              : Icons.check_circle_outline),
                      if (deadline != null) ...[
                        const SizedBox(height: 8),
                        _badge(
                            '${prize.isAvailable ? 'À utiliser avant le' : 'Échéance :'} ${dateTimeFormat('dd/MM/yyyy', deadline)}',
                            Icons.schedule),
                      ],
                      if (prize.gameId == null) ...[
                        if (prize.fulfillmentType == 'platform') ...[
                          const SizedBox(height: 12),
                          const Text('Remise du lot organisée par Proxiplay.')
                        ],
                        if (prize.fulfillmentType == 'review' ||
                            prize.fulfillmentType == 'partner') ...[
                          const SizedBox(height: 12),
                          const Text(
                              'Contactez Proxiplay pour les modalités de remise.')
                        ],
                        if (prize.winDate != null) ...[
                          const SizedBox(height: 8),
                          Text(
                              'Gagné le ${dateTimeFormat('d/M/y', prize.winDate, locale: FFLocalizations.of(context).languageCode)}')
                        ],
                      ],
                    ])),
          ]),
        ),
        const SizedBox(height: 16),
        _card(
            title: 'Code de récupération',
            child: prize.isAvailable
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                        Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                                color: const Color(0xFFF9EAF1),
                                borderRadius: BorderRadius.circular(16)),
                            child: SelectableText(prize.claimCode,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: accent,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1))),
                        const SizedBox(height: 12),
                        const Text('Présentez ce code au commerçant',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: ink)),
                        const SizedBox(height: 8),
                        TextButton.icon(
                            onPressed: _copyClaimCode,
                            style:
                                TextButton.styleFrom(foregroundColor: accent),
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('Copier le code')),
                      ])
                : Text(prize.claimed ? 'Lot récupéré' : 'Lot expiré',
                    style: const TextStyle(color: ink))),
        if (prize.gameId != null || prize.fulfillmentType == 'merchant') ...[
          const SizedBox(height: 16),
          MerchantPickupPoint(enseigneRef: prize.enseigneId),
        ],
        if (description.isNotEmpty) ...[
          const SizedBox(height: 16),
          _card(
              title: 'Conditions d’utilisation',
              child: InkWell(
                onTap: () => _showConditions(description),
                child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Expanded(
                          child: Text(description,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: ink, height: 1.5))),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right_rounded, color: accent),
                    ])),
              )),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          FocusManager.instance.primaryFocus?.unfocus();
        },
        child: Scaffold(
          key: scaffoldKey,
          backgroundColor: const Color(0xFFF7F5F8),
          appBar: AppBar(
              backgroundColor: const Color(0xFFF7F5F8),
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              leading: IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, color: ink),
                  onPressed: () => context.pop()),
              title: const Text('Mon lot',
                  style: TextStyle(
                      color: ink, fontSize: 22, fontWeight: FontWeight.w700))),
          body: SafeArea(
              child: Column(children: [
            Expanded(
                child: _lot?.gameId == null
                    ? _content()
                    : StreamBuilder<GamesRecord>(
                        stream: GamesRecord.getDocument(_lot!.gameId!),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData)
                            return const Center(
                                child: SizedBox(
                                    width: 50,
                                    height: 50,
                                    child: SizedBox.shrink()));
                          return _content(gamePhoto: snapshot.data!.photo);
                        })),
            wrapWithModel(
                model: _model.customNavBarJoueurModel,
                updateCallback: () => safeSetState(() {}),
                child: const CustomNavBarJoueurWidget(indexActive: 4)),
          ])),
        ),
      );
}
