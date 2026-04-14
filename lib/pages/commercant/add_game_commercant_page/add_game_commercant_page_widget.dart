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
  bool _isSubmittingGameCreation = false;

  final scaffoldKey = GlobalKey<ScaffoldState>();

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

  List<Map<String, dynamic>>? _collectSecondaryPrizes() {
    final prizes = <Map<String, dynamic>>[];
    for (var index = 0; index < _model.secondaryPrizes.length; index++) {
      final entry = _model.secondaryPrizes[index];
      final name = entry.nameController.text.trim();
      final presentation = entry.presentationController.text.trim();
      final countText = entry.countController.text.trim();

      if (name.isEmpty && presentation.isEmpty && countText.isEmpty) {
        continue;
      }
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nom du lot secondaire requis')),
        );
        return null;
      }
      if (countText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nombre de lots secondaires requis')),
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

    final hasMainPrizeData = template.hasMainPrize == true;
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

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String label,
    String? hintText,
    Widget? suffixIcon,
  }) {
    final labelStyle = FlutterFlowTheme.of(context).labelMedium.override(
          font: GoogleFonts.inter(
            fontWeight: FontWeight.w400,
            fontStyle: FlutterFlowTheme.of(context).labelMedium.fontStyle,
          ),
          color: const Color(0xFF75728F),
          letterSpacing: 0.0,
          fontSize: 14.0,
          fontWeight: FontWeight.w400,
          fontStyle: FlutterFlowTheme.of(context).labelMedium.fontStyle,
        );
    return InputDecoration(
      labelText: hintText ?? label,
      labelStyle: labelStyle,
      hintStyle: labelStyle,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      alignLabelWithHint: true,
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0x120E1220), width: 1.0),
        borderRadius: BorderRadius.circular(16.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: FlutterFlowTheme.of(context).primary,
          width: 1.2,
        ),
        borderRadius: BorderRadius.circular(16.0),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: FlutterFlowTheme.of(context).error,
          width: 1.2,
        ),
        borderRadius: BorderRadius.circular(16.0),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: FlutterFlowTheme.of(context).error,
          width: 1.2,
        ),
        borderRadius: BorderRadius.circular(16.0),
      ),
      filled: true,
      fillColor: const Color(0xFFF6F7FB),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
      suffixIcon: suffixIcon,
    );
  }

  TextStyle _fieldTextStyle(BuildContext context) =>
      FlutterFlowTheme.of(context).bodyMedium.override(
            font: GoogleFonts.inter(
              fontWeight: FlutterFlowTheme.of(context).bodyMedium.fontWeight,
              fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
            ),
            color: const Color(0xFF38374A),
            letterSpacing: 0.0,
            fontWeight: FontWeight.w400,
            fontStyle: FlutterFlowTheme.of(context).bodyMedium.fontStyle,
          );

  Widget _buildSectionCard(BuildContext context, {required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFE),
        borderRadius: BorderRadius.circular(18.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x090E1220),
            blurRadius: 8.0,
            offset: Offset(0.0, 2.0),
          ),
        ],
        border: Border.all(
          color: Color(0x0D0E1220),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: child,
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    String? description,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: FlutterFlowTheme.of(context).headlineSmall.override(
                      font: GoogleFonts.interTight(
                        fontWeight:
                            FlutterFlowTheme.of(context).headlineSmall.fontWeight,
                        fontStyle:
                            FlutterFlowTheme.of(context).headlineSmall.fontStyle,
                      ),
                      letterSpacing: 0.0,
                      fontSize: 20.0,
                      fontWeight: FontWeight.w600,
                      fontStyle:
                          FlutterFlowTheme.of(context).headlineSmall.fontStyle,
                    ),
              ),
              if (description != null) ...[
                const SizedBox(height: 8.0),
                Text(
                  description,
                  style: FlutterFlowTheme.of(context).bodyMedium.override(
                        font: GoogleFonts.inter(
                          fontWeight:
                              FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                          fontStyle:
                              FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                        ),
                        color: const Color(0xFF6A6884),
                        letterSpacing: 0.0,
                        fontSize: 14.0,
                        fontWeight: FontWeight.w400,
                        fontStyle:
                            FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                      ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12.0),
          trailing,
        ],
      ],
    );
  }

  Future<void> _pickGameImage() async {
    final selectedMedia = await selectMedia(
      maxHeight: 400.00,
      imageQuality: 100,
      mediaSource: MediaSource.photoGallery,
      multiImage: false,
    );
    if (!context.mounted) return;
    if (selectedMedia != null &&
        selectedMedia.every((m) => validateFileFormat(m.storagePath, context))) {
      safeSetState(() => _model.isDataUploading_uploadGameData5ir = true);
      var selectedUploadedFiles = <FFUploadedFile>[];

      try {
        showUploadMessage(
          context,
          'Uploading file...',
          showLoading: true,
        );
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
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _model.isDataUploading_uploadGameData5ir = false;
      }
      if (selectedUploadedFiles.length == selectedMedia.length) {
        safeSetState(() {
          _model.uploadedLocalFile_uploadGameData5ir =
              selectedUploadedFiles.first;
        });
        showUploadMessage(context, 'Success!');
      } else {
        safeSetState(() {});
        showUploadMessage(context, 'Failed to upload data');
      }
    }
  }

  Future<void> _pickStartDate() async {
    final initialDate = _model.startDatePicked ?? getCurrentTimestamp;
    final datePickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2050),
      builder: (context, child) {
        return wrapInMaterialDatePickerTheme(
          context,
          child!,
          headerBackgroundColor: FlutterFlowTheme.of(context).primary,
          headerForegroundColor: FlutterFlowTheme.of(context).info,
          headerTextStyle: FlutterFlowTheme.of(context).headlineLarge.override(
                font: GoogleFonts.interTight(
                  fontWeight: FontWeight.w600,
                  fontStyle:
                      FlutterFlowTheme.of(context).headlineLarge.fontStyle,
                ),
                fontSize: 32.0,
                letterSpacing: 0.0,
                fontWeight: FontWeight.w600,
                fontStyle:
                    FlutterFlowTheme.of(context).headlineLarge.fontStyle,
              ),
          pickerBackgroundColor:
              FlutterFlowTheme.of(context).secondaryBackground,
          pickerForegroundColor: FlutterFlowTheme.of(context).primaryText,
          selectedDateTimeBackgroundColor:
              FlutterFlowTheme.of(context).primary,
          selectedDateTimeForegroundColor: FlutterFlowTheme.of(context).info,
          actionButtonForegroundColor:
              FlutterFlowTheme.of(context).primaryText,
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
  }

  Future<void> _pickEndDate() async {
    final initialDate =
        _model.datePicked ?? _model.startDatePicked ?? getCurrentTimestamp;
    final firstDate = _model.startDatePicked ?? getCurrentTimestamp;
    final datePickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime(2050),
      builder: (context, child) {
        return wrapInMaterialDatePickerTheme(
          context,
          child!,
          headerBackgroundColor: FlutterFlowTheme.of(context).primary,
          headerForegroundColor: FlutterFlowTheme.of(context).info,
          headerTextStyle: FlutterFlowTheme.of(context).headlineLarge.override(
                font: GoogleFonts.interTight(
                  fontWeight: FontWeight.w600,
                  fontStyle:
                      FlutterFlowTheme.of(context).headlineLarge.fontStyle,
                ),
                fontSize: 32.0,
                letterSpacing: 0.0,
                fontWeight: FontWeight.w600,
                fontStyle:
                    FlutterFlowTheme.of(context).headlineLarge.fontStyle,
              ),
          pickerBackgroundColor:
              FlutterFlowTheme.of(context).secondaryBackground,
          pickerForegroundColor: FlutterFlowTheme.of(context).primaryText,
          selectedDateTimeBackgroundColor:
              FlutterFlowTheme.of(context).primary,
          selectedDateTimeForegroundColor: FlutterFlowTheme.of(context).info,
          actionButtonForegroundColor:
              FlutterFlowTheme.of(context).primaryText,
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
  }

  Widget _buildDateField(
    BuildContext context, {
    required String label,
    required String value,
    required Future<void> Function() onTap,
  }) {
    return InkWell(
      splashColor: Colors.transparent,
      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: onTap,
      child: Container(
        height: 60.0,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FC),
          borderRadius: BorderRadius.circular(18.0),
          border: Border.all(
            color: const Color(0x120E1220),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: FlutterFlowTheme.of(context).bodyMedium.override(
                    font: GoogleFonts.inter(
                      fontWeight:
                          FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                      fontStyle:
                          FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                    ),
                    color: FlutterFlowTheme.of(context).fieldText,
                    letterSpacing: 0.0,
                    fontWeight: FontWeight.w400,
                    fontStyle:
                        FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                  ),
            ),
            Text(
              value,
              style: FlutterFlowTheme.of(context).bodyLarge.override(
                    font: GoogleFonts.inter(
                      fontWeight:
                          FlutterFlowTheme.of(context).bodyLarge.fontWeight,
                      fontStyle:
                          FlutterFlowTheme.of(context).bodyLarge.fontStyle,
                    ),
                    color: FlutterFlowTheme.of(context).primaryText,
                    letterSpacing: 0.0,
                    fontWeight: FontWeight.w500,
                    fontStyle:
                        FlutterFlowTheme.of(context).bodyLarge.fontStyle,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondaryPrizeCard(
    BuildContext context,
    int index,
    SecondaryPrizeEntry entry,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAFD),
        borderRadius: BorderRadius.circular(18.0),
        border: Border.all(color: const Color(0x1AF0DDE8)),
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Lot à gain immédiat ${index + 1}',
                  style: FlutterFlowTheme.of(context).titleLarge.override(
                        font: GoogleFonts.interTight(
                          fontWeight:
                              FlutterFlowTheme.of(context).titleLarge.fontWeight,
                          fontStyle:
                              FlutterFlowTheme.of(context).titleLarge.fontStyle,
                        ),
                        letterSpacing: 0.0,
                        fontSize: 18.0,
                        fontWeight: FontWeight.w600,
                        fontStyle:
                            FlutterFlowTheme.of(context).titleLarge.fontStyle,
                      ),
                ),
              ),
              if (_model.secondaryPrizes.length > 1)
                IconButton(
                  onPressed: () {
                    setState(() {
                      _model.secondaryPrizes.removeAt(index).dispose();
                    });
                  },
                  icon: const Icon(Icons.close_rounded),
                  color: FlutterFlowTheme.of(context).primaryText,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32.0,
                    height: 32.0,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 12.0),
          TextFormField(
            controller: entry.nameController,
            focusNode: entry.nameFocusNode,
            decoration: _fieldDecoration(
              context,
              label: 'Titre du lot',
              hintText: 'Titre du lot',
            ),
            style: _fieldTextStyle(context),
          ),
          const SizedBox(height: 8.0),
          TextFormField(
            controller: entry.presentationController,
            focusNode: entry.presentationFocusNode,
            decoration: _fieldDecoration(
              context,
              label: 'Description (facultatif)',
              hintText: 'Description (facultatif)',
            ),
            style: _fieldTextStyle(context),
          ),
          const SizedBox(height: 8.0),
          TextFormField(
            controller: entry.countController,
            focusNode: entry.countFocusNode,
            decoration: _fieldDecoration(
              context,
              label: 'Nombre de lots',
            ),
            style: _fieldTextStyle(context),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    );
  }

  Future<void> _showMissingImageDialog() async {
    await showDialog(
      context: context,
      builder: (alertDialogContext) {
        return WebViewAware(
          child: AlertDialog(
            title: const Text('Image manquante'),
            content:
                const Text('Une image est nécessaire pour ajouter un jeu'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(alertDialogContext),
                child: const Text('Ok'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _submitGameCreation() async {
    if (_model.formKey.currentState == null ||
        !_model.formKey.currentState!.validate()) {
      return false;
    }
    if ((_model.uploadedLocalFile_uploadGameData5ir.bytes?.isEmpty ?? true) &&
        _model.uploadedFileUrl_uploadDataNyu.isEmpty) {
      await _showMissingImageDialog();
      return false;
    }
    if (_model.datePicked == null) {
      return false;
    }
    final secondaryPrizes = _collectSecondaryPrizes();
    if (secondaryPrizes == null) {
      return false;
    }
    final totalSecondaryCount = secondaryPrizes.fold<int>(
      0,
      (currentTotal, item) => currentTotal + (item['count'] as int? ?? 0),
    );
    final secondaryPrizeSummary = secondaryPrizes.isNotEmpty
        ? secondaryPrizes
            .map((e) => (e['name'] ?? '').toString())
            .where((e) => e.isNotEmpty)
            .join(', ')
        : null;
    final mainPrizeName = _model.textController1.text.trim();
    final mainPrizeDescription = _model.textController2.text.trim();
    final manualGameTitle = _model.textController4.text.trim();
    final mainPrizeValueText = _model.textController3.text.trim();
    final gameName =
        mainPrizeName.isNotEmpty ? mainPrizeName : manualGameTitle;
    final mainPrizeValue = mainPrizeValueText.isNotEmpty
        ? _parsePriceValue(mainPrizeValueText)
        : null;
    // Regle produit :
    // Le lot principal doit etre monetaire.
    // On l'autorise uniquement si active, titre renseigne et valeur > 0.
    final shouldPersistMainPrize =
        _model.mainPrizeEnabled &&
        mainPrizeName.isNotEmpty &&
        (mainPrizeValue ?? 0) > 0;
    final startDate = _model.startDatePicked ?? getCurrentTimestamp;
    if (_model.datePicked != null && startDate.isAfter(_model.datePicked!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('La date de début doit être avant la date de fin.'),
        ),
      );
      return false;
    }
    if (_model.mainPrizeEnabled &&
        (mainPrizeName.isEmpty || (mainPrizeValue ?? 0) <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Le lot principal doit avoir un titre et une valeur monétaire supérieure à 0, ou être désactivé.'),
        ),
      );
      return false;
    }
    if (gameName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le nom du jeu est requis.'),
        ),
      );
      return false;
    }
    final hasAnyPrize = shouldPersistMainPrize ||
        secondaryPrizes.isNotEmpty;
    if (!hasAnyPrize) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ajoutez au moins un lot principal ou secondaire.'),
        ),
      );
      return false;
    }
    if (_model.uploadedLocalFile_uploadGameData5ir.bytes?.isNotEmpty ?? false) {
      safeSetState(() => _model.isDataUploading_uploadDataNyu = true);
      var selectedUploadedFiles = <FFUploadedFile>[];
      var selectedMedia = <SelectedFile>[];
      var downloadUrls = <String>[];
      try {
        selectedUploadedFiles =
            _model.uploadedLocalFile_uploadGameData5ir.bytes!.isNotEmpty
                ? [_model.uploadedLocalFile_uploadGameData5ir]
                : <FFUploadedFile>[];
        selectedMedia = selectedFilesFromUploadedFiles(
          selectedUploadedFiles,
        );
        downloadUrls = (await Future.wait(
          selectedMedia.map(
            (m) async => await uploadData(m.storagePath, m.bytes),
          ),
        ))
            .where((u) => u != null)
            .map((u) => u!)
            .toList();
      } finally {
        _model.isDataUploading_uploadDataNyu = false;
      }
      if (selectedUploadedFiles.length == selectedMedia.length &&
          downloadUrls.length == selectedMedia.length) {
        safeSetState(() {
          _model.uploadedLocalFile_uploadDataNyu = selectedUploadedFiles.first;
          _model.uploadedFileUrl_uploadDataNyu = downloadUrls.first;
        });
      } else {
        safeSetState(() {});
        return false;
      }
    } else if (_model.uploadedFileUrl_uploadDataNyu.isEmpty) {
      return false;
    }

    _model.endDateTransformCopy = actions.setEndOfDay(
      _model.datePicked!,
    );

    var gamesRecordReference = GamesRecord.collection.doc();
    await gamesRecordReference.set({
      ...createGamesRecordData(
        name: gameName,
        description:
            mainPrizeDescription.isNotEmpty ? mainPrizeDescription : null,
        endDate: _model.endDateTransformCopy,
        enseigneId: widget.enseigneRef,
        createBy: currentUserReference,
        visiblePublic: true,
        prizeValue: shouldPersistMainPrize ? mainPrizeValue : null,
        gameType: GameType.scratcher,
        photo: _model.uploadedFileUrl_uploadDataNyu,
        secondaryPrizeDescription: secondaryPrizeSummary,
        secondaryPrizes: secondaryPrizes,
        views: 0,
        favorites: 0,
        participations: 0,
        prohibitedForMinors: _model.switchValue,
        hasWinner: false,
        mainPrizeWinner: null,
        hasMainPrize: shouldPersistMainPrize,
        startDate: startDate,
        enseigneName: widget.enseigne,
      ),
      ...mapToFirestore(
        {
          'created_time': FieldValue.serverTimestamp(),
          'uniquePlayersEnabled': true,
          'unique_players_count': 0,
        },
      ),
    });
    _model.gameResult = GamesRecord.getDocumentFromData({
      ...createGamesRecordData(
        name: gameName,
        description:
            mainPrizeDescription.isNotEmpty ? mainPrizeDescription : null,
        endDate: _model.endDateTransformCopy,
        enseigneId: widget.enseigneRef,
        createBy: currentUserReference,
        visiblePublic: true,
        prizeValue: shouldPersistMainPrize ? mainPrizeValue : null,
        gameType: GameType.scratcher,
        photo: _model.uploadedFileUrl_uploadDataNyu,
        secondaryPrizeDescription: secondaryPrizeSummary,
        secondaryPrizes: secondaryPrizes,
        views: 0,
        favorites: 0,
        participations: 0,
        prohibitedForMinors: _model.switchValue,
        hasWinner: false,
        mainPrizeWinner: null,
        hasMainPrize: shouldPersistMainPrize,
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
      await actions.addInstantWinnersToGame(
        _model.gameResult!.reference,
        _model.gameResult!.startDate!,
        _model.endDateTransformCopy!,
        secondaryPrizes,
      );
    }
    safeSetState(() {
      _model.isDataUploading_uploadGameData5ir = false;
      _model.uploadedLocalFile_uploadGameData5ir = FFUploadedFile(
        bytes: Uint8List.fromList([]),
        originalFilename: '',
      );
    });
    return true;
  }

  Future<void> _handleCreatePressed() async {
    if (_isSubmittingGameCreation) {
      return;
    }

    FocusScope.of(context).unfocus();
    FocusManager.instance.primaryFocus?.unfocus();

    if (_model.formKey.currentState == null ||
        !_model.formKey.currentState!.validate()) {
      return;
    }
    if ((_model.uploadedLocalFile_uploadGameData5ir.bytes?.isEmpty ?? true) &&
        _model.uploadedFileUrl_uploadDataNyu.isEmpty) {
      await _showMissingImageDialog();
      return;
    }
    if (_model.datePicked == null) {
      return;
    }
    if (widget.enseigneRef != null) {
      final didCreateGame = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
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
                  FocusManager.instance.primaryFocus?.unfocus();
                },
                child: ValidationCardWidget(
                  callback: _submitGameCreationGuarded,
                ),
              ),
            ),
          );
        },
      );
      if (didCreateGame == true && context.mounted) {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
        context.goNamed(
          JeuxCommercantPageWidget.routeName,
          extra: <String, dynamic>{
            kTransitionInfoKey: const TransitionInfo(
              hasTransition: true,
              transitionType: PageTransitionType.fade,
              duration: Duration(milliseconds: 0),
            ),
          },
        );
      }
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
                  onPressed: () => Navigator.pop(alertDialogContext),
                  child: const Text('Ok'),
                ),
              ],
            ),
          );
        },
      );
    }

    safeSetState(() {});
  }

  Future<bool> _submitGameCreationGuarded() async {
    if (_isSubmittingGameCreation) {
      return false;
    }

    safeSetState(() => _isSubmittingGameCreation = true);

    try {
      return await _submitGameCreation();
    } catch (e, st) {
      debugPrint('Game creation failed: $e');
      debugPrintStack(stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La création du jeu a échoué. Veuillez réessayer.',
            ),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) {
        safeSetState(() => _isSubmittingGameCreation = false);
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
                padding:
                    const EdgeInsetsDirectional.fromSTEB(20.0, 20.0, 20.0, 20.0),
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FlutterFlowIconButton(
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
                    ),
                    _buildSectionCard(
                      context,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 300.0),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Créer un nouveau jeu',
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  style: FlutterFlowTheme.of(context)
                                      .displaySmall
                                      .override(
                                        font: GoogleFonts.interTight(
                                          fontWeight: FontWeight.w600,
                                          fontStyle: FlutterFlowTheme.of(context)
                                              .displaySmall
                                              .fontStyle,
                                        ),
                                        letterSpacing: -0.6,
                                        fontSize: 31.0,
                                        fontWeight: FontWeight.w600,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .displaySmall
                                            .fontStyle,
                                      ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16.0),
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFAFD),
                              borderRadius: BorderRadius.circular(18.0),
                              border: Border.all(color: const Color(0x26F0DDE8)),
                            ),
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSectionHeader(
                                  context,
                                  title: 'Lot principal',
                                  description:
                                      'Tirage au sort final parmi les participants',
                                  trailing: Container(
                                    padding: const EdgeInsets.all(2.0),
                                    decoration: BoxDecoration(
                                      color: _model.mainPrizeEnabled
                                          ? const Color(0xFFFBE8F1)
                                          : const Color(0xFFF2EEF3),
                                      borderRadius: BorderRadius.circular(999.0),
                                    ),
                                    child: Switch(
                                      value: _model.mainPrizeEnabled,
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
                                      activeTrackColor: const Color(0xFFB61B5A),
                                      inactiveTrackColor:
                                          const Color(0xFFDCD6DB),
                                      activeThumbColor: Colors.white,
                                      inactiveThumbColor: Colors.white,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      trackOutlineColor:
                                          WidgetStateProperty.all(
                                        Colors.transparent,
                                      ),
                                    ),
                                  ),
                                ),
                                if (_model.mainPrizeEnabled) ...[
                                  const SizedBox(height: 16.0),
                                  TextFormField(
                                    controller: _model.textController1,
                                    focusNode: _model.textFieldFocusNode1,
                                    autofocus: false,
                                    obscureText: false,
                                    decoration: _fieldDecoration(
                                      context,
                                      label: 'Titre du lot principal',
                                      hintText: 'ex : Un dîner pour 2',
                                    ),
                                    style: _fieldTextStyle(context),
                                    onChanged: (value) {
                                      if (_model.mainPrizeEnabled) {
                                        _model.textController4?.text =
                                            value.trim();
                                      }
                                    },
                                    validator: _model.textController1Validator
                                        .asValidator(context),
                                  ),
                                  const SizedBox(height: 12.0),
                                  TextFormField(
                                    controller: _model.textController2,
                                    focusNode: _model.textFieldFocusNode2,
                                    autofocus: false,
                                    obscureText: false,
                                    minLines: 4,
                                    maxLines: 4,
                                    decoration: _fieldDecoration(
                                      context,
                                      label: 'Description du lot principal',
                                      hintText:
                                          'ex : Un menu du marché pour 2, hors boisson',
                                    ),
                                    style: _fieldTextStyle(context),
                                    validator: _model.textController2Validator
                                        .asValidator(context),
                                  ),
                                  const SizedBox(height: 12.0),
                                  TextFormField(
                                    controller: _model.textController3,
                                    focusNode: _model.textFieldFocusNode3,
                                    autofocus: false,
                                    obscureText: false,
                                    decoration: _fieldDecoration(
                                      context,
                                      label: 'Valeur estimée du lot principal',
                                      suffixIcon: Icon(
                                        Icons.euro,
                                        color:
                                            FlutterFlowTheme.of(context).primary,
                                        size: 22.0,
                                      ),
                                    ),
                                    style: _fieldTextStyle(context),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
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
                                  const SizedBox(height: 8.0),
                                  Text(
                                    "Le lot principal doit être une valeur en € (ex : bon d'achat 20 €).\nPour les remises ou cadeaux clients, utilisez les gains immédiats.",
                                    style: FlutterFlowTheme.of(context)
                                        .bodySmall
                                        .override(
                                          font: GoogleFonts.inter(
                                            fontWeight: FontWeight.w400,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .bodySmall
                                                    .fontStyle,
                                          ),
                                          color: const Color(0xFF75728F),
                                          letterSpacing: 0.0,
                                          fontSize: 12.0,
                                          fontWeight: FontWeight.w400,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodySmall
                                                  .fontStyle,
                                        )
                                        .copyWith(height: 1.3),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildSectionCard(
                      context,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            context,
                            title: 'Lots à gains immédiats lors du grattage',
                            description:
                                'Ces lots sont remportés immédiatement pendant le jeu.',
                            trailing: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFFCECF4),
                                borderRadius: BorderRadius.circular(999.0),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14.0,
                                vertical: 8.0,
                              ),
                              child: Text(
                                '${_model.secondaryPrizes.length} ${_model.secondaryPrizes.length > 1 ? 'lots' : 'lot'}',
                                style: FlutterFlowTheme.of(context)
                                    .titleSmall
                                    .override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .titleSmall
                                            .fontStyle,
                                      ),
                                      color:
                                          FlutterFlowTheme.of(context).primary,
                                      letterSpacing: 0.0,
                                      fontSize: 14.0,
                                      fontWeight: FontWeight.w600,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .titleSmall
                                          .fontStyle,
                                    ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12.0),
                          Divider(
                            thickness: 1.0,
                            color: FlutterFlowTheme.of(context).alternate,
                          ),
                          if (!_model.mainPrizeEnabled) ...[
                            const SizedBox(height: 12.0),
                            TextFormField(
                              controller: _model.textController4,
                              focusNode: _model.textFieldFocusNode4,
                              autofocus: false,
                              obscureText: false,
                              decoration: _fieldDecoration(
                                context,
                                label: 'Titre du jeu',
                              ),
                              style: _fieldTextStyle(context),
                              validator: _model.textController4Validator
                                  .asValidator(context),
                            ),
                          ],
                          const SizedBox(height: 12.0),
                          ...List.generate(
                            _model.secondaryPrizes.length,
                            (index) => Padding(
                              padding: EdgeInsets.only(
                                bottom: index == _model.secondaryPrizes.length - 1
                                    ? 0.0
                                    : 12.0,
                              ),
                              child: _buildSecondaryPrizeCard(
                                context,
                                index,
                                _model.secondaryPrizes[index],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8.0),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _model.secondaryPrizes
                                      .add(SecondaryPrizeEntry());
                                });
                              },
                              icon: Icon(
                                Icons.add_circle_outline_rounded,
                                color: FlutterFlowTheme.of(context).primary,
                              ),
                              label: Text(
                                'Ajouter un lot',
                                style: FlutterFlowTheme.of(context)
                                    .titleMedium
                                    .override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .titleMedium
                                            .fontStyle,
                                      ),
                                      color:
                                          FlutterFlowTheme.of(context).primary,
                                      letterSpacing: 0.0,
                                      fontWeight: FontWeight.w600,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .titleMedium
                                          .fontStyle,
                                    ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: Color(0xFFF0DDE8),
                                ),
                                backgroundColor: const Color(0xFFFFFAFD),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18.0,
                                  vertical: 14.0,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18.0),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildSectionCard(
                      context,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            context,
                            title: 'Image du jeu',
                            description:
                                'Ajoutez un visuel clair pour présenter votre jeu.',
                          ),
                          const SizedBox(height: 8.0),
                          InkWell(
                            splashColor: Colors.transparent,
                            focusColor: Colors.transparent,
                            hoverColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            onTap: _pickGameImage,
                            child: Container(
                              width: double.infinity,
                              height: 184.0,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F7FC),
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
                                            : NetworkImage(
                                                _model.uploadedFileUrl_uploadDataNyu,
                                              ),
                                      )
                                    : null,
                                borderRadius: BorderRadius.circular(14.0),
                                border: Border.all(
                                  color: const Color(0x100E1220),
                                ),
                              ),
                              child: ((_model.uploadedLocalFile_uploadGameData5ir
                                              .bytes?.isEmpty ??
                                          true) &&
                                      _model
                                          .uploadedFileUrl_uploadDataNyu.isEmpty)
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 52.0,
                                            height: 52.0,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFFFFF),
                                              borderRadius:
                                                  BorderRadius.circular(14.0),
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: Color(0x080E1220),
                                                  blurRadius: 8.0,
                                                  offset: Offset(0.0, 2.0),
                                                ),
                                              ],
                                            ),
                                            child: Icon(
                                              Icons.add_photo_alternate_outlined,
                                              color:
                                                  FlutterFlowTheme.of(context)
                                                      .primary,
                                              size: 26.0,
                                            ),
                                          ),
                                          const SizedBox(height: 8.0),
                                          Text(
                                            'Ajouter une image',
                                            style: FlutterFlowTheme.of(context)
                                                .titleMedium
                                                .override(
                                                  font:
                                                      GoogleFonts.interTight(
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    fontStyle:
                                                        FlutterFlowTheme.of(
                                                                context)
                                                            .titleMedium
                                                            .fontStyle,
                                                  ),
                                                  letterSpacing: 0.0,
                                                  fontSize: 16.0,
                                                  fontWeight: FontWeight.w600,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .titleMedium
                                                          .fontStyle,
                                                ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildSectionCard(
                      context,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            context,
                            title: 'Dates',
                            description:
                                'Définissez la période d’activation du jeu.',
                          ),
                          const SizedBox(height: 8.0),
                          _buildDateField(
                            context,
                            label: 'Date de début',
                            value: dateTimeFormat(
                              'd/M/y',
                              _model.startDatePicked ?? getCurrentTimestamp,
                              locale:
                                  FFLocalizations.of(context).languageCode,
                            ),
                            onTap: _pickStartDate,
                          ),
                          const SizedBox(height: 8.0),
                          _buildDateField(
                            context,
                            label: 'Date de fin',
                            value: _model.datePicked != null
                                ? dateTimeFormat(
                                    'd/M/y',
                                    _model.datePicked,
                                    locale: FFLocalizations.of(context)
                                        .languageCode,
                                  )
                                : '',
                            onTap: _pickEndDate,
                          ),
                        ],
                      ),
                    ),
                    _buildSectionCard(
                      context,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            context,
                            title: 'Restrictions',
                            description:
                                'Choisissez si le jeu est accessible aux mineurs.',
                          ),
                          const SizedBox(height: 8.0),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 10.0,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF6F7FB),
                              borderRadius: BorderRadius.circular(14.0),
                              border: Border.all(
                                color: const Color(0x100E1220),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      style: FlutterFlowTheme.of(context)
                                          .bodyLarge
                                          .override(
                                            font: GoogleFonts.inter(
                                              fontWeight:
                                                  FlutterFlowTheme.of(context)
                                                      .bodyLarge
                                                      .fontWeight,
                                              fontStyle:
                                                  FlutterFlowTheme.of(context)
                                                      .bodyLarge
                                                      .fontStyle,
                                            ),
                                            color: const Color(0xFF6A6884),
                                            letterSpacing: 0.0,
                                            fontSize: 14.0,
                                            fontWeight: FontWeight.w400,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .bodyLarge
                                                    .fontStyle,
                                          ),
                                      children: [
                                        const TextSpan(
                                            text: 'Interdire aux mineurs ? '),
                                        TextSpan(
                                          text: _model.switchValue!
                                              ? 'Oui'
                                              : 'Non',
                                          style: FlutterFlowTheme.of(context)
                                              .bodyLarge
                                              .override(
                                                font: GoogleFonts.inter(
                                                  fontWeight: FontWeight.w600,
                                                  fontStyle:
                                                      FlutterFlowTheme.of(
                                                              context)
                                                          .bodyLarge
                                                          .fontStyle,
                                                ),
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .primaryText,
                                                letterSpacing: 0.0,
                                                fontSize: 14.0,
                                                fontWeight: FontWeight.w600,
                                                fontStyle:
                                                    FlutterFlowTheme.of(context)
                                                        .bodyLarge
                                                        .fontStyle,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8.0),
                                Switch(
                                  value: _model.switchValue!,
                                  onChanged: (newValue) async {
                                    safeSetState(
                                        () => _model.switchValue = newValue);
                                  },
                                  activeThumbColor: Colors.white,
                                  activeTrackColor: const Color(0xFFA0134D),
                                  inactiveTrackColor:
                                      const Color(0xFFD7D9E2),
                                  inactiveThumbColor: Colors.white,
                                  trackOutlineColor: WidgetStateProperty.all(
                                    Colors.transparent,
                                  ),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Builder(
                      builder: (context) => FFButtonWidget(
                        onPressed: _handleCreatePressed,
                        text: 'Créer le jeu',
                        options: FFButtonOptions(
                          width: double.infinity,
                          height: 52.0,
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          iconPadding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          color: FlutterFlowTheme.of(context).primary,
                          textStyle:
                              FlutterFlowTheme.of(context).titleLarge.override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .titleLarge
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .titleLarge
                                          .fontStyle,
                                    ),
                                    color: FlutterFlowTheme.of(context).info,
                                    letterSpacing: 0.0,
                                    fontSize: 20.0,
                                    fontWeight: FontWeight.w600,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .titleLarge
                                        .fontStyle,
                                  ),
                          elevation: 0.0,
                          borderRadius: BorderRadius.circular(18.0),
                        ),
                      ),
                    ),
                  ].divide(const SizedBox(height: 12.0)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

