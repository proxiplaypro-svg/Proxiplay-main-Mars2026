import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/widgets/lots/empty_lots_state_widget.dart';
import '/widgets/lots/lot_card_widget.dart';
import '/widgets/lots/lots_summary_card_widget.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'lots_joueur_page_model.dart';
export 'lots_joueur_page_model.dart';

/// page pour le joueur puisse consulter tous les lots gagnes
class LotsJoueurPageWidget extends StatefulWidget {
  const LotsJoueurPageWidget({super.key});

  static String routeName = 'LotsJoueurPage';
  static String routePath = 'lotsJoueurPage';

  @override
  State<LotsJoueurPageWidget> createState() => _LotsJoueurPageWidgetState();
}

class _LotsJoueurPageWidgetState extends State<LotsJoueurPageWidget> {
  late LotsJoueurPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  final Set<String> _deletingLotRefs = <String>{};

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => LotsJoueurPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'LotsJoueurPage'});
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  Future<List<_LotListItem>> _loadLotItems(List<MyLotsRecord> myLots) async {
    final recordsWithPrizeRef =
        myLots.where((record) => record.prizeId != null).toList();
    if (recordsWithPrizeRef.isEmpty) {
      return const <_LotListItem>[];
    }

    final prizeSnaps = await Future.wait(
      recordsWithPrizeRef.map((record) => record.prizeId!.get()),
    );

    final items = <_LotListItem>[];
    for (var i = 0; i < recordsWithPrizeRef.length; i++) {
      final prizeSnap = prizeSnaps[i];
      if (!prizeSnap.exists) {
        continue;
      }
      final prize = PrizesRecord.fromSnapshot(prizeSnap);
      items.add(_LotListItem(
        myLot: recordsWithPrizeRef[i],
        prize: prize,
      ));
    }

    items.sort((a, b) {
      final aTime = a.prize.winDate?.millisecondsSinceEpoch ?? 0;
      final bTime = b.prize.winDate?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });
    return items;
  }

  Future<void> _openLotDetail(PrizesRecord prize) async {
    context.pushNamed(
      LotDetailJoueurPageWidget.routeName,
      queryParameters: {
        'lot': serializeParam(
          prize,
          ParamType.Document,
        ),
      }.withoutNulls,
      extra: <String, dynamic>{
        'lot': prize,
      },
    );
  }

  Future<void> _confirmDeleteLot(_LotListItem item) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Supprimer ce lot ?'),
            content: const Text(
              'Voulez-vous vraiment supprimer ce lot de votre liste ?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    final deletingKey = item.myLot.reference.path;
    setState(() {
      _deletingLotRefs.add(deletingKey);
    });

    try {
      await item.myLot.reference.delete();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lot supprimé'),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de supprimer ce lot pour le moment.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _deletingLotRefs.remove(deletingKey);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          automaticallyImplyLeading: false,
          leading: FlutterFlowIconButton(
            borderRadius: 24.0,
            buttonSize: 48.0,
            icon: Icon(
              Icons.chevron_left_rounded,
              color: FlutterFlowTheme.of(context).primaryText,
              size: 24.0,
            ),
            onPressed: () async {
              context.safePop();
            },
          ),
          title: Text(
            'Mes Lots Gagnés',
            style: FlutterFlowTheme.of(context).headlineMedium.override(
                  font: GoogleFonts.interTight(
                    fontWeight:
                        FlutterFlowTheme.of(context).headlineMedium.fontWeight,
                    fontStyle:
                        FlutterFlowTheme.of(context).headlineMedium.fontStyle,
                  ),
                  fontSize: 22.0,
                  letterSpacing: 0.0,
                  fontWeight:
                      FlutterFlowTheme.of(context).headlineMedium.fontWeight,
                  fontStyle:
                      FlutterFlowTheme.of(context).headlineMedium.fontStyle,
                ),
          ),
          actions: const [],
          flexibleSpace: FlexibleSpaceBar(
            background: ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: Image.asset(
                'assets/images/Background.png',
                fit: BoxFit.cover,
                alignment: const Alignment(1.0, -1.0),
              ),
            ),
          ),
          centerTitle: false,
          elevation: 0.0,
        ),
        body: SafeArea(
          top: true,
          child: Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                fit: BoxFit.cover,
                alignment: const AlignmentDirectional(-1.0, 1.0),
                image: Image.asset(
                  'assets/images/Background.png',
                ).image,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        20.0, 20.0, 20.0, 0.0),
                    child: StreamBuilder<List<MyLotsRecord>>(
                      stream: currentUserReference == null
                          ? const Stream<List<MyLotsRecord>>.empty()
                          : queryMyLotsRecord(
                              parent: currentUserReference,
                            ),
                      builder: (context, myLotsSnapshot) {
                        if (!myLotsSnapshot.hasData) {
                          return const Center(
                            child: SizedBox(
                              width: 50.0,
                              height: 50.0,
                              child: SizedBox.shrink(),
                            ),
                          );
                        }

                        final myLots =
                            myLotsSnapshot.data ?? const <MyLotsRecord>[];
                        return FutureBuilder<List<_LotListItem>>(
                          future: _loadLotItems(myLots),
                          builder: (context, lotItemsSnapshot) {
                            if (!lotItemsSnapshot.hasData) {
                              return const Center(
                                child: SizedBox(
                                  width: 50.0,
                                  height: 50.0,
                                  child: SizedBox.shrink(),
                                ),
                              );
                            }

                            final items =
                                lotItemsSnapshot.data ?? const <_LotListItem>[];

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LotsSummaryCard(
                                  totalLots: items.length,
                                  unclaimedLots: items
                                      .where((item) => !item.prize.claimed)
                                      .length,
                                ),
                                const SizedBox(height: 20.0),
                                Expanded(
                                  child: items.isEmpty
                                      ? const EmptyLotsState()
                                      : ListView.separated(
                                          padding: EdgeInsets.zero,
                                          itemCount: items.length,
                                          separatorBuilder: (_, __) =>
                                              const SizedBox(height: 14.0),
                                          itemBuilder: (context, index) {
                                            final item = items[index];
                                            final prize = item.prize;
                                            final merchantLabel =
                                                prize.enseigneName.isNotEmpty
                                                    ? prize.enseigneName
                                                    : 'Commerçant non renseigné';
                                            final isDeleting = _deletingLotRefs
                                                .contains(item.myLot.reference.path);

                                            return LotCard(
                                              merchantLabel: merchantLabel,
                                              prizeName: prize.name,
                                              winDateLabel:
                                                  'Gagné le ${dateTimeFormat(
                                                "d/M/y",
                                                prize.winDate,
                                                locale:
                                                    FFLocalizations.of(context)
                                                        .languageCode,
                                              )}',
                                              claimed: prize.claimed,
                                              isDeleting: isDeleting,
                                              onTap: () {
                                                _openLotDetail(prize);
                                              },
                                              onDelete: () {
                                                _confirmDeleteLot(item);
                                              },
                                            );
                                          },
                                        ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
                wrapWithModel(
                  model: _model.customNavBarJoueurModel,
                  updateCallback: () => safeSetState(() {}),
                  child: const CustomNavBarJoueurWidget(
                    indexActive: 4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LotListItem {
  const _LotListItem({
    required this.myLot,
    required this.prize,
  });

  final MyLotsRecord myLot;
  final PrizesRecord prize;
}
