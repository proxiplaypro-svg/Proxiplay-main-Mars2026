import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'legal_page_model.dart';
export 'legal_page_model.dart';

/// page regroupent les mentions légales, cgv, cgu, rgpd et tout autre
/// document
class LegalPageWidget extends StatefulWidget {
  const LegalPageWidget({super.key});

  static String routeName = 'legalPage';
  static String routePath = 'legalPage';

  @override
  State<LegalPageWidget> createState() => _LegalPageWidgetState();
}

class _LegalPageWidgetState extends State<LegalPageWidget> {
  static final Uri _legalUri = Uri.parse('https://www.proxiplay.fr/legal.html');

  late LegalPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  bool _openFailed = false;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => LegalPageModel());

    logFirebaseEvent('screen_view', parameters: {'screen_name': 'legalPage'});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openLegalDocuments();
    });
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  Future<void> _openLegalDocuments() async {
    bool opened = false;
    try {
      opened = await launchUrl(
        _legalUri,
        mode: LaunchMode.inAppBrowserView,
      );
    } catch (_) {
      opened = false;
    }

    if (!mounted) {
      return;
    }

    if (opened) {
      context.pop();
      return;
    }

    setState(() => _openFailed = true);
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
        backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
          automaticallyImplyLeading: false,
          leading: FlutterFlowIconButton(
            borderRadius: 20.0,
            buttonSize: 40.0,
            icon: Icon(
              Icons.arrow_back_rounded,
              color: FlutterFlowTheme.of(context).primaryText,
              size: 24.0,
            ),
            onPressed: () async {
              context.pop();
            },
          ),
          title: Text(
            'Documents légaux',
            style: FlutterFlowTheme.of(context).headlineMedium.override(
                  font: GoogleFonts.interTight(
                    fontWeight:
                        FlutterFlowTheme.of(context).headlineMedium.fontWeight,
                    fontStyle:
                        FlutterFlowTheme.of(context).headlineMedium.fontStyle,
                  ),
                  fontSize: 20.0,
                  letterSpacing: 0.0,
                  fontWeight:
                      FlutterFlowTheme.of(context).headlineMedium.fontWeight,
                  fontStyle:
                      FlutterFlowTheme.of(context).headlineMedium.fontStyle,
                ),
          ),
          actions: const [],
          centerTitle: false,
          elevation: 0.0,
        ),
        body: SafeArea(
          top: true,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_openFailed) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16.0),
                    Text(
                      'Ouverture des documents légaux…',
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
                  ] else ...[
                    Text(
                      'Impossible d’ouvrir les documents pour le moment.',
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
                    const SizedBox(height: 16.0),
                    ElevatedButton(
                      onPressed: _openLegalDocuments,
                      child: const Text('Réessayer'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
