import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class AnimationDetailPage extends StatefulWidget {
  const AnimationDetailPage({
    super.key,
    required this.animationId,
  });

  final String animationId;

  static String routeName = 'AnimationDetailPage';
  static String routePath = 'animationDetailPage';

  @override
  State<AnimationDetailPage> createState() => _AnimationDetailPageState();
}

class _AnimationDetailPageState extends State<AnimationDetailPage> {
  static const Color _pageBackgroundColor = Color(0xFFF0EEE8);
  static const Color _proxiplayBlue = Color(0xFF1A1A4E);
  static const Color _proxiplayBlueLight = Color(0xFF2C2C6E);
  static const Color _progressRed = Color(0xFFA0134D);
  static const Color _accentRed = Color(0xFFA0134D);
  static const Color _cardWhite = Color(0xFFFFFFFF);
  static const Color _mutedGrey = Color(0xFFE3E5EA);
  static const Color _mutedText = Color(0xFF7D8597);

  final GlobalKey _mainPrizeSectionKey = GlobalKey();

  DocumentReference get _animationRef =>
      AnimationsRecord.collection.doc(widget.animationId);

  Stream<_AnimationProgressData> _progressStream() {
    if (currentUserUid.isEmpty) {
      return Stream.value(const _AnimationProgressData());
    }

    return FirebaseFirestore.instance
        .collection('animations')
        .doc(widget.animationId)
        .collection('entries')
        .doc(currentUserUid)
        .snapshots()
        .map((snapshot) {
      final data = snapshot.data() ?? const <String, dynamic>{};
      final visitedCount = data['visited_count'] is int
          ? data['visited_count'] as int
          : 0;
      final thresholdReached = data['threshold_reached'] == true;
      final rawVisitedMerchantIds = data['visited_merchant_ids'];
      final visitedMerchantIds = rawVisitedMerchantIds is List
          ? rawVisitedMerchantIds
              .map((value) => value?.toString().trim() ?? '')
              .where((value) => value.isNotEmpty)
              .toList()
          : const <String>[];
      return _AnimationProgressData(
        visitedCount: visitedCount,
        thresholdReached: thresholdReached,
        visitedMerchantIds: visitedMerchantIds,
      );
    });
  }

  Stream<List<GamesRecord>> _animationGamesStream() {
    return GamesRecord.collection
        .where('animation_id', isEqualTo: widget.animationId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => GamesRecord.fromSnapshot(doc))
              .toList(),
        );
  }

  String _formatPrizeLabel(GamesRecord game) {
    final secondaryPrize = game.secondaryPrizeDescription.trim();
    if (secondaryPrize.isNotEmpty) {
      return secondaryPrize;
    }

    final prizeDescription =
        (game.snapshotData['prize_description'] as String? ?? '').trim();
    if (prizeDescription.isNotEmpty) {
      return prizeDescription;
    }

    return 'Lot \u00E0 d\u00E9couvrir en boutique';
  }

  String _presentationGameDescription(GamesRecord game) {
    for (final item in game.secondaryPrizes) {
      final presentation = (item['presentation'] as String? ?? '').trim();
      if (presentation.isNotEmpty) {
        return presentation;
      }
    }

    final secondaryDescription = game.secondaryPrizeDescription.trim();
    if (secondaryDescription.isNotEmpty) {
      return secondaryDescription;
    }

    final prizeDescription =
        (game.snapshotData['prize_description'] as String? ?? '').trim();
    if (prizeDescription.isNotEmpty) {
      return prizeDescription;
    }

    return game.description;
  }

  static Future<EnseignesRecord?> loadEnseigne(
    GamesRecord game,
  ) async {
    if (game.enseigneId != null) {
      try {
        final enseigne = await EnseignesRecord.getDocumentOnce(game.enseigneId!);
        if (enseigne.name.trim().isNotEmpty) {
          return enseigne;
        }
      } catch (_) {}
    }

    final enseigneName = game.enseigneName.trim();
    if (enseigneName.isEmpty) {
      return null;
    }

    try {
      final enseignes = await queryEnseignesRecordOnce(
        queryBuilder: (query) => query.where('name', isEqualTo: enseigneName),
        singleRecord: true,
      );
      if (enseignes.isNotEmpty) {
        return enseignes.first;
      }
    } catch (_) {}

    return null;
  }

  // Kept for the QR flow and future entry points to a specific game.
  // ignore: unused_element
  Future<void> _openGameDetail(
    BuildContext context,
    GamesRecord game, {
    EnseignesRecord? enseigne,
    bool fromQr = false,
    String source = 'campaign',
  }) async {
    final resolvedEnseigne =
        enseigne ?? await loadEnseigne(game);
    final prizeDescription =
        (game.snapshotData['prize_description'] as String? ?? '').trim();
    final prizePresentation =
        (game.snapshotData['prize_presentation'] as String? ?? '').trim();
    final prizeCount = game.snapshotData['prize_count'];
    final countInt = prizeCount is int
        ? prizeCount
        : int.tryParse(prizeCount?.toString() ?? '') ?? 1;
    final snapshotSecondaryPrizes =
        game.snapshotData['secondary_prizes'] as List<dynamic>? ?? const [];
    final presentationGame = GamesRecord.getDocumentFromData(
      <String, dynamic>{
        ...game.snapshotData,
        'name': prizeDescription.isNotEmpty
            ? prizeDescription
            : game.enseigneName,
        'description': _presentationGameDescription(game),
        if (resolvedEnseigne != null) 'enseigne_id': resolvedEnseigne.reference,
        if (resolvedEnseigne != null) 'enseigne_name': resolvedEnseigne.name,
        if (snapshotSecondaryPrizes.isEmpty && prizeDescription.isNotEmpty)
          'secondary_prizes': [
            <String, dynamic>{
              'name': prizeDescription,
              'count': countInt,
              'presentation': prizePresentation,
            },
          ],
      },
      game.reference,
    );

    if (!context.mounted) {
      return;
    }

    final enseigneParam = resolvedEnseigne != null
        ? serializeParam(
            resolvedEnseigne,
            ParamType.Document,
          )
        : serializeParam(
            game.enseigneId,
            ParamType.DocumentReference,
          );

    await context.pushNamed(
      JeuDetailJoueurPageWidget.routeName,
      queryParameters: {
        'gameDoc': serializeParam(
          presentationGame,
          ParamType.Document,
        ),
        'enseigneDoc': enseigneParam,
        'fromQr': serializeParam(
          fromQr,
          ParamType.bool,
        ),
      }.withoutNulls,
      extra: <String, dynamic>{
        'gameDoc': presentationGame,
        if (resolvedEnseigne != null) 'enseigneDoc': resolvedEnseigne,
        'source': source,
        kTransitionInfoKey: const TransitionInfo(
          hasTransition: true,
          transitionType: PageTransitionType.rightToLeft,
        ),
      },
    );
  }

  Future<void> _openQrScanner(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _QrScannerPage(
          onDetected: (String url) async {
            Navigator.of(context).pop();
            final uri = Uri.tryParse(url);
            if (uri == null) {
              return;
            }
            final segments = uri.pathSegments;
            final jIndex = segments.indexOf('j');
            if (jIndex == -1 || jIndex + 1 >= segments.length) {
              return;
            }
            final gameId = segments[jIndex + 1].trim();
            if (gameId.isEmpty) {
              return;
            }
            final gameRef = GamesRecord.collection.doc(gameId);
            final gameDoc = await GamesRecord.getDocumentOnce(gameRef);
            if (!context.mounted) {
              return;
            }
            await _openGameDetail(
              context,
              gameDoc,
              fromQr: true,
              source: 'qr_scan',
            );
          },
        ),
      ),
    );
  }

  Future<void> _scrollToMainPrizeSection() async {
    final targetContext = _mainPrizeSectionKey.currentContext;
    if (targetContext == null) {
      return;
    }

    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.08,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AnimationsRecord>(
      stream: AnimationsRecord.getDocument(_animationRef),
      builder: (context, animationSnapshot) {
        if (animationSnapshot.hasError) {
          return _AnimationDetailScaffold(
            body: _CenteredState(
              child: Text(
                'Impossible de charger cette animation.',
                style: FlutterFlowTheme.of(context).bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!animationSnapshot.hasData) {
          return const _AnimationDetailScaffold(
            body: _CenteredState(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final animation = animationSnapshot.data!;
        final hasMainPrizeSection = animation.prizeImage.trim().isNotEmpty ||
            animation.prizeDescription.trim().isNotEmpty;
        final isAnimationFinished = animation.endDate != null &&
            !animation.endDate!.isAfter(getCurrentTimestamp);

        return _AnimationDetailScaffold(
          bottomNavigationBar: isAnimationFinished
              ? null
              : SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 16.0),
                    child: _ScanQrButton(
                      onPressed: () => _openQrScanner(context),
                    ),
                  ),
                ),
          body: StreamBuilder<_AnimationProgressData>(
            stream: _progressStream(),
            builder: (context, progressSnapshot) {
              final progress =
                  progressSnapshot.data ?? const _AnimationProgressData();

              return StreamBuilder<List<GamesRecord>>(
                stream: _animationGamesStream(),
                builder: (context, gamesSnapshot) {
                  final hasGamesError = gamesSnapshot.hasError;
                  final games = gamesSnapshot.data ?? const <GamesRecord>[];

                  return SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 120.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (animation.description.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              16.0,
                              16.0,
                              16.0,
                              0.0,
                            ),
                            child: Text(
                              animation.description.trim(),
                              style: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontStyle,
                                    ),
                                    color: _proxiplayBlue,
                                    fontSize: 14.0,
                                    letterSpacing: 0.0,
                                  ),
                            ),
                          ),
                        _AnimationBanner(animation: animation),
                        _ProgressCard(
                          progress: progress,
                          threshold: animation.threshold,
                        ),
                        if (hasMainPrizeSection)
                          _MainPrizeShortcutCard(
                            prizeDescription: animation.prizeDescription.trim(),
                            onTap: _scrollToMainPrizeSection,
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            16.0,
                            0.0,
                            16.0,
                            0.0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _SectionHeader(
                                icon: Icons.card_giftcard_rounded,
                                title:
                                    'Commerces participants & lots imm\u00E9diats',
                              ),
                              const SizedBox(height: 12.0),
                              if (hasGamesError)
                                const _StatusCard(
                                  message:
                                      'Impossible de charger les jeux participants.',
                                )
                              else if (!gamesSnapshot.hasData)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24.0),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else if (games.isEmpty)
                                const _StatusCard(
                                  message:
                                      'Aucun commerce participant pour le moment.',
                                )
                              else
                                Column(
                                  children: games.map((game) {
                                    final enseigneId =
                                        game.enseigneId?.id.trim() ?? '';
                                    final isVisited = progress.visitedMerchantIds
                                        .contains(enseigneId);
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 8.0),
                                      child: _MerchantGameCard(
                                        game: game,
                                        prizeText: _formatPrizeLabel(game),
                                        isVisited: isVisited,
                                        onTap: (enseigne) => _openGameDetail(
                                          context,
                                          game,
                                          enseigne: enseigne,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              if (hasMainPrizeSection) ...[
                                const SizedBox(height: 24.0),
                                _MainPrizeSection(
                                  sectionKey: _mainPrizeSectionKey,
                                  prizeImage: animation.prizeImage.trim(),
                                  prizeDescription:
                                      animation.prizeDescription.trim(),
                                ),
                              ],
                              const SizedBox(height: 24.0),
                              _DrawWinnerSection(
                                animationId: widget.animationId,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _AnimationBanner extends StatelessWidget {
  const _AnimationBanner({
    required this.animation,
  });

  final AnimationsRecord animation;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200.0,
      width: double.infinity,
      margin: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24.0),
        gradient: animation.coverImage.trim().isEmpty
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _AnimationDetailPageState._proxiplayBlue,
                  _AnimationDetailPageState._proxiplayBlueLight,
                ],
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18.0,
            offset: const Offset(0.0, 8.0),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: animation.coverImage.trim().isNotEmpty
          ? Image.network(
              animation.coverImage,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        _AnimationDetailPageState._proxiplayBlue,
                        _AnimationDetailPageState._proxiplayBlueLight,
                      ],
                    ),
                  ),
                );
              },
            )
          : const SizedBox.expand(),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.progress,
    required this.threshold,
  });

  final _AnimationProgressData progress;
  final int threshold;

  @override
  Widget build(BuildContext context) {
    final safeThreshold = threshold <= 0 ? 1 : threshold;
    final visitedCount = progress.visitedCount.clamp(0, safeThreshold);
    final remaining = (safeThreshold - visitedCount).clamp(0, safeThreshold);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: _AnimationDetailPageState._cardWhite,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14.0,
            offset: const Offset(0.0, 6.0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ta progression',
                  style: FlutterFlowTheme.of(context).titleMedium.override(
                        font: GoogleFonts.interTight(
                          fontWeight: FontWeight.w700,
                          fontStyle: FlutterFlowTheme.of(context)
                              .titleMedium
                              .fontStyle,
                        ),
                        color: _AnimationDetailPageState._proxiplayBlue,
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Text(
                '$visitedCount/$safeThreshold commerces visit\u00E9s',
                style: FlutterFlowTheme.of(context).bodyMedium.override(
                      font: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontStyle:
                            FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                      ),
                      color: _AnimationDetailPageState._proxiplayBlue,
                      letterSpacing: 0.0,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 18.0),
          Row(
            children: List.generate(safeThreshold, (index) {
              final stepNumber = index + 1;
              final isVisited = index < visitedCount;
              final isCurrent =
                  !progress.thresholdReached && index == visitedCount;

              return Expanded(
                child: Row(
                  children: [
                    _ProgressStepCircle(
                      stepNumber: stepNumber,
                      isVisited: isVisited,
                      isCurrent: isCurrent,
                    ),
                    if (index < safeThreshold - 1)
                      Expanded(
                        child: Container(
                          height: 4.0,
                          color: index < visitedCount - 1
                              ? _AnimationDetailPageState._progressRed
                              : _AnimationDetailPageState._mutedGrey,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 16.0),
          Text(
            progress.thresholdReached
                ? 'Tu es qualifi\u00E9 pour le tirage final !'
                : 'Visite encore $remaining commerces en scannant le QR code en boutique pour participer au tirage final.',
            style: FlutterFlowTheme.of(context).bodyMedium.override(
                  font: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                  ),
                  color: progress.thresholdReached
                      ? _AnimationDetailPageState._progressRed
                      : _AnimationDetailPageState._proxiplayBlue,
                  letterSpacing: 0.0,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _ProgressStepCircle extends StatelessWidget {
  const _ProgressStepCircle({
    required this.stepNumber,
    required this.isVisited,
    required this.isCurrent,
  });

  final int stepNumber;
  final bool isVisited;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isVisited
        ? _AnimationDetailPageState._progressRed
        : (isCurrent ? Colors.white : const Color(0xFFF1F2F5));
    final borderColor = isCurrent
        ? _AnimationDetailPageState._proxiplayBlue
        : Colors.transparent;
    final textColor = isVisited
        ? Colors.white
        : (isCurrent
            ? _AnimationDetailPageState._proxiplayBlue
            : _AnimationDetailPageState._mutedText);

    return Container(
      width: 36.0,
      height: 36.0,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor,
          width: 3.0,
        ),
      ),
      alignment: Alignment.center,
      child: isVisited
          ? const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 20.0,
            )
          : Text(
              '$stepNumber',
              style: FlutterFlowTheme.of(context).bodyMedium.override(
                    font: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontStyle:
                          FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                    ),
                    color: textColor,
                    letterSpacing: 0.0,
                    fontWeight: FontWeight.w700,
                  ),
            ),
    );
  }
}

class _MainPrizeShortcutCard extends StatelessWidget {
  const _MainPrizeShortcutCard({
    required this.prizeDescription,
    required this.onTap,
  });

  final String prizeDescription;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Material(
        color: _AnimationDetailPageState._cardWhite,
        borderRadius: BorderRadius.circular(16.0),
        child: InkWell(
          borderRadius: BorderRadius.circular(16.0),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Icon(
                  Icons.emoji_events_rounded,
                  color: _AnimationDetailPageState._accentRed,
                  size: 28.0,
                ),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gros lot \u00E0 gagner',
                        style: FlutterFlowTheme.of(context).bodySmall.override(
                              font: GoogleFonts.inter(
                                fontWeight: FontWeight.w500,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .bodySmall
                                    .fontStyle,
                              ),
                              color: _AnimationDetailPageState._mutedText,
                              fontSize: 12.0,
                              letterSpacing: 0.0,
                            ),
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        prizeDescription,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: FlutterFlowTheme.of(context).bodyLarge.override(
                              font: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .bodyLarge
                                    .fontStyle,
                              ),
                              color: _AnimationDetailPageState._proxiplayBlue,
                              fontSize: 16.0,
                              letterSpacing: 0.0,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12.0),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: _AnimationDetailPageState._mutedText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          color: _AnimationDetailPageState._accentRed,
          size: 22.0,
        ),
        const SizedBox(width: 8.0),
        Expanded(
          child: Text(
            title,
            style: FlutterFlowTheme.of(context).titleLarge.override(
                  font: GoogleFonts.interTight(
                    fontWeight: FontWeight.w700,
                    fontStyle:
                        FlutterFlowTheme.of(context).titleLarge.fontStyle,
                  ),
                  color: _AnimationDetailPageState._proxiplayBlue,
                  letterSpacing: 0.0,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}

class _MainPrizeSection extends StatelessWidget {
  const _MainPrizeSection({
    required this.sectionKey,
    required this.prizeImage,
    required this.prizeDescription,
  });

  final GlobalKey sectionKey;
  final String prizeImage;
  final String prizeDescription;

  @override
  Widget build(BuildContext context) {
    if (prizeImage.isEmpty && prizeDescription.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      key: sectionKey,
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.emoji_events_rounded,
            title: 'Lot principal',
          ),
          if (prizeImage.isNotEmpty || prizeDescription.isNotEmpty)
            const SizedBox(height: 12.0),
          if (prizeImage.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(16.0),
              child: Image.network(
                prizeImage,
                width: double.infinity,
                height: 220.0,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox.shrink();
                },
              ),
            ),
          if (prizeDescription.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                prizeDescription,
                style: FlutterFlowTheme.of(context).bodyMedium.override(
                      font: GoogleFonts.inter(
                        fontWeight:
                            FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                        fontStyle:
                            FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                      ),
                      color: _AnimationDetailPageState._proxiplayBlue,
                      fontSize: 14.0,
                      letterSpacing: 0.0,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MerchantGameCard extends StatelessWidget {
  const _MerchantGameCard({
    required this.game,
    required this.prizeText,
    required this.isVisited,
    required this.onTap,
  });

  final GamesRecord game;
  final String prizeText;
  final bool isVisited;
  final Future<void> Function(EnseignesRecord? enseigne) onTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EnseignesRecord?>(
      future: _AnimationDetailPageState.loadEnseigne(game),
      builder: (context, snapshot) {
        final enseigne = snapshot.data;
        final storeName = (enseigne?.name ?? game.enseigneName).trim().isNotEmpty
            ? (enseigne?.name ?? game.enseigneName).trim()
            : 'Commerce partenaire';
        final imageUrl = game.photo.trim();

        return GestureDetector(
          onTap: () async {
            await onTap(enseigne);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: _AnimationDetailPageState._cardWhite,
              borderRadius: BorderRadius.circular(12.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10.0,
                  offset: const Offset(0.0, 4.0),
                ),
              ],
            ),
            child: Row(
              children: [
                _MerchantImage(imageUrl: imageUrl, fallbackLabel: storeName),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        storeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FlutterFlowTheme.of(context).bodyLarge.override(
                              font: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .bodyLarge
                                    .fontStyle,
                              ),
                              color: _AnimationDetailPageState._proxiplayBlue,
                              letterSpacing: 0.0,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        prizeText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: FlutterFlowTheme.of(context).bodyMedium.override(
                              font: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .fontStyle,
                              ),
                              color: _AnimationDetailPageState._progressRed,
                              letterSpacing: 0.0,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8.0),
                _MerchantStatusBadge(isVisited: isVisited),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MerchantImage extends StatelessWidget {
  const _MerchantImage({
    required this.imageUrl,
    required this.fallbackLabel,
  });

  final String imageUrl;
  final String fallbackLabel;

  @override
  Widget build(BuildContext context) {
    final fallbackText = fallbackLabel.isNotEmpty
        ? fallbackLabel.characters.first.toUpperCase()
        : '?';

    return ClipRRect(
      borderRadius: BorderRadius.circular(12.0),
      child: Container(
        width: 48.0,
        height: 48.0,
        color: const Color(0xFFEFF2F7),
        child: imageUrl.isNotEmpty
            ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Text(
                      fallbackText,
                      style: FlutterFlowTheme.of(context).titleMedium.override(
                            font: GoogleFonts.interTight(
                              fontWeight: FontWeight.w700,
                              fontStyle: FlutterFlowTheme.of(context)
                                  .titleMedium
                                  .fontStyle,
                            ),
                            color: _AnimationDetailPageState._proxiplayBlue,
                            letterSpacing: 0.0,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  );
                },
              )
            : Center(
                child: Text(
                  fallbackText,
                  style: FlutterFlowTheme.of(context).titleMedium.override(
                        font: GoogleFonts.interTight(
                          fontWeight: FontWeight.w700,
                          fontStyle:
                              FlutterFlowTheme.of(context).titleMedium.fontStyle,
                        ),
                        color: _AnimationDetailPageState._proxiplayBlue,
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
      ),
    );
  }
}

class _MerchantStatusBadge extends StatelessWidget {
  const _MerchantStatusBadge({
    required this.isVisited,
  });

  final bool isVisited;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isVisited
        ? _AnimationDetailPageState._progressRed.withValues(alpha: 0.14)
        : const Color(0xFFF1F2F5);
    final foregroundColor = isVisited
        ? _AnimationDetailPageState._progressRed
        : _AnimationDetailPageState._mutedText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isVisited ? 'Visit\u00E9' : 'En boutique',
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  font: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontStyle: FlutterFlowTheme.of(context).bodySmall.fontStyle,
                  ),
                  color: foregroundColor,
                  letterSpacing: 0.0,
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (isVisited) ...[
            const SizedBox(width: 4.0),
            Icon(
              Icons.check_rounded,
              size: 16.0,
              color: foregroundColor,
            ),
          ],
        ],
      ),
    );
  }
}

class _ScanQrButton extends StatelessWidget {
  const _ScanQrButton({
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56.0,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _AnimationDetailPageState._progressRed,
          foregroundColor: Colors.white,
          elevation: 0.0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30.0),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36.0,
              height: 36.0,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: const Icon(
                Icons.qr_code_scanner_rounded,
                color: Colors.white,
                size: 22.0,
              ),
            ),
            const SizedBox(width: 12.0),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scanner un QR code',
                    style: FlutterFlowTheme.of(context).bodyLarge.override(
                          font: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontStyle: FlutterFlowTheme.of(context)
                                .bodyLarge
                                .fontStyle,
                          ),
                          color: Colors.white,
                          letterSpacing: 0.0,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    'chez un commer\u00E7ant',
                    style: FlutterFlowTheme.of(context).bodySmall.override(
                          font: GoogleFonts.inter(
                            fontWeight: FontWeight.w500,
                            fontStyle: FlutterFlowTheme.of(context)
                                .bodySmall
                                .fontStyle,
                          ),
                          color: Colors.white.withValues(alpha: 0.8),
                          letterSpacing: 0.0,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimationDetailScaffold extends StatelessWidget {
  const _AnimationDetailScaffold({
    required this.body,
    this.bottomNavigationBar,
  });

  final Widget body;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AnimationDetailPageState._pageBackgroundColor,
      appBar: AppBar(
        backgroundColor: _AnimationDetailPageState._pageBackgroundColor,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        elevation: 0.0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: _AnimationDetailPageState._proxiplayBlue,
          ),
          onPressed: () => context.safePop(),
        ),
        title: Image.asset(
          'assets/images/logo_D_secondaire.png',
          height: 32.0,
        ),
      ),
      body: body,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: _AnimationDetailPageState._cardWhite,
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Text(
        message,
        style: FlutterFlowTheme.of(context).bodyMedium.override(
              font: GoogleFonts.inter(
                fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
              ),
              color: _AnimationDetailPageState._proxiplayBlue,
              letterSpacing: 0.0,
            ),
      ),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: child,
      ),
    );
  }
}

class _AnimationProgressData {
  const _AnimationProgressData({
    this.visitedCount = 0,
    this.thresholdReached = false,
    this.visitedMerchantIds = const <String>[],
  });

  final int visitedCount;
  final bool thresholdReached;
  final List<String> visitedMerchantIds;
}

class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage({required this.onDetected});

  final void Function(String url) onDetected;

  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner le QR code'),
        backgroundColor: const Color(0xFF1A1A4E),
        foregroundColor: Colors.white,
      ),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) {
            return;
          }
          final barcode =
              capture.barcodes.isNotEmpty ? capture.barcodes.first : null;
          final url = barcode?.rawValue;
          if (url == null || url.isEmpty) {
            return;
          }
          if (!url.contains('proxiplay.fr/j/')) {
            return;
          }
          _handled = true;
          widget.onDetected(url);
        },
      ),
    );
  }
}

class _DrawWinnerSection extends StatelessWidget {
  const _DrawWinnerSection({required this.animationId});

  final String animationId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .doc('animations/$animationId/winner/current')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox.shrink();
        }
        final data = snapshot.data!.data() ?? {};
        final label = (data['label'] as String? ?? '').trim();
        if (label.isEmpty) {
          return const SizedBox.shrink();
        }
        final selectedAt = data['selected_at'];
        String dateLabel = '';
        if (selectedAt is Timestamp) {
          final dt = selectedAt.toDate();
          dateLabel = DateFormat('dd/MM/yyyy', 'fr_FR').format(dt);
        }

        return Container(
          margin: const EdgeInsets.only(top: 4.0),
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A4E),
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: Color(0xFFFFD700),
                size: 32.0,
              ),
              const SizedBox(width: 12.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gagnant du tirage',
                      style: FlutterFlowTheme.of(context).labelSmall.override(
                            font: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                            ),
                            color: Colors.white.withValues(alpha: 0.7),
                            letterSpacing: 0.0,
                          ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      label,
                      style: FlutterFlowTheme.of(context).titleSmall.override(
                            font: GoogleFonts.interTight(
                              fontWeight: FontWeight.w700,
                            ),
                            color: Colors.white,
                            letterSpacing: 0.0,
                          ),
                    ),
                    if (dateLabel.isNotEmpty)
                      Text(
                        'Tirage du $dateLabel',
                        style:
                            FlutterFlowTheme.of(context).bodySmall.override(
                                  font: GoogleFonts.inter(
                                    fontWeight: FontWeight.w400,
                                  ),
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 11.0,
                                  letterSpacing: 0.0,
                                ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
