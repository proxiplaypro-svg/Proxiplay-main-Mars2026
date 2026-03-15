import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/backend/firebase_storage/storage.dart';
import '/backend/schema/enums/enums.dart';
import '/components/validation_card_widget.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/flutter_flow/upload_data.dart';
import '/custom_code/actions/index.dart' as actions;
import '/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webviewx_plus/webviewx_plus.dart';
import 'add_game_commercant_page_model.dart';
export 'add_game_commercant_page_model.dart';

/// formulaire pour créer un jeu
class AddGameCommercantPageWidget extends StatefulWidget {
  const AddGameCommercantPageWidget({
    super.key,
    required this.enseigneRef,
    required this.enseigne,
    this.templateGame,
  });

  final DocumentReference? enseigneRef;
  final String? enseigne;
  final GamesRecord? templateGame;

  static String routeName = 'AddGameCommercantPage';
  static String routePath = 'addGameCommercantPage';

  @override
  State<AddGameCommercantPageWidget> createState() =>
      _AddGameCommercantPageWidgetState();
}

class _AddGameCommercantPageWidgetState
    extends State<AddGameCommercantPageWidget> {
  late AddGameCommercantPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  static const Color _premiumRaspberry = Color(0xFFA0134D);
  static const Color _premiumFieldBorder = Color(0xFFD9D3EF);

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => AddGameCommercantPageModel());

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'AddGameCommercantPage'});
    _model.textController1 ??= TextEditingController();
    _model.textFieldFocusNode1 ??= FocusNode();

    _model.textController2 ??= TextEditingController();
    _model.textFieldFocusNode2 ??= FocusNode();

    _model.textController3 ??= TextEditingController();
    _model.textFieldFocusNode3 ??= FocusNode();
    _model.textController4 ??= TextEditingController();
    _model.textFieldFocusNode4 ??= FocusNode();

    _model.switchValue = false;
    _prefillFromTemplate();
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  BoxDecoration _buildSectionDecoration(BuildContext context) {
    return BoxDecoration(
      color: FlutterFlowTheme.of(context).secondaryBackground,
      borderRadius: BorderRadius.circular(24.0),
      border: Border.all(
        color: _premiumRaspberry.withValues(alpha: 0.06),
        width: 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.035),
          blurRadius: 18.0,
          offset: const Offset(0.0, 8.0),
        ),
        BoxShadow(
          color: _premiumRaspberry.withValues(alpha: 0.03),
          blurRadius: 24.0,
          offset: const Offset(0.0, 12.0),
        ),
      ],
    );
  }

  InputDecoration _buildPremiumFieldDecoration({
    required String hintText,
    String? labelText,
    Widget? suffixIcon,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      hintStyle: theme.labelMedium.override(
        font: GoogleFonts.inter(
          fontWeight: FontWeight.w500,
        ),
        color: theme.fieldText.withValues(alpha: 0.75),
        fontSize: 14.0,
        letterSpacing: 0.0,
      ),
      labelStyle: theme.labelMedium.override(
        font: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
        ),
        color: theme.fieldText.withValues(alpha: 0.9),
        letterSpacing: 0.0,
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(
          color: _premiumFieldBorder,
          width: 1.4,
        ),
        borderRadius: BorderRadius.circular(16.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: _premiumRaspberry.withValues(alpha: 0.28),
          width: 1.6,
        ),
        borderRadius: BorderRadius.circular(16.0),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: theme.error,
          width: 1.6,
        ),
        borderRadius: BorderRadius.circular(16.0),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: theme.error,
          width: 1.6,
        ),
        borderRadius: BorderRadius.circular(16.0),
      ),
      filled: true,
      fillColor: theme.fieldBg.withValues(alpha: 0.94),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
      suffixIcon: suffixIcon,
      suffixIconConstraints:
          const BoxConstraints(minHeight: 24.0, minWidth: 24.0),
    );
  }

  List<Map<String, dynamic>>? _collectSecondaryPrizes() {
    final prizes = <Map<String, dynamic>>[];
    for (final entry in _model.secondaryPrizes) {
      final name = entry.nameController.text.trim();
      final presentation = entry.presentationController.text.trim();
      final countText = entry.countController.text.trim();

      if (name.isEmpty && presentation.isEmpty && countText.isEmpty) {
        continue;
      }
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nom du lot requis')),
        );
        return null;
      }
      if (countText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nombre de lots requis')),
        );
        return null;
      }
      if (!RegExp('^\\d+\$').hasMatch(countText)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Il faut un nombre')),
        );
        return null;
      }

      prizes.add({
        'name': name,
        if (presentation.isNotEmpty) 'presentation': presentation,
        'count': int.parse(countText),
      });
    }
    return prizes;
  }

  double? _parsePriceValue(String? rawValue) {
    if (rawValue == null) {
      return null;
    }
    final normalized = rawValue.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }
    return double.tryParse(normalized);
  }

  String _formatPriceForInput(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  void _prefillFromTemplate() {
    final template = widget.templateGame;
    if (template == null) {
      return;
    }

    final hasMainPrizeData = template.name.trim().isNotEmpty ||
        template.description.trim().isNotEmpty ||
        template.hasPrizeValue();
    _model.mainPrizeEnabled = hasMainPrizeData;
    _model.textController1?.text = template.name;
    _model.textController2?.text = template.description;
    _model.textController3?.text = template.hasPrizeValue()
        ? _formatPriceForInput(template.prizeValue)
        : '';
    _model.textController4?.text = template.name;
    _model.switchValue = template.prohibitedForMinors;
    _model.uploadedFileUrl_uploadDataNyu = template.photo;

    for (final entry in _model.secondaryPrizes) {
      entry.dispose();
    }
    _model.secondaryPrizes.clear();
    for (final prize in template.secondaryPrizes) {
      final entry = SecondaryPrizeEntry();
      entry.nameController.text = (prize['name'] ?? '').toString();
      entry.presentationController.text =
          (prize['presentation'] ?? '').toString();
      entry.countController.text = (prize['count'] ?? '').toString();
      _model.secondaryPrizes.add(entry);
    }
    if (_model.secondaryPrizes.isEmpty) {
      _model.secondaryPrizes.add(SecondaryPrizeEntry());
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
        body: SafeArea(
          top: true,
          child: Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                fit: BoxFit.cover,
                image: Image.asset(
                  'assets/images/Background.png',
                ).image,
              ),
            ),
            child: Form(
              key: _model.formKey,
              autovalidateMode: AutovalidateMode.disabled,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20.0, 20.0, 20.0, 20.0),
                child: ListView(
                  padding: EdgeInsets.zero,
                  scrollDirection: Axis.vertical,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        FlutterFlowIconButton(
                          borderColor: Colors.transparent,
                          borderRadius: 30.0,
                          borderWidth: 1.0,
                          buttonSize: 50.0,
                          fillColor: Colors.transparent,
                          icon: Icon(
                            Icons.chevron_left_rounded,
                            color: FlutterFlowTheme.of(context).primaryText,
                            size: 30.0,
                          ),
                          onPressed: () async {
                            context.pop();
                          },
                        ),
                      ],
                    ),
                    Container(
                      width: double.infinity,
                      decoration: _buildSectionDecoration(context),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                            20.0, 20.0, 20.0, 20.0),
                        child: ListView(
                          padding: EdgeInsets.zero,
                          primary: false,
                          shrinkWrap: true,
                          scrollDirection: Axis.vertical,
                          children: [
                            Text(
                              'Créer un nouveau jeu',
                              textAlign: TextAlign.center,
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
                                    color: FlutterFlowTheme.of(context).primaryText,
                                    fontSize: 22.0,
                                    letterSpacing: -0.4,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  0.0, 16.0, 0.0, 10.0),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    16.0, 14.0, 12.0, 14.0),
                                decoration: BoxDecoration(
                                  color: _premiumRaspberry.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(18.0),
                                  border: Border.all(
                                    color: _premiumRaspberry.withValues(alpha: 0.10),
                                    width: 1.0,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Lot principal',
                                            style: FlutterFlowTheme.of(context)
                                                .titleSmall
                                                .override(
                                                  font: GoogleFonts.interTight(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                  fontSize: 18.0,
                                                  letterSpacing: -0.2,
                                                ),
                                          ),
                                        ),
                                        Switch(
                                          value: _model.mainPrizeEnabled,
                                          activeThumbColor: Colors.white,
                                          activeTrackColor: _premiumRaspberry,
                                          onChanged: (val) {
                                            setState(() {
                                              _model.mainPrizeEnabled = val;
                                              if (!val) {
                                                _model.textController1?.clear();
                                                _model.textController2?.clear();
                                                _model.textController3?.clear();
                                                _model.textController4?.clear();
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                    Text(
                                      'Tirage au sort final parmi les participants',
                                      style: FlutterFlowTheme.of(context)
                                          .bodySmall
                                          .override(
                                            font: GoogleFonts.inter(
                                              fontWeight: FontWeight.w500,
                                            ),
                                            color: FlutterFlowTheme.of(context)
                                                .secondaryText,
                                            letterSpacing: 0.0,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_model.mainPrizeEnabled)
                              TextFormField(
                                controller: _model.textController1,
                                focusNode: _model.textFieldFocusNode1,
                                autofocus: false,
                                obscureText: false,
                                decoration: _buildPremiumFieldDecoration(
                                  hintText: 'ex : Un dîner pour 2',
                                ),
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
                                      color: FlutterFlowTheme.of(context)
                                          .fieldText,
                                      letterSpacing: 0.0,
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontStyle,
                                    ),
                                onChanged: (value) {
                                  if (_model.mainPrizeEnabled) {
                                    _model.textController4?.text = value.trim();
                                  }
                                },
                                validator: _model.textController1Validator
                                    .asValidator(context),
                              ),
                            if (_model.mainPrizeEnabled)
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    0.0, 0.0, 0.0, 16.0),
                                child: TextFormField(
                                  controller: _model.textController2,
                                  focusNode: _model.textFieldFocusNode2,
                                  autofocus: false,
                                  obscureText: false,
                                  decoration: _buildPremiumFieldDecoration(
                                    hintText:
                                        'ex : Un menu du marché pour 2, hors boisson',
                                  ),
                                  style: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .fieldText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                  maxLines: 5,
                                  validator: _model.textController2Validator
                                      .asValidator(context),
                                ),
                              ),
                            if (_model.mainPrizeEnabled)
                              TextFormField(
                                controller: _model.textController3,
                                focusNode: _model.textFieldFocusNode3,
                                autofocus: false,
                                obscureText: false,
                                decoration: _buildPremiumFieldDecoration(
                                  hintText: 'Valeur estimée du lot principal',
                                  labelText: 'Valeur estimée du lot principal',
                                  suffixIcon: Icon(
                                    Icons.euro_rounded,
                                    color:
                                        _premiumRaspberry.withValues(alpha: 0.82),
                                    size: 20.0,
                                  ),
                                ),
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
                                      color: FlutterFlowTheme.of(context)
                                          .fieldText,
                                      letterSpacing: 0.0,
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontStyle,
                                    ),
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9,\.]'),
                                  ),
                                ],
                                validator: _model.textController3Validator
                                    .asValidator(context),
                              ),
                          ].divide(const SizedBox(height: 14.0)),
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      decoration: _buildSectionDecoration(context),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                            20.0, 20.0, 20.0, 20.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Lots à gains immédiats lors du grattage',
                                        style: FlutterFlowTheme.of(context)
                                            .headlineSmall
                                            .override(
                                              font: GoogleFonts.interTight(
                                                fontWeight: FontWeight.w800,
                                              ),
                                              fontSize: 19.0,
                                              letterSpacing: -0.3,
                                            ),
                                      ),
                                      const SizedBox(height: 6.0),
                                      Text(
                                        'Ces lots sont remportés immédiatement pendant le jeu.',
                                        style: FlutterFlowTheme.of(context)
                                            .bodySmall
                                            .override(
                                              font: GoogleFonts.inter(
                                                fontWeight: FontWeight.w500,
                                              ),
                                              color: FlutterFlowTheme.of(context)
                                                  .secondaryText,
                                              letterSpacing: 0.0,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12.0),
                                Container(
                                  padding: const EdgeInsetsDirectional.fromSTEB(
                                      10.0, 6.0, 10.0, 6.0),
                                  decoration: BoxDecoration(
                                    color:
                                        _premiumRaspberry.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(999.0),
                                  ),
                                  child: Text(
                                    '${_model.secondaryPrizes.length} lot${_model.secondaryPrizes.length > 1 ? 's' : ''}',
                                    style: FlutterFlowTheme.of(context)
                                        .labelSmall
                                        .override(
                                          font: GoogleFonts.inter(
                                            fontWeight: FontWeight.w700,
                                          ),
                                          color: _premiumRaspberry,
                                          letterSpacing: 0.0,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            Divider(
                              thickness: 1.0,
                              height: 28.0,
                              color: FlutterFlowTheme.of(context)
                                  .alternate
                                  .withValues(alpha: 0.8),
                            ),
                            if (!_model.mainPrizeEnabled)
                              TextFormField(
                                controller: _model.textController4,
                                focusNode: _model.textFieldFocusNode4,
                                autofocus: false,
                                obscureText: false,
                                decoration: InputDecoration(
                                  labelText: 'Titre du jeu',
                                  labelStyle: FlutterFlowTheme.of(context)
                                      .labelMedium
                                      .override(
                                        font: GoogleFonts.inter(
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .labelMedium
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .labelMedium
                                                  .fontStyle,
                                        ),
                                        color: FlutterFlowTheme.of(context)
                                            .fieldText,
                                        letterSpacing: 0.0,
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .labelMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .labelMedium
                                            .fontStyle,
                                      ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                      color: Color(0x00000000),
                                      width: 2.0,
                                    ),
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color:
                                          FlutterFlowTheme.of(context).primary,
                                      width: 2.0,
                                    ),
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: FlutterFlowTheme.of(context).error,
                                      width: 2.0,
                                    ),
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: FlutterFlowTheme.of(context).error,
                                      width: 2.0,
                                    ),
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  filled: true,
                                  fillColor:
                                      FlutterFlowTheme.of(context).fieldBg,
                                  contentPadding: const EdgeInsets.all(24.0),
                                ),
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
                                      color: FlutterFlowTheme.of(context)
                                          .fieldText,
                                      letterSpacing: 0.0,
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontStyle,
                                    ),
                                validator: _model.textController4Validator
                                    .asValidator(context),
                              ),
                            Column(
                              children: [
                                ...List.generate(
                                  _model.secondaryPrizes.length,
                                  (index) {
                                    final entry = _model.secondaryPrizes[index];
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 14),
                                      child: Container(
                                        padding: const EdgeInsetsDirectional.fromSTEB(
                                            14.0, 14.0, 14.0, 14.0),
                                        decoration: BoxDecoration(
                                          color: _premiumRaspberry.withValues(
                                              alpha: 0.035),
                                          borderRadius:
                                              BorderRadius.circular(18.0),
                                          border: Border.all(
                                            color: _premiumRaspberry
                                                .withValues(alpha: 0.08),
                                            width: 1.0,
                                          ),
                                        ),
                                        child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                'Lot à gain immédiat ${index + 1}',
                                                style:
                                                    FlutterFlowTheme.of(context)
                                                        .titleSmall
                                                        .override(
                                                          font:
                                                              GoogleFonts.interTight(
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                          letterSpacing: -0.1,
                                                        ),
                                              ),
                                              const Spacer(),
                                              if (_model
                                                      .secondaryPrizes.length >
                                                  1)
                                                IconButton(
                                                  icon: const Icon(Icons.close),
                                                  onPressed: () {
                                                    setState(() {
                                                      _model.secondaryPrizes
                                                          .removeAt(index)
                                                          .dispose();
                                                    });
                                                  },
                                                ),
                                            ],
                                          ),
                                          TextFormField(
                                            controller: entry.nameController,
                                            focusNode: entry.nameFocusNode,
                                            decoration:
                                                _buildPremiumFieldDecoration(
                                              hintText:
                                                  'ex : 20% de réduction hors soldes',
                                            ),
                                            style: FlutterFlowTheme.of(context)
                                                .bodyMedium
                                                .override(
                                                  font: GoogleFonts.inter(
                                                    fontWeight:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodyMedium
                                                            .fontWeight,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodyMedium
                                                            .fontStyle,
                                                  ),
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .fieldText,
                                                  letterSpacing: 0.0,
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontStyle,
                                                ),
                                          ),
                                          const SizedBox(height: 12),
                                          TextFormField(
                                            controller:
                                                entry.presentationController,
                                            focusNode:
                                                entry.presentationFocusNode,
                                            decoration:
                                                _buildPremiumFieldDecoration(
                                              hintText:
                                                  'ex : 20% en caisse, hors soldes et promotions',
                                            ),
                                            style: FlutterFlowTheme.of(context)
                                                .bodyMedium
                                                .override(
                                                  font: GoogleFonts.inter(
                                                    fontWeight:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodyMedium
                                                            .fontWeight,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodyMedium
                                                            .fontStyle,
                                                  ),
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .fieldText,
                                                  letterSpacing: 0.0,
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontStyle,
                                                ),
                                          ),
                                          const SizedBox(height: 12),
                                          TextFormField(
                                            controller: entry.countController,
                                            focusNode: entry.countFocusNode,
                                            autofocus: false,
                                            obscureText: false,
                                            decoration:
                                                _buildPremiumFieldDecoration(
                                              hintText:
                                                  'Nombre de lots',
                                              labelText:
                                                  'Nombre de lots',
                                            ),
                                            style: FlutterFlowTheme.of(context)
                                                .bodyMedium
                                                .override(
                                                  font: GoogleFonts.inter(
                                                    fontWeight:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodyMedium
                                                            .fontWeight,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .bodyMedium
                                                            .fontStyle,
                                                  ),
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .fieldText,
                                                  letterSpacing: 0.0,
                                                  fontWeight:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontWeight,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyMedium
                                                          .fontStyle,
                                                ),
                                            keyboardType: TextInputType.number,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                  },
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        _model.secondaryPrizes
                                            .add(SecondaryPrizeEntry());
                                      });
                                    },
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsetsDirectional.fromSTEB(
                                          14.0, 12.0, 16.0, 12.0),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16.0),
                                      ),
                                      backgroundColor: _premiumRaspberry
                                          .withValues(alpha: 0.06),
                                    ),
                                    icon: const Icon(
                                      Icons.add_circle_outline_rounded,
                                      color: _premiumRaspberry,
                                      size: 18.0,
                                    ),
                                    label: Text(
                                      'Ajouter un lot à gain immédiat',
                                      style: FlutterFlowTheme.of(context)
                                          .titleSmall
                                          .override(
                                            font: GoogleFonts.interTight(
                                              fontWeight: FontWeight.w700,
                                            ),
                                            color: _premiumRaspberry,
                                            fontSize: 15.0,
                                            letterSpacing: -0.1,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ].divide(const SizedBox(height: 16.0)),
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      decoration: _buildSectionDecoration(context),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                            20.0, 20.0, 20.0, 20.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Text(
                              'Image du jeu',
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
                                    fontSize: 20.0,
                                    letterSpacing: -0.3,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            InkWell(
                              splashColor: Colors.transparent,
                              focusColor: Colors.transparent,
                              hoverColor: Colors.transparent,
                              highlightColor: Colors.transparent,
                              onTap: () async {
                                final selectedMedia = await selectMedia(
                                  maxHeight: 400.00,
                                  imageQuality: 100,
                                  mediaSource: MediaSource.photoGallery,
                                  multiImage: false,
                                );
                                if (!context.mounted) return;
                                if (selectedMedia != null &&
                                    selectedMedia.every((m) =>
                                        validateFileFormat(
                                            m.storagePath, context))) {
                                  safeSetState(() =>
                                      _model.isDataUploading_uploadGameData5ir =
                                          true);
                                  var selectedUploadedFiles =
                                      <FFUploadedFile>[];

                                  try {
                                    showUploadMessage(
                                      context,
                                      'Uploading file...',
                                      showLoading: true,
                                    );
                                    selectedUploadedFiles = selectedMedia
                                        .map((m) => FFUploadedFile(
                                              name:
                                                  m.storagePath.split('/').last,
                                              bytes: m.bytes,
                                              height: m.dimensions?.height,
                                              width: m.dimensions?.width,
                                              blurHash: m.blurHash,
                                              originalFilename:
                                                  m.originalFilename,
                                            ))
                                        .toList();
                                  } finally {
                                    ScaffoldMessenger.of(context)
                                        .hideCurrentSnackBar();
                                    _model.isDataUploading_uploadGameData5ir =
                                        false;
                                  }
                                  if (selectedUploadedFiles.length ==
                                      selectedMedia.length) {
                                    safeSetState(() {
                                      _model.uploadedLocalFile_uploadGameData5ir =
                                          selectedUploadedFiles.first;
                                    });
                                    showUploadMessage(context, 'Success!');
                                  } else {
                                    safeSetState(() {});
                                    showUploadMessage(
                                        context, 'Failed to upload data');
                                    return;
                                  }
                                }
                              },
                              child: Container(
                                width: double.infinity,
                                height: 200.0,
                                decoration: BoxDecoration(
                                  color: FlutterFlowTheme.of(context)
                                      .primaryBackground,
                                  image: (_model.uploadedLocalFile_uploadGameData5ir
                                                  .bytes?.isNotEmpty ??
                                              false) ||
                                          _model.uploadedFileUrl_uploadDataNyu
                                              .isNotEmpty
                                      ? DecorationImage(
                                          fit: BoxFit.cover,
                                          image: (_model
                                                      .uploadedLocalFile_uploadGameData5ir
                                                      .bytes
                                                      ?.isNotEmpty ??
                                                  false)
                                              ? Image.memory(
                                                  _model
                                                          .uploadedLocalFile_uploadGameData5ir
                                                          .bytes ??
                                                      Uint8List.fromList([]),
                                                ).image
                                              : NetworkImage(_model
                                                  .uploadedFileUrl_uploadDataNyu),
                                        )
                                      : null,
                                  borderRadius: BorderRadius.circular(18.0),
                                ),
                                child: Builder(
                                  builder: (context) {
                                    if ((_model.uploadedLocalFile_uploadGameData5ir
                                            .bytes?.isEmpty ??
                                        true) &&
                                        _model.uploadedFileUrl_uploadDataNyu
                                            .isEmpty) {
                                      return Padding(
                                        padding: const EdgeInsetsDirectional.fromSTEB(
                                            16.0, 16.0, 16.0, 16.0),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.max,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.add_photo_alternate,
                                              color:
                                                  FlutterFlowTheme.of(context)
                                                      .primary,
                                              size: 40.0,
                                            ),
                                            Text(
                                              'Ajouter une image',
                                              style:
                                                  FlutterFlowTheme.of(context)
                                                      .bodyLarge
                                                      .override(
                                                        font: GoogleFonts.inter(
                                                          fontWeight:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodyLarge
                                                                  .fontWeight,
                                                          fontStyle:
                                                              FlutterFlowTheme.of(
                                                                      context)
                                                                  .bodyLarge
                                                                  .fontStyle,
                                                        ),
                                                        letterSpacing: 0.0,
                                                        fontWeight:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodyLarge
                                                                .fontWeight,
                                                        fontStyle:
                                                            FlutterFlowTheme.of(
                                                                    context)
                                                                .bodyLarge
                                                                .fontStyle,
                                                      ),
                                            ),
                                          ].divide(const SizedBox(height: 8.0)),
                                        ),
                                      );
                                    } else {
                                      return Container(
                                        width: 100.0,
                                        height: 100.0,
                                        decoration: const BoxDecoration(),
                                      );
                                    }
                                  },
                                ),
                              ),
                            ),
                          ].divide(const SizedBox(height: 12.0)),
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      decoration: _buildSectionDecoration(context),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                            20.0, 20.0, 20.0, 20.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Text(
                              'Dates',
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
                                    fontSize: 20.0,
                                    letterSpacing: -0.3,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            Container(
                              height: 50.0,
                              decoration: BoxDecoration(
                                color: FlutterFlowTheme.of(context).fieldBg,
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    10.0, 0.0, 10.0, 0.0),
                                child: InkWell(
                                  splashColor: Colors.transparent,
                                  focusColor: Colors.transparent,
                                  hoverColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
                                  onTap: () async {
                                    final initialDate =
                                        _model.startDatePicked ??
                                            getCurrentTimestamp;
                                    final datePickedDate =
                                        await showDatePicker(
                                      context: context,
                                      initialDate: initialDate,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2050),
                                      builder: (context, child) {
                                        return wrapInMaterialDatePickerTheme(
                                          context,
                                          child!,
                                          headerBackgroundColor:
                                              FlutterFlowTheme.of(context)
                                                  .primary,
                                          headerForegroundColor:
                                              FlutterFlowTheme.of(context).info,
                                          headerTextStyle: FlutterFlowTheme.of(
                                                  context)
                                              .headlineLarge
                                              .override(
                                                font: GoogleFonts.interTight(
                                                  fontWeight: FontWeight.w600,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .headlineLarge
                                                          .fontStyle,
                                                ),
                                                fontSize: 32.0,
                                                letterSpacing: 0.0,
                                                fontWeight: FontWeight.w600,
                                                fontStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .headlineLarge
                                                        .fontStyle,
                                              ),
                                          pickerBackgroundColor:
                                              FlutterFlowTheme.of(context)
                                                  .secondaryBackground,
                                          pickerForegroundColor:
                                              FlutterFlowTheme.of(context)
                                                  .primaryText,
                                          selectedDateTimeBackgroundColor:
                                              FlutterFlowTheme.of(context)
                                                  .primary,
                                          selectedDateTimeForegroundColor:
                                              FlutterFlowTheme.of(context).info,
                                          actionButtonForegroundColor:
                                              FlutterFlowTheme.of(context)
                                                  .primaryText,
                                          iconSize: 24.0,
                                        );
                                      },
                                    );

                                    if (datePickedDate != null) {
                                      safeSetState(() {
                                        _model.startDatePicked = DateTime(
                                          datePickedDate.year,
                                          datePickedDate.month,
                                          datePickedDate.day,
                                        );
                                      });
                                    }
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.max,
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Date de début',
                                        style: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .override(
                                              font: GoogleFonts.inter(
                                                fontWeight:
                                                    FlutterFlowTheme.of(context)
                                                        .bodyMedium
                                                        .fontWeight,
                                                fontStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .bodyMedium
                                                        .fontStyle,
                                              ),
                                              color:
                                                  FlutterFlowTheme.of(context)
                                                      .fieldText,
                                              letterSpacing: 0.0,
                                              fontWeight:
                                                  FlutterFlowTheme.of(context)
                                                      .bodyMedium
                                                      .fontWeight,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .bodyMedium
                                                      .fontStyle,
                                            ),
                                      ),
                                      Text(
                                        dateTimeFormat(
                                          "d/M/y",
                                          _model.startDatePicked ??
                                              getCurrentTimestamp,
                                          locale: FFLocalizations.of(context)
                                              .languageCode,
                                        ),
                                        style: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .override(
                                              font: GoogleFonts.inter(
                                                fontWeight:
                                                    FlutterFlowTheme.of(context)
                                                        .bodyMedium
                                                        .fontWeight,
                                                fontStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .bodyMedium
                                                        .fontStyle,
                                              ),
                                              color:
                                                  FlutterFlowTheme.of(context)
                                                      .primaryText,
                                              letterSpacing: 0.0,
                                              fontWeight:
                                                  FlutterFlowTheme.of(context)
                                                      .bodyMedium
                                                      .fontWeight,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .bodyMedium
                                                      .fontStyle,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              height: 50.0,
                              decoration: BoxDecoration(
                                color: FlutterFlowTheme.of(context).fieldBg,
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    10.0, 0.0, 10.0, 0.0),
                                child: InkWell(
                                  splashColor: Colors.transparent,
                                  focusColor: Colors.transparent,
                                  hoverColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
                                  onTap: () async {
                                    final initialDate = _model.datePicked ??
                                        _model.startDatePicked ??
                                        getCurrentTimestamp;
                                    final firstDate = _model.startDatePicked ??
                                        getCurrentTimestamp;
                                    final datePickedDate =
                                        await showDatePicker(
                                      context: context,
                                      initialDate: initialDate,
                                      firstDate: firstDate,
                                      lastDate: DateTime(2050),
                                      builder: (context, child) {
                                        return wrapInMaterialDatePickerTheme(
                                          context,
                                          child!,
                                          headerBackgroundColor:
                                              FlutterFlowTheme.of(context)
                                                  .primary,
                                          headerForegroundColor:
                                              FlutterFlowTheme.of(context).info,
                                          headerTextStyle: FlutterFlowTheme.of(
                                                  context)
                                              .headlineLarge
                                              .override(
                                                font: GoogleFonts.interTight(
                                                  fontWeight: FontWeight.w600,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .headlineLarge
                                                          .fontStyle,
                                                ),
                                                fontSize: 32.0,
                                                letterSpacing: 0.0,
                                                fontWeight: FontWeight.w600,
                                                fontStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .headlineLarge
                                                        .fontStyle,
                                              ),
                                          pickerBackgroundColor:
                                              FlutterFlowTheme.of(context)
                                                  .secondaryBackground,
                                          pickerForegroundColor:
                                              FlutterFlowTheme.of(context)
                                                  .primaryText,
                                          selectedDateTimeBackgroundColor:
                                              FlutterFlowTheme.of(context)
                                                  .primary,
                                          selectedDateTimeForegroundColor:
                                              FlutterFlowTheme.of(context).info,
                                          actionButtonForegroundColor:
                                              FlutterFlowTheme.of(context)
                                                  .primaryText,
                                          iconSize: 24.0,
                                        );
                                      },
                                    );

                                    if (datePickedDate != null) {
                                      safeSetState(() {
                                        _model.datePicked = DateTime(
                                          datePickedDate.year,
                                          datePickedDate.month,
                                          datePickedDate.day,
                                        );
                                      });
                                    } else if (_model.datePicked != null) {
                                      safeSetState(() {
                                        _model.datePicked = getCurrentTimestamp;
                                      });
                                    }
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.max,
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Date de fin',
                                        style: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .override(
                                              font: GoogleFonts.inter(
                                                fontWeight:
                                                    FlutterFlowTheme.of(context)
                                                        .bodyMedium
                                                        .fontWeight,
                                                fontStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .bodyMedium
                                                        .fontStyle,
                                              ),
                                              color:
                                                  FlutterFlowTheme.of(context)
                                                      .fieldText,
                                              letterSpacing: 0.0,
                                              fontWeight:
                                                  FlutterFlowTheme.of(context)
                                                      .bodyMedium
                                                      .fontWeight,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .bodyMedium
                                                      .fontStyle,
                                            ),
                                      ),
                                      Text(
                                        dateTimeFormat(
                                          "d/M/y",
                                          _model.datePicked,
                                          locale: FFLocalizations.of(context)
                                              .languageCode,
                                        ),
                                        style: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .override(
                                              font: GoogleFonts.inter(
                                                fontWeight:
                                                    FlutterFlowTheme.of(context)
                                                        .bodyMedium
                                                        .fontWeight,
                                                fontStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .bodyMedium
                                                        .fontStyle,
                                              ),
                                              letterSpacing: 0.0,
                                              fontWeight:
                                                  FlutterFlowTheme.of(context)
                                                      .bodyMedium
                                                      .fontWeight,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .bodyMedium
                                                      .fontStyle,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ].divide(const SizedBox(height: 16.0)),
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      decoration: _buildSectionDecoration(context),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                            20.0, 20.0, 20.0, 20.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  10.0, 0.0, 10.0, 0.0),
                              child: Text(
                                'Restrictions',
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
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  10.0, 0.0, 10.0, 0.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.max,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.max,
                                    children: [
                                      Text(
                                        'Interdire aux mineurs ?',
                                        style: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .override(
                                              font: GoogleFonts.inter(
                                                fontWeight:
                                                    FlutterFlowTheme.of(context)
                                                        .bodyMedium
                                                        .fontWeight,
                                                fontStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .bodyMedium
                                                        .fontStyle,
                                              ),
                                              color: const Color(0xFF605F83),
                                              letterSpacing: 0.0,
                                              fontWeight:
                                                  FlutterFlowTheme.of(context)
                                                      .bodyMedium
                                                      .fontWeight,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .bodyMedium
                                                      .fontStyle,
                                            ),
                                      ),
                                      Text(
                                        _model.switchValue! ? ' Oui' : ' Non',
                                        style: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .override(
                                              font: GoogleFonts.inter(
                                                fontWeight:
                                                    FlutterFlowTheme.of(context)
                                                        .bodyMedium
                                                        .fontWeight,
                                                fontStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .bodyMedium
                                                        .fontStyle,
                                              ),
                                              letterSpacing: 0.0,
                                              fontWeight:
                                                  FlutterFlowTheme.of(context)
                                                      .bodyMedium
                                                      .fontWeight,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .bodyMedium
                                                      .fontStyle,
                                            ),
                                      ),
                                    ],
                                  ),
                                  Switch(
                                    value: _model.switchValue!,
                                    onChanged: (newValue) async {
                                      safeSetState(
                                          () => _model.switchValue = newValue);
                                    },
                                    activeThumbColor:
                                        FlutterFlowTheme.of(context).primary,
                                    activeTrackColor: const Color(0xFFC4C4C4),
                                    inactiveTrackColor:
                                        FlutterFlowTheme.of(context)
                                            .secondaryText,
                                    inactiveThumbColor: const Color(0xFF8C82E7),
                                  ),
                                ].divide(const SizedBox(width: 10.0)),
                              ),
                            ),
                          ].divide(const SizedBox(height: 16.0)),
                        ),
                      ),
                    ),
                    Builder(
                      builder: (context) => FFButtonWidget(
                        onPressed: () async {
                          if (_model.formKey.currentState == null ||
                              !_model.formKey.currentState!.validate()) {
                            return;
                          }
                          if ((_model.uploadedLocalFile_uploadGameData5ir
                                      .bytes?.isEmpty ??
                                  true) &&
                              _model.uploadedFileUrl_uploadDataNyu.isEmpty) {
                            await showDialog(
                              context: context,
                              builder: (alertDialogContext) {
                                return WebViewAware(
                                  child: AlertDialog(
                                    title: const Text('Image manquante'),
                                    content: const Text(
                                        'Une image est nécessaire pour ajouter un jeu'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(alertDialogContext),
                                        child: const Text('Ok'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                            return;
                          }
                          if (_model.datePicked == null) {
                            return;
                          }
                          if (widget.enseigneRef != null) {
                            await showDialog(
                              context: context,
                              builder: (dialogContext) {
                                return Dialog(
                                  elevation: 0,
                                  insetPadding: EdgeInsets.zero,
                                  backgroundColor: Colors.transparent,
                                  alignment: const AlignmentDirectional(0.0, 0.0)
                                      .resolve(Directionality.of(context)),
                                  child: WebViewAware(
                                    child: GestureDetector(
                                      onTap: () {
                                        FocusScope.of(dialogContext).unfocus();
                                        FocusManager.instance.primaryFocus
                                            ?.unfocus();
                                      },
                                      child: ValidationCardWidget(
                                        callback: () async {
                                          if (_model.formKey.currentState ==
                                                  null ||
                                              !_model.formKey.currentState!
                                                  .validate()) {
                                            return;
                                          }
                                          if ((_model
                                                      .uploadedLocalFile_uploadGameData5ir
                                                      .bytes
                                                      ?.isEmpty ??
                                                  true) &&
                                              _model.uploadedFileUrl_uploadDataNyu
                                                  .isEmpty) {
                                            await showDialog(
                                              context: context,
                                              builder: (alertDialogContext) {
                                                return WebViewAware(
                                                  child: AlertDialog(
                                                    title:
                                                        const Text('Image manquante'),
                                                    content: const Text(
                                                        'Une image est nécessaire pour ajouter un jeu'),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                alertDialogContext),
                                                        child: const Text('Ok'),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            );
                                            return;
                                          }
                                          if (_model.datePicked == null) {
                                            return;
                                          }
                                          final secondaryPrizes =
                                              _collectSecondaryPrizes();
                                          if (secondaryPrizes == null) {
                                            return;
                                          }
                                          final totalSecondaryCount =
                                              secondaryPrizes.fold<int>(
                                            0,
                                            (sum, item) =>
                                                sum +
                                                (item['count'] as int? ?? 0),
                                          );
                                          final secondaryPrizeSummary =
                                              secondaryPrizes.isNotEmpty
                                                  ? secondaryPrizes
                                                      .map((e) =>
                                                          (e['name'] ?? '')
                                                              .toString())
                                                      .where(
                                                          (e) => e.isNotEmpty)
                                                      .join(', ')
                                                  : null;
                                          final mainPrizeName = _model
                                              .textController1.text
                                              .trim();
                                          final mainPrizeDescription = _model
                                              .textController2.text
                                              .trim();
                                          final manualGameTitle = _model
                                              .textController4.text
                                              .trim();
                                          final mainPrizeValueText = _model
                                              .textController3.text
                                              .trim();
                                          final gameName =
                                              mainPrizeName.isNotEmpty
                                                  ? mainPrizeName
                                                  : manualGameTitle;
                                          final mainPrizeValue =
                                              mainPrizeValueText.isNotEmpty
                                                  ? _parsePriceValue(
                                                      mainPrizeValueText)
                                                  : null;
                                          final startDate =
                                              _model.startDatePicked ??
                                                  getCurrentTimestamp;
                                          if (_model.datePicked != null &&
                                              startDate.isAfter(
                                                  _model.datePicked!)) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'La date de début doit être avant la date de fin.'),
                                              ),
                                            );
                                            return;
                                          }
                                          if (_model.mainPrizeEnabled &&
                                              (mainPrizeName.isEmpty ||
                                                  mainPrizeDescription
                                                      .isEmpty)) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'Veuillez remplir le lot principal ou désactivez-le.'),
                                              ),
                                            );
                                            return;
                                          }
                                          if (gameName.isEmpty) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'Le nom du jeu est requis.'),
                                              ),
                                            );
                                            return;
                                          }
                                          final hasAnyPrize = (_model
                                                      .mainPrizeEnabled &&
                                                  (mainPrizeName.isNotEmpty ||
                                                      mainPrizeDescription
                                                          .isNotEmpty ||
                                                      mainPrizeValue !=
                                                          null)) ||
                                              secondaryPrizes.isNotEmpty;
                                          if (!hasAnyPrize) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'Ajoutez au moins un lot tirage au sort ou gain immédiat.'),
                                              ),
                                            );
                                            return;
                                          }
                                          if (_model
                                                  .uploadedLocalFile_uploadGameData5ir
                                                  .bytes
                                                  ?.isNotEmpty ??
                                              false) {
                                            safeSetState(() => _model
                                                    .isDataUploading_uploadDataNyu =
                                                true);
                                            var selectedUploadedFiles =
                                                <FFUploadedFile>[];
                                            var selectedMedia =
                                                <SelectedFile>[];
                                            var downloadUrls = <String>[];
                                            try {
                                              selectedUploadedFiles = _model
                                                      .uploadedLocalFile_uploadGameData5ir
                                                      .bytes!
                                                      .isNotEmpty
                                                  ? [
                                                      _model
                                                          .uploadedLocalFile_uploadGameData5ir
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
                                              _model.isDataUploading_uploadDataNyu =
                                                  false;
                                            }
                                            if (selectedUploadedFiles.length ==
                                                    selectedMedia.length &&
                                                downloadUrls.length ==
                                                    selectedMedia.length) {
                                              safeSetState(() {
                                                _model.uploadedLocalFile_uploadDataNyu =
                                                    selectedUploadedFiles.first;
                                                _model.uploadedFileUrl_uploadDataNyu =
                                                    downloadUrls.first;
                                              });
                                            } else {
                                              safeSetState(() {});
                                              return;
                                            }
                                          } else if (_model
                                              .uploadedFileUrl_uploadDataNyu
                                              .isEmpty) {
                                            return;
                                          }

                                          _model.endDateTransformCopy =
                                              actions.setEndOfDay(
                                            _model.datePicked!,
                                          );

                                          var gamesRecordReference =
                                              GamesRecord.collection.doc();
                                          await gamesRecordReference.set({
                                            ...createGamesRecordData(
                                              name: gameName,
                                              description: mainPrizeDescription
                                                      .isNotEmpty
                                                  ? mainPrizeDescription
                                                  : null,
                                              endDate:
                                                  _model.endDateTransformCopy,
                                              enseigneId: widget.enseigneRef,
                                              createBy: currentUserReference,
                                              visiblePublic: true,
                                              prizeValue: mainPrizeValue,
                                              gameType: GameType.scratcher,
                                              photo: _model
                                                  .uploadedFileUrl_uploadDataNyu,
                                              secondaryPrizeDescription:
                                                  secondaryPrizeSummary,
                                              secondaryPrizes: secondaryPrizes,
                                              views: 0,
                                              favorites: 0,
                                              participations: 0,
                                              prohibitedForMinors:
                                                  _model.switchValue,
                                              hasWinner: false,
                                              mainPrizeWinner: null,
                                              startDate: startDate,
                                              enseigneName: widget.enseigne,
                                            ),
                                            ...mapToFirestore(
                                              {
                                                'created_time': FieldValue
                                                    .serverTimestamp(),
                                                'uniquePlayersEnabled': true,
                                                'unique_players_count': 0,
                                              },
                                            ),
                                          });
                                          _model.gameResult =
                                              GamesRecord.getDocumentFromData({
                                            ...createGamesRecordData(
                                              name: gameName,
                                              description: mainPrizeDescription
                                                      .isNotEmpty
                                                  ? mainPrizeDescription
                                                  : null,
                                              endDate:
                                                  _model.endDateTransformCopy,
                                              enseigneId: widget.enseigneRef,
                                              createBy: currentUserReference,
                                              visiblePublic: true,
                                              prizeValue: mainPrizeValue,
                                              gameType: GameType.scratcher,
                                              photo: _model
                                                  .uploadedFileUrl_uploadDataNyu,
                                              secondaryPrizeDescription:
                                                  secondaryPrizeSummary,
                                              secondaryPrizes: secondaryPrizes,
                                              views: 0,
                                              favorites: 0,
                                              participations: 0,
                                              prohibitedForMinors:
                                                  _model.switchValue,
                                              hasWinner: false,
                                              mainPrizeWinner: null,
                                              startDate: startDate,
                                              enseigneName: widget.enseigne,
                                            ),
                                            ...mapToFirestore(
                                              {
                                                'created_time': DateTime.now(),
                                                'uniquePlayersEnabled': true,
                                                'unique_players_count': 0,
                                              },
                                            ),
                                          }, gamesRecordReference);
                                          if (totalSecondaryCount > 0) {
                                            await actions
                                                .addInstantWinnersToGame(
                                              _model.gameResult!.reference,
                                              _model.gameResult!.startDate!,
                                              _model.endDateTransformCopy!,
                                              totalSecondaryCount,
                                            );
                                          }
                                          safeSetState(() {
                                            _model.isDataUploading_uploadGameData5ir =
                                                false;
                                            _model.uploadedLocalFile_uploadGameData5ir =
                                                FFUploadedFile(
                                                    bytes:
                                                        Uint8List.fromList([]),
                                                    originalFilename: '');
                                          });
                                          if (!context.mounted) return;

                                          context.goNamed(
                                            JeuxCommercantPageWidget.routeName,
                                            extra: <String, dynamic>{
                                              kTransitionInfoKey:
                                                  const TransitionInfo(
                                                hasTransition: true,
                                                transitionType:
                                                    PageTransitionType.fade,
                                                duration:
                                                    Duration(milliseconds: 0),
                                              ),
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          } else {
                            await showDialog(
                              context: context,
                              builder: (alertDialogContext) {
                                return WebViewAware(
                                  child: AlertDialog(
                                    title: const Text('Erreur'),
                                    content: const Text('Veuillez recommencer'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(alertDialogContext),
                                        child: const Text('Ok'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          }

                          safeSetState(() {});
                        },
                        text: 'Créer le jeu',
                        options: FFButtonOptions(
                          width: double.infinity,
                          height: 50.0,
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          iconPadding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          color: FlutterFlowTheme.of(context).primary,
                          textStyle:
                              FlutterFlowTheme.of(context).titleMedium.override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .titleMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .titleMedium
                                          .fontStyle,
                                    ),
                                    color: FlutterFlowTheme.of(context).info,
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .titleMedium
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .titleMedium
                                        .fontStyle,
                                  ),
                          elevation: 0.0,
                          borderRadius: BorderRadius.circular(25.0),
                        ),
                      ),
                    ),
                  ].divide(const SizedBox(height: 18.0)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
