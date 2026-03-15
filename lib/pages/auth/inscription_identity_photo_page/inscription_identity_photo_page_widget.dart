import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/backend/firebase_storage/storage.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_animations.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/flutter_flow/upload_data.dart';
import '/index.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'inscription_identity_photo_page_model.dart';
export 'inscription_identity_photo_page_model.dart';

class InscriptionIdentityPhotoPageWidget extends StatefulWidget {
  const InscriptionIdentityPhotoPageWidget({super.key});

  static String routeName = 'InscriptionIdentityPhotoPage';
  static String routePath = 'inscriptionIdentityPhotoPage';

  @override
  State<InscriptionIdentityPhotoPageWidget> createState() =>
      _InscriptionIdentityPhotoPageWidgetState();
}

class _InscriptionIdentityPhotoPageWidgetState
    extends State<InscriptionIdentityPhotoPageWidget>
    with TickerProviderStateMixin {
  late InscriptionIdentityPhotoPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  final animationsMap = <String, AnimationInfo>{};

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => InscriptionIdentityPhotoPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'InscriptionIdentityPhotoPage'});
    animationsMap.addAll({
      'containerOnPageLoadAnimation': AnimationInfo(
        trigger: AnimationTrigger.onPageLoad,
        effectsBuilder: () => [
          VisibilityEffect(duration: 1.ms),
          FadeEffect(
            curve: Curves.easeInOut,
            delay: 0.0.ms,
            duration: 300.0.ms,
            begin: 0.0,
            end: 1.0,
          ),
          ScaleEffect(
            curve: Curves.bounceOut,
            delay: 0.0.ms,
            duration: 300.0.ms,
            begin: const Offset(0.6, 1.0),
            end: const Offset(1.0, 1.0),
          ),
        ],
      ),
      'textOnPageLoadAnimation': AnimationInfo(
        trigger: AnimationTrigger.onPageLoad,
        effectsBuilder: () => [
          VisibilityEffect(duration: 100.ms),
          FadeEffect(
            curve: Curves.easeInOut,
            delay: 100.0.ms,
            duration: 400.0.ms,
            begin: 0.0,
            end: 1.0,
          ),
          MoveEffect(
            curve: Curves.easeInOut,
            delay: 100.0.ms,
            duration: 400.0.ms,
            begin: const Offset(0.0, 30.0),
            end: const Offset(0.0, 0.0),
          ),
        ],
      ),
    });
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: PopScope(
        canPop: false,
        child: Scaffold(
          key: scaffoldKey,
          backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
          body: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        FlutterFlowTheme.of(context).primary,
                        FlutterFlowTheme.of(context).error,
                        FlutterFlowTheme.of(context).tertiary
                      ],
                      stops: const [0.0, 0.5, 1.0],
                      begin: const AlignmentDirectional(-1.0, -1.0),
                      end: const AlignmentDirectional(1.0, 1.0),
                    ),
                  ),
                  child: Container(
                    width: 100.0,
                    height: 200.0,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0x00FFFFFF),
                          FlutterFlowTheme.of(context).secondaryBackground
                        ],
                        stops: const [0.0, 1.0],
                        begin: const AlignmentDirectional(0.0, -1.0),
                        end: const AlignmentDirectional(0, 1.0),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 226.0,
                          height: 76.0,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16.0),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8.0),
                            child: Image.asset(
                              'assets/images/Logo_(1).png',
                              width: 200.0,
                              height: 200.0,
                              fit: BoxFit.fitWidth,
                            ),
                          ),
                        ).animateOnPageLoad(
                            animationsMap['containerOnPageLoadAnimation']!),
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 12.0, 0.0, 0.0),
                          child: Text(
                            'Information compémentaire',
                            style: FlutterFlowTheme.of(context)
                                .headlineSmall
                                .override(
                                  font: GoogleFonts.interTight(
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .headlineSmall
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .headlineSmall
                                        .fontStyle,
                                  ),
                                  letterSpacing: 0.0,
                                  fontWeight: FlutterFlowTheme.of(context)
                                      .headlineSmall
                                      .fontWeight,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .headlineSmall
                                      .fontStyle,
                                ),
                          ).animateOnPageLoad(
                              animationsMap['textOnPageLoadAnimation']!),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20.0, 0.0, 20.0, 0.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Align(
                        alignment: const AlignmentDirectional(-1.0, 0.0),
                        child: Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 10.0),
                          child: Text(
                            'Photo du propriétaire de la carte :',
                            style: FlutterFlowTheme.of(context)
                                .labelLarge
                                .override(
                                  font: GoogleFonts.inter(
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .labelLarge
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .labelLarge
                                        .fontStyle,
                                  ),
                                  letterSpacing: 0.0,
                                  fontWeight: FlutterFlowTheme.of(context)
                                      .labelLarge
                                      .fontWeight,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .labelLarge
                                      .fontStyle,
                                ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                            0.0, 0.0, 0.0, 16.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8.0),
                          child: Image.memory(
                            _model.uploadedLocalFile_uploadDataSelfieCommercant
                                    .bytes ??
                                Uint8List.fromList([]),
                            width: double.infinity,
                            height: 150.0,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Padding(
                        padding:
                            const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 16.0),
                        child: FFButtonWidget(
                          onPressed: () async {
                            final selectedMedia = await selectMedia(
                              multiImage: false,
                            );
                            if (selectedMedia != null &&
                                selectedMedia.every((m) => validateFileFormat(
                                    m.storagePath, context))) {
                              safeSetState(() => _model
                                      .isDataUploading_uploadDataSelfieCommercant =
                                  true);
                              var selectedUploadedFiles = <FFUploadedFile>[];

                              try {
                                selectedUploadedFiles = selectedMedia
                                    .map((m) => FFUploadedFile(
                                          name: m.storagePath.split('/').last,
                                          bytes: m.bytes,
                                          height: m.dimensions?.height,
                                          width: m.dimensions?.width,
                                          blurHash: m.blurHash,
                                          originalFilename: m.originalFilename,
                                        ))
                                    .toList();
                              } finally {
                                _model.isDataUploading_uploadDataSelfieCommercant =
                                    false;
                              }
                              if (selectedUploadedFiles.length ==
                                  selectedMedia.length) {
                                safeSetState(() {
                                  _model.uploadedLocalFile_uploadDataSelfieCommercant =
                                      selectedUploadedFiles.first;
                                });
                              } else {
                                safeSetState(() {});
                                return;
                              }
                            }
                          },
                          text:
                              _model.isDataUploading_uploadDataSelfieCommercant
                                  ? 'Modifier la photo'
                                  : 'Prendre une photo',
                          options: FFButtonOptions(
                            width: double.infinity,
                            height: 40.0,
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                16.0, 0.0, 16.0, 0.0),
                            iconPadding: const EdgeInsetsDirectional.fromSTEB(
                                0.0, 0.0, 0.0, 0.0),
                            color: FlutterFlowTheme.of(context).primary,
                            textStyle: FlutterFlowTheme.of(context)
                                .titleSmall
                                .override(
                                  font: GoogleFonts.interTight(
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .titleSmall
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .titleSmall
                                        .fontStyle,
                                  ),
                                  color: Colors.white,
                                  letterSpacing: 0.0,
                                  fontWeight: FlutterFlowTheme.of(context)
                                      .titleSmall
                                      .fontWeight,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .titleSmall
                                      .fontStyle,
                                ),
                            elevation: 0.0,
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                      ),
                      Padding(
                        padding:
                            const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 16.0),
                        child: FFButtonWidget(
                          onPressed:
                              ((_model.uploadedLocalFile_uploadDataSelfieCommercant
                                              .bytes?.isEmpty ??
                                          true))
                                  ? null
                                  : () async {
                                      {
                                        safeSetState(() => _model
                                                .isDataUploading_uploadDataPhotoIdentity =
                                            true);
                                        var selectedUploadedFiles =
                                            <FFUploadedFile>[];
                                        var selectedMedia = <SelectedFile>[];
                                        var downloadUrls = <String>[];
                                        try {
                                          selectedUploadedFiles = _model
                                                  .uploadedLocalFile_uploadDataSelfieCommercant
                                                  .bytes!
                                                  .isNotEmpty
                                              ? [
                                                  _model
                                                      .uploadedLocalFile_uploadDataSelfieCommercant
                                                ]
                                              : <FFUploadedFile>[];
                                          selectedMedia =
                                              selectedFilesFromUploadedFiles(
                                            selectedUploadedFiles,
                                          );
                                          downloadUrls = (await Future.wait(
                                            selectedMedia.map(
                                              (m) async => await uploadData(
                                                  m.storagePath, m.bytes),
                                            ),
                                          ))
                                              .where((u) => u != null)
                                              .map((u) => u!)
                                              .toList();
                                        } finally {
                                          _model.isDataUploading_uploadDataPhotoIdentity =
                                              false;
                                        }
                                        if (selectedUploadedFiles.length ==
                                                selectedMedia.length &&
                                            downloadUrls.length ==
                                                selectedMedia.length) {
                                          safeSetState(() {
                                            _model.uploadedLocalFile_uploadDataPhotoIdentity =
                                                selectedUploadedFiles.first;
                                            _model.uploadedFileUrl_uploadDataPhotoIdentity =
                                                downloadUrls.first;
                                          });
                                        } else {
                                          safeSetState(() {});
                                          return;
                                        }
                                      }

                                      _model.result =
                                          await queryIdentityDocumentsRecordOnce(
                                        parent: currentUserReference,
                                        singleRecord: true,
                                      ).then((s) => s.firstOrNull);
                                      if ((_model.result
                                                      ?.idPhotoCommercantUrl !=
                                                  null &&
                                              _model.result
                                                      ?.idPhotoCommercantUrl !=
                                                  '') ||
                                          (_model.result?.idFrontCardUrl !=
                                                  null &&
                                              _model.result?.idFrontCardUrl !=
                                                  '')) {
                                        await _model.result!.reference.update(
                                            createIdentityDocumentsRecordData(
                                          idPhotoCommercantUrl: _model
                                              .uploadedFileUrl_uploadDataPhotoIdentity,
                                        ));
                                      } else {
                                        await IdentityDocumentsRecord.createDoc(
                                                currentUserReference!)
                                            .set(
                                                createIdentityDocumentsRecordData(
                                          idPhotoCommercantUrl: _model
                                              .uploadedFileUrl_uploadDataPhotoIdentity,
                                        ));
                                      }

                                      await currentUserReference!
                                          .update(createUsersRecordData(
                                        accountStatus:
                                            AccountStatus.pendingValidation,
                                      ));
                                      if (!context.mounted) return;

                                      context.goNamed(
                                          WaitingValidationPageWidget
                                              .routeName);

                                      safeSetState(() {});
                                    },
                          text: 'Valider',
                          options: FFButtonOptions(
                            width: double.infinity,
                            height: 40.0,
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                16.0, 0.0, 16.0, 0.0),
                            iconPadding: const EdgeInsetsDirectional.fromSTEB(
                                0.0, 0.0, 0.0, 0.0),
                            color: FlutterFlowTheme.of(context).primary,
                            textStyle: FlutterFlowTheme.of(context)
                                .titleSmall
                                .override(
                                  font: GoogleFonts.interTight(
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .titleSmall
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .titleSmall
                                        .fontStyle,
                                  ),
                                  color: Colors.white,
                                  letterSpacing: 0.0,
                                  fontWeight: FlutterFlowTheme.of(context)
                                      .titleSmall
                                      .fontWeight,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .titleSmall
                                      .fontStyle,
                                ),
                            elevation: 0.0,
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                      ),
                    ],
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
