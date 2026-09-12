import '/components/player_gain_card.dart';
import 'dart:async';
import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
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

  Timer? _expirationTimer;
  List<MyLotsRecord>? _cachedRecords;
  Future<List<_LotListItem>>? _cachedItems;
  late final Stream<List<MyLotsRecord>> _myLotsStream;
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final Set<String> _deletingLotRefs = <String>{};

  @override
  void initState() {
    super.initState();
    _myLotsStream = currentUserReference == null
        ? const Stream<List<MyLotsRecord>>.empty()
        : queryMyLotsRecord(parent: currentUserReference);
    _expirationTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _model = createModel(context, () => LotsJoueurPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'LotsJoueurPage'});
  }

  @override
  void dispose() {
    _expirationTimer?.cancel();
    _model.dispose();

    super.dispose();
  }

  Future<List<_LotListItem>> _loadLotItems(List<MyLotsRecord> myLots) async {
    final recordsWithPrizeRef =
        myLots.where((record) => record.prizeId != null).toList();
    if (recordsWithPrizeRef.isEmpty) {
      return const <_LotListItem>[];
    }

    final items = <_LotListItem>[];
    for (final record in recordsWithPrizeRef) {
      final prizeRef = record.prizeId!;
      if (record.snapshotData['prize_deleted'] == true) continue;
      final cached = record.snapshotData['prize_snapshot'];
      if (cached is Map) {
        items.add(_LotListItem(
            myLot: record,
            prize: PrizesRecord.getDocumentFromData(
                Map<String, dynamic>.from(cached), prizeRef)));
        continue;
      }
      DocumentSnapshot<Object?> prizeSnap;
      try {
        prizeSnap = await prizeRef.get();
      } catch (error, stackTrace) {
        debugPrint(
          'Failed to load my_lots item. my_lots=${record.reference.path} '
          'prize=${prizeRef.path} error=$error',
        );
        debugPrintStack(stackTrace: stackTrace);
        rethrow;
      }

      if (!prizeSnap.exists) {
        continue;
      }

      final prize = PrizesRecord.fromSnapshot(prizeSnap);
      items.add(_LotListItem(
        myLot: record,
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

  Future<void> _openEnseigne(PrizesRecord prize) async {
    final enseigneRef = prize.enseigneId;
    if (enseigneRef == null) {
      return;
    }
    final enseigneRecord = await EnseignesRecord.getDocumentOnce(enseigneRef);
    if (!mounted) {
      return;
    }
    context.pushNamed(
      EnseigneDetailJoueurPageWidget.routeName,
      queryParameters: {
        'enseigneDoc': serializeParam(
          enseigneRecord,
          ParamType.Document,
        ),
      }.withoutNulls,
      extra: <String, dynamic>{
        'enseigneDoc': enseigneRecord,
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
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to delete my_lots item ${item.myLot.reference.path}: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
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

  Widget _buildLoadErrorState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Text(
          'Impossible de charger vos lots pour le moment.',
          textAlign: TextAlign.center,
          style: FlutterFlowTheme.of(context).bodyMedium.override(
                font: GoogleFonts.inter(
                  fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                ),
                color: FlutterFlowTheme.of(context).secondaryText,
                letterSpacing: 0.0,
                fontWeight: FontWeight.w500,
              ),
        ),
      ),
    );
  }

  bool _showHistory = false;

  Widget _buildSummaryCard(List<_LotListItem> items) {
    final available = items.where((item) => item.prize.isAvailable).length;
    final claimed = items.where((item) => item.prize.claimed).length;
    final expired = items
        .where((item) => !item.prize.claimed && item.prize.isExpired)
        .length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: gainPaper,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFF0ECF1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.card_giftcard_rounded, color: gainPink, size: 30),
        const SizedBox(height: 10),
        Text(
            '${items.length} lot${items.length == 1 ? '' : 's'} gagné${items.length == 1 ? '' : 's'}',
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w700, color: gainInk)),
        const SizedBox(height: 6),
        Text(
            '$available à récupérer · $claimed retiré${claimed == 1 ? '' : 's'} · $expired expiré${expired == 1 ? '' : 's'}',
            style: const TextStyle(color: gainInk, height: 1.5)),
        if (available > 0) ...[
          const SizedBox(height: 8),
          const Text('Profitez vite de vos lots !',
              style: TextStyle(color: gainPink)),
        ],
      ]),
    );
  }

  Widget _content(List<_LotListItem> items) {
    final available = items.where((item) => item.prize.isAvailable).toList();
    final history = items
        .where((item) => item.prize.claimed || item.prize.isExpired)
        .toList();
    final visible = _showHistory ? history : available;
    Widget tab(String label, bool historyTab) {
      final selected = _showHistory == historyTab;
      return Semantics(
          selected: selected,
          child: TextButton(
            onPressed: () => setState(() => _showHistory = historyTab),
            style: TextButton.styleFrom(
                backgroundColor: selected ? gainPink : const Color(0xFFF1EDF5),
                foregroundColor: selected ? gainPaper : gainInk,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
            child: Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: 3 + (visible.isEmpty ? 1 : visible.length),
      itemBuilder: (context, index) {
        if (index == 0) {
          return const Padding(
              padding: EdgeInsets.only(bottom: 18),
              child: Text('Retrouvez tous vos lots gagnés !',
                  style: TextStyle(color: gainInk, fontSize: 15)));
        }
        if (index == 1) return _buildSummaryCard(items);
        if (index == 2) {
          return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                tab('À récupérer (${available.length})', false),
                tab('Historique (${history.length})', true),
              ]));
        }
        if (visible.isEmpty) {
          return Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                  _showHistory
                      ? 'Aucun lot dans votre historique.'
                      : 'Aucun lot à récupérer pour le moment.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: gainInk)));
        }
        final item = visible[index - 3];
        return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PlayerGainCard(
              prize: item.prize,
              onOpen: () => _openLotDetail(item.prize),
              onDelete: () => _confirmDeleteLot(item),
              deleting: _deletingLotRefs.contains(item.myLot.reference.path),
            ));
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: scaffoldKey,
        backgroundColor: const Color(0xFFF7F5F8),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF7F5F8),
          elevation: 0,
          leading: IconButton(
              onPressed: () => context.safePop(),
              icon: const Icon(Icons.chevron_left_rounded, color: gainInk)),
          title: const Text('Mes gains',
              style: TextStyle(color: gainInk, fontWeight: FontWeight.w700)),
        ),
        body: SafeArea(
            child: Column(children: [
          Expanded(
              child: StreamBuilder<List<MyLotsRecord>>(
            stream: _myLotsStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) return _buildLoadErrorState(context);
              if (!snapshot.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: gainPink));
              }
              final records = snapshot.data!;
              if (!identical(_cachedRecords, records)) {
                _cachedRecords = records;
                _cachedItems = _loadLotItems(records);
              }
              return FutureBuilder<List<_LotListItem>>(
                future: _cachedItems,
                builder: (context, snapshot) {
                  if (snapshot.hasError) return _buildLoadErrorState(context);
                  if (!snapshot.hasData) {
                    return const Center(
                        child: CircularProgressIndicator(color: gainPink));
                  }
                  return _content(snapshot.data!);
                },
              );
            },
          )),
          wrapWithModel(
              model: _model.customNavBarJoueurModel,
              updateCallback: () => safeSetState(() {}),
              child: const CustomNavBarJoueurWidget(indexActive: 4)),
        ])),
      );
}

class _LotListItem {
  const _LotListItem({
    required this.myLot,
    required this.prize,
  });

  final MyLotsRecord myLot;
  final PrizesRecord prize;
}
