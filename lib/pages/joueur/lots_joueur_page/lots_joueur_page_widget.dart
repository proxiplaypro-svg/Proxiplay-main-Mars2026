import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/components/list_empty_component_widget.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
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
    final recordsWithPrizeRef = myLots.where((record) => record.prizeId != null).toList();
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

  Widget _buildSummaryCard(BuildContext context, List<_LotListItem> items) {
    final totalLots = items.length;
    final unclaimedLots = items.where((item) => !item.prize.claimed).length;

    return Material(
      color: Colors.transparent,
      elevation: 0.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28.0),
      ),
      child: Container(
        width: MediaQuery.sizeOf(context).width,
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(28.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 22.0,
              offset: const Offset(0.0, 8.0),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(22.0, 22.0, 22.0, 22.0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total des Lots',
                      style: FlutterFlowTheme.of(context).headlineSmall.override(
                            font: GoogleFonts.interTight(
                              fontWeight: FontWeight.w700,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .headlineSmall
                                  .fontStyle,
                            ),
                            fontSize: 21.0,
                            letterSpacing: 0.0,
                            color: const Color(0xFF2D2A72),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                      const SizedBox(height: 10.0),
                    Text(
                      totalLots > 0
                          ? '$totalLots lot${totalLots > 1 ? 's' : ''} gagné${totalLots > 1 ? 's' : ''}'
                          : 'Aucun lot gagné',
                      style: FlutterFlowTheme.of(context).bodyLarge.override(
                            font: GoogleFonts.inter(
                              fontWeight: FontWeight.w500,
                              fontStyle:
                                  FlutterFlowTheme.of(context).bodyLarge.fontStyle,
                            ),
                            fontSize: 18.0,
                            color: const Color(0xFF4E586E),
                            letterSpacing: 0.0,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (totalLots > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          '$unclaimedLots non réclamé${unclaimedLots > 1 ? 's' : ''}',
                          style: FlutterFlowTheme.of(context).bodyMedium.override(
                                font: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .fontStyle,
                                ),
                                fontSize: 16.0,
                                color: const Color(0xFF6B5A80),
                                letterSpacing: 0.0,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                width: 72.0,
                height: 72.0,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F6FF),
                  borderRadius: BorderRadius.circular(22.0),
                ),
                child: Icon(
                  Icons.emoji_events_rounded,
                  color: const Color(0xFF9BB1E5),
                  size: 32.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color textColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999.0),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(10.0, 7.0, 10.0, 7.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14.0,
              color: textColor,
            ),
            const SizedBox(width: 6.0),
            Text(
              label,
              style: FlutterFlowTheme.of(context).bodySmall.override(
                    font: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontStyle:
                          FlutterFlowTheme.of(context).bodySmall.fontStyle,
                    ),
                    color: textColor,
                    letterSpacing: 0.0,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLotCard(BuildContext context, _LotListItem item) {
    final prize = item.prize;
    final isDeleting = _deletingLotRefs.contains(item.myLot.reference.path);
    final merchantLabel = prize.enseigneName.isNotEmpty
        ? prize.enseigneName
        : 'Commerçant non renseigné';

    final conditions = _lotConditions(prize);

    return InkWell(
      splashColor: const Color(0x122D2A72),
      focusColor: const Color(0x0A2D2A72),
      hoverColor: const Color(0x082D2A72),
      highlightColor: const Color(0x082D2A72),
      borderRadius: BorderRadius.circular(28.0),
      onTap: () async {
        await _openLotDetail(prize);
      },
      child: Material(
        color: Colors.transparent,
        elevation: 0.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28.0),
        ),
        child: Container(
          width: MediaQuery.sizeOf(context).width,
          decoration: BoxDecoration(
            color: FlutterFlowTheme.of(context).secondaryBackground,
            borderRadius: BorderRadius.circular(28.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 18.0,
                offset: const Offset(0.0, 8.0),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(18.0, 18.0, 18.0, 18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 64.0,
                      height: 64.0,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F6FF),
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                      child: const Icon(
                        Icons.card_giftcard_rounded,
                        color: Color(0xFF9BB1E5),
                        size: 30.0,
                      ),
                    ),
                    const SizedBox(width: 16.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            merchantLabel,
                            style: FlutterFlowTheme.of(context).titleMedium.override(
                                  font: GoogleFonts.interTight(
                                    fontWeight: FontWeight.w700,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .titleMedium
                                        .fontStyle,
                                  ),
                                  fontSize: 19.0,
                                  color: const Color(0xFF2D2A72),
                                  letterSpacing: 0.0,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 6.0),
                          Text(
                            prize.name,
                            style: FlutterFlowTheme.of(context).bodyLarge.override(
                                  font: GoogleFonts.inter(
                                    fontWeight: FontWeight.w500,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .bodyLarge
                                        .fontStyle,
                                  ),
                                  color: const Color(0xFF5E667E),
                                  letterSpacing: 0.0,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Container(
                      width: 56.0,
                      height: 56.0,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F5),
                        borderRadius: BorderRadius.circular(18.0),
                      ),
                      child: IconButton(
                        onPressed: isDeleting ? null : () => _confirmDeleteLot(item),
                        icon: isDeleting
                            ? SizedBox(
                                width: 18.0,
                                height: 18.0,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.0,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    FlutterFlowTheme.of(context).secondaryText,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.delete_outline_rounded,
                                color: Color(0xFFA0134D),
                                size: 24.0,
                              ),
                        splashRadius: 24.0,
                        tooltip: 'Supprimer',
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12.0),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: [
                    _buildBadge(
                      context,
                      icon: Icons.calendar_today_rounded,
                      label: 'Gagné le ${dateTimeFormat(
                        "d/M/y",
                        prize.winDate,
                        locale: FFLocalizations.of(context).languageCode,
                      )}',
                      backgroundColor: const Color(0xFFEFF4FF),
                      textColor: const Color(0xFF7E98D2),
                    ),
                    _buildBadge(
                      context,
                      icon: prize.claimed
                          ? Icons.check_circle_outline_rounded
                          : Icons.schedule_rounded,
                      label: prize.claimed ? 'Réclamé' : 'Non réclamé',
                      backgroundColor: prize.claimed
                          ? const Color(0xFFE9F8F0)
                          : const Color(0xFFFFF1E8),
                      textColor: prize.claimed
                          ? const Color(0xFF2D9B64)
                          : const Color(0xFFD8874D),
                    ),
                    if (prize.hasUsageDeadline())
                      _buildBadge(
                        context,
                        icon: Icons.event_busy_rounded,
                        label: 'À utiliser avant le ${dateTimeFormat(
                          "d/M/y",
                          prize.usageDeadline,
                          locale: FFLocalizations.of(context).languageCode,
                        )}',
                        backgroundColor: const Color(0xFFFFF1E8),
                        textColor: const Color(0xFFD8874D),
                      ),
                  ],
                ),
                if (conditions != null) ...[
                  const SizedBox(height: 14.0),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7FB),
                      borderRadius: BorderRadius.circular(18.0),
                    ),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          14.0, 12.0, 14.0, 12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Conditions',
                            style: FlutterFlowTheme.of(context).bodyMedium.override(
                                  font: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .bodyMedium
                                        .fontStyle,
                                  ),
                                  color: const Color(0xFF2D2A72),
                                  letterSpacing: 0.0,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 6.0),
                          Text(
                            conditions,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: FlutterFlowTheme.of(context).bodyMedium.override(
                                  font: GoogleFonts.inter(
                                    fontWeight: FontWeight.w400,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .bodyMedium
                                        .fontStyle,
                                  ),
                                  color: const Color(0xFF5E667E),
                                  letterSpacing: 0.0,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _lotConditions(PrizesRecord prize) {
    final conditions = prize.description.trim();
    return conditions.isEmpty ? null : conditions;
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
          backgroundColor: Colors.transparent,
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
          centerTitle: true,
          elevation: 0.0,
        ),
        body: SafeArea(
          top: true,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFCFCFF),
                  Color(0xFFF2F4FF),
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        20.0, 18.0, 20.0, 0.0),
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

                        final myLots = myLotsSnapshot.data ?? const <MyLotsRecord>[];
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
                                _buildSummaryCard(context, items),
                                const SizedBox(height: 20.0),
                                Expanded(
                                  child: items.isEmpty
                                      ? const ListEmptyComponentWidget(
                                          title: 'Liste vide',
                                          description: 'Aucun lot',
                                        )
                                      : ListView.separated(
                                          padding: EdgeInsets.zero,
                                          itemCount: items.length,
                                          separatorBuilder: (_, __) =>
                                              const SizedBox(height: 18.0),
                                          itemBuilder: (context, index) =>
                                              _buildLotCard(context, items[index]),
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
