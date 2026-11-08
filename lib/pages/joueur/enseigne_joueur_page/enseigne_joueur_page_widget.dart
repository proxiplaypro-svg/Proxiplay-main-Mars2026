import '/backend/backend.dart';
import '/components/app_bar_joueur_widget.dart';
import '/components/custom_nav_bar_joueur_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'enseigne_joueur_page_model.dart';
import 'merchant_directory_logic.dart';
import 'merchant_directory_source.dart';
import 'merchant_directory_view.dart';
export 'enseigne_joueur_page_model.dart';

class EnseigneJoueurPageWidget extends StatefulWidget {
  const EnseigneJoueurPageWidget({super.key});

  static String routeName = 'EnseigneJoueurPage';
  static String routePath = 'enseigneJoueurPage';

  @override
  State<EnseigneJoueurPageWidget> createState() =>
      _EnseigneJoueurPageWidgetState();
}

class _EnseigneJoueurPageWidgetState extends State<EnseigneJoueurPageWidget> {
  late EnseigneJoueurPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  late StreamSubscription<bool> _keyboardVisibilitySubscription;
  bool _isKeyboardVisible = false;
  final MerchantDirectorySource _directorySource =
      FirestoreMerchantDirectorySource();

  void _openMerchant(DirectoryMerchant merchant) {
    final record = merchant.record;
    if (record is! EnseignesRecord) return;
    context.pushNamed(
      EnseigneDetailJoueurPageWidget.routeName,
      queryParameters: {
        'enseigneDoc': serializeParam(record, ParamType.Document),
      }.withoutNulls,
      extra: <String, dynamic>{'enseigneDoc': record},
    );
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => EnseigneJoueurPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'EnseigneJoueurPage'});
    if (!isWeb) {
      _keyboardVisibilitySubscription =
          KeyboardVisibilityController().onChange.listen((bool visible) {
        safeSetState(() {
          _isKeyboardVisible = visible;
        });
      });
    }
  }

  @override
  void dispose() {
    _model.dispose();

    if (!isWeb) {
      _keyboardVisibilitySubscription.cancel();
    }
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
          resizeToAvoidBottomInset: false,
          backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(100.0),
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0.0,
              scrolledUnderElevation: 0.0,
              shadowColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              automaticallyImplyLeading: false,
              actions: const [],
              flexibleSpace: FlexibleSpaceBar(
                title: Align(
                  alignment: const AlignmentDirectional(0.0, 1.0),
                  child: wrapWithModel(
                    model: _model.appBarJoueurModel,
                    updateCallback: () => safeSetState(() {}),
                    child: const AppBarJoueurWidget(),
                  ),
                ),
                background: const SizedBox.shrink(),
                centerTitle: true,
                expandedTitleScale: 1.0,
                titlePadding:
                    const EdgeInsetsDirectional.fromSTEB(20.0, 30.0, 20.0, 0.0),
              ),
            ),
          ),
          body: SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  fit: BoxFit.cover,
                  image: Image.asset(
                    'assets/images/Background.png',
                  ).image,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          16.0, 24.0, 16.0, 0.0),
                      child: MerchantDirectoryView(
                        source: _directorySource,
                        knownCategories: FFAppConstants.Category,
                        onOpenMerchant: _openMerchant,
                      ),
                    ),
                  ),
                  if (!(isWeb
                      ? MediaQuery.viewInsetsOf(context).bottom > 0
                      : _isKeyboardVisible))
                    wrapWithModel(
                      model: _model.customNavBarJoueurModel,
                      updateCallback: () => safeSetState(() {}),
                      child: const CustomNavBarJoueurWidget(
                        indexActive: 3,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
