import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/backend/schema/enums/enums.dart';
import '/components/game_card_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AnimationDetailPage extends StatelessWidget {
  const AnimationDetailPage({
    super.key,
    required this.animationId,
  });

  final String animationId;

  static String routeName = 'AnimationDetailPage';
  static String routePath = 'animationDetailPage';

  DocumentReference get _animationRef =>
      AnimationsRecord.collection.doc(animationId);

  Stream<_AnimationProgressData> _progressStream() {
    if (currentUserUid.isEmpty) {
      return Stream.value(const _AnimationProgressData());
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserUid)
        .collection('animations')
        .doc(animationId)
        .snapshots()
        .map((snapshot) {
      final data = snapshot.data() ?? const <String, dynamic>{};
      final rawVisited = data['visited_merchants'];
      final visitedMerchants = rawVisited is Iterable
          ? rawVisited.map((e) => e.toString()).toList()
          : const <String>[];
      final qualified = data['qualified'] == true;
      return _AnimationProgressData(
        visitedMerchants: visitedMerchants,
        qualified: qualified,
      );
    });
  }

  Stream<List<GamesRecord>> _animationGamesStream() {
    return GamesRecord.collection
        .where('animation_id', isEqualTo: animationId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => GamesRecord.fromSnapshot(doc))
              .toList(),
        );
  }

  String _formatPrizeLabel(GamesRecord game) {
    if (game.prizeValue <= 0) {
      return 'Gains instantanes';
    }

    final hasDecimals = game.prizeValue % 1 != 0;
    return hasDecimals
        ? '${game.prizeValue.toStringAsFixed(2).replaceAll('.', ',')} EUR'
        : '${game.prizeValue.toStringAsFixed(0)} EUR';
  }

  String _formatAnimationDates(BuildContext context, AnimationsRecord animation) {
    final locale = FFLocalizations.of(context).languageCode;
    final start = animation.startDate != null
        ? dateTimeFormat('d/M/y', animation.startDate, locale: locale)
        : '-';
    final end = animation.endDate != null
        ? dateTimeFormat('d/M/y', animation.endDate, locale: locale)
        : '-';
    return 'Du $start au $end';
  }

  static Future<EnseignesRecord?> loadEnseigne(
    DocumentReference? enseigneRef,
  ) async {
    if (enseigneRef == null) {
      return null;
    }

    try {
      return await EnseignesRecord.getDocumentOnce(enseigneRef);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openGameDetail(
    BuildContext context,
    GamesRecord game, {
    EnseignesRecord? enseigne,
  }) async {
    final resolvedEnseigne = enseigne ?? await loadEnseigne(game.enseigneId);

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
          game,
          ParamType.Document,
        ),
        'enseigneDoc': enseigneParam,
      }.withoutNulls,
      extra: <String, dynamic>{
        'gameDoc': game,
        if (resolvedEnseigne != null) 'enseigneDoc': resolvedEnseigne,
        'source': 'campaign',
        kTransitionInfoKey: const TransitionInfo(
          hasTransition: true,
          transitionType: PageTransitionType.rightToLeft,
        ),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AnimationsRecord>(
      stream: AnimationsRecord.getDocument(_animationRef),
      builder: (context, animationSnapshot) {
        if (animationSnapshot.hasError) {
          return _AnimationDetailScaffold(
            title: 'Animation',
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
          return _AnimationDetailScaffold(
            title: 'Animation',
            body: const _CenteredState(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final animation = animationSnapshot.data!;

        return _AnimationDetailScaffold(
          title: animation.name.isNotEmpty ? animation.name : 'Animation',
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
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 200.0,
                          child: animation.coverImage.isNotEmpty
                              ? Image.network(
                                  animation.coverImage,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return _BannerPlaceholder(
                                      label: animation.name,
                                    );
                                  },
                                )
                              : _BannerPlaceholder(
                                  label: animation.name,
                                ),
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionTitle(
                                title: 'Gros lot final',
                              ),
                              const SizedBox(height: 12.0),
                              _InfoCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (animation.prizeImage.isNotEmpty)
                                      ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(16.0),
                                        child: Image.network(
                                          animation.prizeImage,
                                          width: double.infinity,
                                          height: 180.0,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  const SizedBox.shrink(),
                                        ),
                                      ),
                                    if (animation.prizeImage.isNotEmpty)
                                      const SizedBox(height: 14.0),
                                    Text(
                                      animation.prizeDescription.isNotEmpty
                                          ? animation.prizeDescription
                                          : 'Lot final a venir',
                                      style: FlutterFlowTheme.of(context)
                                          .bodyLarge
                                          .override(
                                            font: GoogleFonts.inter(
                                              fontWeight: FontWeight.w600,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .bodyLarge
                                                      .fontStyle,
                                            ),
                                            letterSpacing: 0.0,
                                          ),
                                    ),
                                    const SizedBox(height: 10.0),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.calendar_today_rounded,
                                          size: 18.0,
                                          color:
                                              FlutterFlowTheme.of(context)
                                                  .primary,
                                        ),
                                        const SizedBox(width: 8.0),
                                        Expanded(
                                          child: Text(
                                            _formatAnimationDates(
                                              context,
                                              animation,
                                            ),
                                            style: FlutterFlowTheme.of(context)
                                                .bodyMedium
                                                .override(
                                                  font: GoogleFonts.inter(
                                                    fontWeight: FontWeight.w500,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodyMedium
                                                            .fontStyle,
                                                  ),
                                                  letterSpacing: 0.0,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20.0),
                              _SectionTitle(
                                title: 'Ta progression',
                              ),
                              const SizedBox(height: 12.0),
                              _ProgressCard(
                                progress: progress,
                                threshold: animation.threshold,
                              ),
                              const SizedBox(height: 20.0),
                              _SectionTitle(
                                title: 'Commerces participants',
                              ),
                              const SizedBox(height: 12.0),
                              if (hasGamesError)
                                _InfoCard(
                                  child: Text(
                                    'Impossible de charger les jeux participants.',
                                    style:
                                        FlutterFlowTheme.of(context).bodyMedium,
                                  ),
                                )
                              else if (!gamesSnapshot.hasData)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24.0),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else if (games.isEmpty)
                                _InfoCard(
                                  child: Text(
                                    'Aucun jeu participant pour le moment.',
                                    style:
                                        FlutterFlowTheme.of(context).bodyMedium,
                                  ),
                                )
                              else
                                Column(
                                  children: games.map((game) {
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 16.0),
                                      child: _AnimationGameTile(
                                        game: game,
                                        prizeText: _formatPrizeLabel(game),
                                        endDateText: game.endDate != null
                                            ? 'Valable jusqu\'au : ${dateTimeFormat(
                                                'd/M/y',
                                                game.endDate,
                                                locale:
                                                    FFLocalizations.of(context)
                                                        .languageCode,
                                              )}'
                                            : 'Valable jusqu\'au : -',
                                        onOpen: game.accessMode ==
                                                AccessMode.public
                                            ? () => _openGameDetail(
                                                  context,
                                                  game,
                                                )
                                            : null,
                                      ),
                                    );
                                  }).toList(),
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

class _AnimationGameTile extends StatelessWidget {
  const _AnimationGameTile({
    required this.game,
    required this.prizeText,
    required this.endDateText,
    this.onOpen,
  });

  final GamesRecord game;
  final String prizeText;
  final String endDateText;
  final Future<void> Function()? onOpen;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EnseignesRecord?>(
      future: AnimationDetailPage.loadEnseigne(game.enseigneId),
      builder: (context, snapshot) {
        final enseigne = snapshot.data;
        final storeName = (enseigne?.name ?? game.enseigneName).trim();
        final city = (enseigne?.city ?? '').trim();
        final isQrOnly = game.accessMode == AccessMode.qr_only;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GameCardWidget(
              title: game.name,
              imageUrl: game.photo,
              storeName: storeName.isNotEmpty ? storeName : 'Commerce partenaire',
              city: city,
              prizeText: prizeText,
              endDateText: endDateText,
              gameAccessType: game.type,
              accessMode: game.accessMode,
              width: double.infinity,
              onTap: isQrOnly
                  ? null
                  : () async {
                      await onOpen?.call();
                    },
            ),
            const SizedBox(height: 10.0),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isQrOnly
                    ? null
                    : () async {
                        await onOpen?.call();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isQrOnly
                      ? const Color(0xFFE5E7EB)
                      : FlutterFlowTheme.of(context).primary,
                  foregroundColor: isQrOnly
                      ? const Color(0xFF6B7280)
                      : Colors.white,
                  disabledBackgroundColor: const Color(0xFFE5E7EB),
                  disabledForegroundColor: const Color(0xFF6B7280),
                  minimumSize: const Size.fromHeight(48.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14.0),
                  ),
                  elevation: 0.0,
                ),
                child: Text(
                  isQrOnly ? 'Disponible en commerce' : 'Voir le jeu',
                  style: GoogleFonts.inter(
                    fontSize: 15.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        );
      },
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
    final visitedCount = progress.visitedMerchants.length;
    final progressValue = (visitedCount / safeThreshold).clamp(0.0, 1.0);

    return _InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$visitedCount/$safeThreshold commercants visites',
            style: FlutterFlowTheme.of(context).titleMedium.override(
                  font: GoogleFonts.interTight(
                    fontWeight: FontWeight.w700,
                    fontStyle:
                        FlutterFlowTheme.of(context).titleMedium.fontStyle,
                  ),
                  letterSpacing: 0.0,
                ),
          ),
          const SizedBox(height: 12.0),
          ClipRRect(
            borderRadius: BorderRadius.circular(999.0),
            child: LinearProgressIndicator(
              value: progressValue,
              minHeight: 12.0,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: AlwaysStoppedAnimation<Color>(
                FlutterFlowTheme.of(context).primary,
              ),
            ),
          ),
          if (progress.qualified) ...[
            const SizedBox(height: 14.0),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 8.0,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(999.0),
              ),
              child: Text(
                'Qualifie pour le tirage !',
                style: FlutterFlowTheme.of(context).bodyMedium.override(
                      font: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontStyle:
                            FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                      ),
                      color: const Color(0xFF2E7D32),
                      letterSpacing: 0.0,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnimationDetailScaffold extends StatelessWidget {
  const _AnimationDetailScaffold({
    required this.title,
    required this.body,
  });

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      appBar: AppBar(
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        elevation: 0.0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.safePop(),
        ),
        title: Text(
          title,
          style: FlutterFlowTheme.of(context).titleLarge.override(
                font: GoogleFonts.interTight(
                  fontWeight: FontWeight.w700,
                  fontStyle:
                      FlutterFlowTheme.of(context).titleLarge.fontStyle,
                ),
                letterSpacing: 0.0,
              ),
        ),
      ),
      body: body,
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(20.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14.0,
            offset: const Offset(0.0, 4.0),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: FlutterFlowTheme.of(context).titleLarge.override(
            font: GoogleFonts.interTight(
              fontWeight: FontWeight.w700,
              fontStyle: FlutterFlowTheme.of(context).titleLarge.fontStyle,
            ),
            letterSpacing: 0.0,
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

class _BannerPlaceholder extends StatelessWidget {
  const _BannerPlaceholder({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FlutterFlowTheme.of(context).primary.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: FlutterFlowTheme.of(context).titleLarge.override(
              font: GoogleFonts.interTight(
                fontWeight: FontWeight.w700,
                fontStyle: FlutterFlowTheme.of(context).titleLarge.fontStyle,
              ),
              letterSpacing: 0.0,
            ),
      ),
    );
  }
}

class _AnimationProgressData {
  const _AnimationProgressData({
    this.visitedMerchants = const <String>[],
    this.qualified = false,
  });

  final List<String> visitedMerchants;
  final bool qualified;
}
