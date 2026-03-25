import '/backend/backend.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'add_horaire_commercant_page_model.dart';
export 'add_horaire_commercant_page_model.dart';

class _LocalTimeRange {
  _LocalTimeRange({
    required this.start,
    required this.end,
  });

  TimeOfDay start;
  TimeOfDay end;
}

class _LocalDaySchedule {
  _LocalDaySchedule({
    required this.day,
    required this.isClosed,
    required this.ranges,
  });

  final DayOfTheWeek day;
  bool isClosed;
  final List<_LocalTimeRange> ranges;
}

class AddHoraireCommercantPageWidget extends StatefulWidget {
  const AddHoraireCommercantPageWidget({
    super.key,
    required this.enseigneRef,
    bool? created,
  }) : created = created ?? false;

  final DocumentReference? enseigneRef;
  final bool created;

  static String routeName = 'AddHoraireCommercantPage';
  static String routePath = 'addHoraireCommercantPage';

  @override
  State<AddHoraireCommercantPageWidget> createState() =>
      _AddHoraireCommercantPageWidgetState();
}

class _AddHoraireCommercantPageWidgetState
    extends State<AddHoraireCommercantPageWidget> {
  late AddHoraireCommercantPageModel _model;
  late List<_LocalDaySchedule> _draftSchedules;
  bool _didInitFromRecords = false;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => AddHoraireCommercantPageModel());
    _draftSchedules = _buildDefaultSchedules();

    logFirebaseEvent('screen_view',
        parameters: {'screen_name': 'AddHoraireCommercantPage'});
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  List<_LocalDaySchedule> _buildDefaultSchedules() {
    return DayOfTheWeek.values
        .map(
          (day) => _LocalDaySchedule(
            day: day,
            isClosed: true,
            ranges: [
              _LocalTimeRange(
                start: const TimeOfDay(hour: 9, minute: 0),
                end: const TimeOfDay(hour: 18, minute: 0),
              ),
            ],
          ),
        )
        .toList();
  }

  TimeOfDay _timeOfDayFromDateTime(DateTime value) {
    return TimeOfDay(hour: value.hour, minute: value.minute);
  }

  List<_LocalTimeRange> _rangesFromRecord(HorairesRecord record) {
    if (!record.isOpen) {
      return [
        _LocalTimeRange(
          start: const TimeOfDay(hour: 9, minute: 0),
          end: const TimeOfDay(hour: 18, minute: 0),
        ),
      ];
    }

    if (!record.isFullDay &&
        record.openingDay != null &&
        record.closingDay != null) {
      return [
        _LocalTimeRange(
          start: _timeOfDayFromDateTime(record.openingDay!),
          end: _timeOfDayFromDateTime(record.closingDay!),
        ),
      ];
    }

    final ranges = <_LocalTimeRange>[];
    if (record.openingMorning != null && record.closingMorning != null) {
      ranges.add(
        _LocalTimeRange(
          start: _timeOfDayFromDateTime(record.openingMorning!),
          end: _timeOfDayFromDateTime(record.closingMorning!),
        ),
      );
    }
    if (record.openingAfternoon != null && record.closingAfternoon != null) {
      ranges.add(
        _LocalTimeRange(
          start: _timeOfDayFromDateTime(record.openingAfternoon!),
          end: _timeOfDayFromDateTime(record.closingAfternoon!),
        ),
      );
    }

    if (ranges.isEmpty) {
      return [
        _LocalTimeRange(
          start: const TimeOfDay(hour: 9, minute: 0),
          end: const TimeOfDay(hour: 18, minute: 0),
        ),
      ];
    }

    ranges.sort((a, b) => _toMinutes(a.start).compareTo(_toMinutes(b.start)));
    return ranges;
  }

  void _initDraftFromRecords(List<HorairesRecord> records) {
    final defaults = _buildDefaultSchedules();
    for (final record in records) {
      final day = record.day;
      if (day == null) {
        continue;
      }
      final index = defaults.indexWhere((item) => item.day == day);
      if (index == -1) {
        continue;
      }
      defaults[index] = _LocalDaySchedule(
        day: day,
        isClosed: !record.isOpen,
        ranges: _rangesFromRecord(record),
      );
    }
    _draftSchedules = defaults;
    _didInitFromRecords = true;
  }

  int _toMinutes(TimeOfDay value) => value.hour * 60 + value.minute;

  String? _validateDraft() {
    for (final schedule in _draftSchedules) {
      if (schedule.isClosed) {
        continue;
      }

      final sortedRanges = [...schedule.ranges]
        ..sort((a, b) => _toMinutes(a.start).compareTo(_toMinutes(b.start)));

      for (final range in sortedRanges) {
        if (_toMinutes(range.start) >= _toMinutes(range.end)) {
          return 'Une plage de ${schedule.day.name} est invalide.';
        }
      }

      for (var i = 1; i < sortedRanges.length; i++) {
        if (_toMinutes(sortedRanges[i].start) <
            _toMinutes(sortedRanges[i - 1].end)) {
          return 'Deux plages de ${schedule.day.name} se chevauchent.';
        }
      }
    }
    return null;
  }

  Future<void> _pickTime({
    required _LocalTimeRange range,
    required bool isStart,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? range.start : range.end,
      builder: (context, child) {
        return wrapInMaterialTimePickerTheme(
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

    if (picked == null) {
      return;
    }

    safeSetState(() {
      if (isStart) {
        range.start = picked;
      } else {
        range.end = picked;
      }
    });
  }

  Widget _buildTimeChip({
    required TimeOfDay value,
    required VoidCallback onTap,
  }) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return Expanded(
      child: InkWell(
        splashColor: Colors.transparent,
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: FlutterFlowTheme.of(context).fieldBg,
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Padding(
            padding:
                const EdgeInsetsDirectional.fromSTEB(12.0, 14.0, 12.0, 14.0),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Icon(
                  Icons.access_time,
                  color: FlutterFlowTheme.of(context).primary,
                  size: 18.0,
                ),
                Text(
                  '$hour:$minute',
                  style: FlutterFlowTheme.of(context).bodyMedium.override(
                        font: GoogleFonts.inter(
                          fontWeight:
                              FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                          fontStyle:
                              FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                        ),
                        letterSpacing: 0.0,
                        fontWeight:
                            FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                        fontStyle:
                            FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                      ),
                ),
              ].divide(const SizedBox(width: 8.0)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDayCard(_LocalDaySchedule schedule) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  schedule.day.name,
                  style: FlutterFlowTheme.of(context).titleMedium.override(
                        font: GoogleFonts.interTight(
                          fontWeight:
                              FlutterFlowTheme.of(context).titleMedium.fontWeight,
                          fontStyle:
                              FlutterFlowTheme.of(context).titleMedium.fontStyle,
                        ),
                        letterSpacing: 0.0,
                        fontWeight:
                            FlutterFlowTheme.of(context).titleMedium.fontWeight,
                        fontStyle:
                            FlutterFlowTheme.of(context).titleMedium.fontStyle,
                      ),
                ),
                Row(
                  children: [
                    Checkbox(
                      value: schedule.isClosed,
                      onChanged: (value) {
                        safeSetState(() {
                          schedule.isClosed = value ?? false;
                        });
                      },
                    ),
                    Text(
                      'Fermé',
                      style: FlutterFlowTheme.of(context).bodyMedium.override(
                            font: GoogleFonts.inter(
                              fontWeight:
                                  FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                              fontStyle:
                                  FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                            ),
                            letterSpacing: 0.0,
                            fontWeight:
                                FlutterFlowTheme.of(context).bodyMedium.fontWeight,
                            fontStyle:
                                FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                          ),
                    ),
                  ],
                ),
              ],
            ),
            if (!schedule.isClosed)
              Column(
                children: schedule.ranges
                    .asMap()
                    .entries
                    .map((entry) {
                      final index = entry.key;
                      final range = entry.value;
                      return Row(
                        children: <Widget>[
                          _buildTimeChip(
                            value: range.start,
                            onTap: () => _pickTime(range: range, isStart: true),
                          ),
                          _buildTimeChip(
                            value: range.end,
                            onTap: () => _pickTime(range: range, isStart: false),
                          ),
                          if (schedule.ranges.length > 1)
                            IconButton(
                              onPressed: () {
                                safeSetState(() {
                                  schedule.ranges.removeAt(index);
                                });
                              },
                              icon: Icon(
                                Icons.close,
                                color: FlutterFlowTheme.of(context).error,
                                size: 18.0,
                              ),
                            ),
                        ].divide(const SizedBox(width: 10.0)),
                      );
                    })
                    .toList()
                    .divide(const SizedBox(height: 10.0)),
              ),
            if (!schedule.isClosed)
              Align(
                alignment: Alignment.centerLeft,
                child: FFButtonWidget(
                  onPressed: () async {
                    safeSetState(() {
                      schedule.ranges.add(
                        _LocalTimeRange(
                          start: const TimeOfDay(hour: 9, minute: 0),
                          end: const TimeOfDay(hour: 18, minute: 0),
                        ),
                      );
                    });
                  },
                  text: 'Ajouter une plage',
                  options: FFButtonOptions(
                    width: 160.0,
                    height: 36.0,
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(
                            14.0, 0.0, 14.0, 0.0),
                    iconPadding:
                        const EdgeInsetsDirectional.fromSTEB(0.0, 0.0, 0.0, 0.0),
                    color: FlutterFlowTheme.of(context).primaryBackground,
                    textStyle: FlutterFlowTheme.of(context).bodyMedium.override(
                          font: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontStyle:
                                FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                          ),
                          color: FlutterFlowTheme.of(context).primary,
                          letterSpacing: 0.0,
                          fontWeight: FontWeight.w600,
                          fontStyle:
                              FlutterFlowTheme.of(context).bodyMedium.fontStyle,
                        ),
                    elevation: 0.0,
                    borderSide: BorderSide(
                      color: FlutterFlowTheme.of(context).primary,
                      width: 1.0,
                    ),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
              ),
          ].divide(const SizedBox(height: 10.0)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<HorairesRecord>>(
      stream: queryHorairesRecord(
        parent: widget.enseigneRef,
        queryBuilder: (horairesRecord) => horairesRecord.orderBy('order'),
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
            body: const Center(
              child: SizedBox(
                width: 50.0,
                height: 50.0,
                child: SizedBox.shrink(),
              ),
            ),
          );
        }

        final horaires = snapshot.data!;
        if (!_didInitFromRecords) {
          _initDraftFromRecords(horaires);
        }

        return GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
            FocusManager.instance.primaryFocus?.unfocus();
          },
          child: PopScope(
            canPop: false,
            child: Scaffold(
              key: scaffoldKey,
              backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
              appBar: AppBar(
                backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
                automaticallyImplyLeading: false,
                leading: Visibility(
                  visible: widget.created == false,
                  child: InkWell(
                    splashColor: Colors.transparent,
                    focusColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    onTap: () async {
                      context.safePop();
                    },
                    child: Icon(
                      Icons.chevron_left_rounded,
                      color: FlutterFlowTheme.of(context).primaryText,
                      size: 24.0,
                    ),
                  ),
                ),
                title: Text(
                  'Horaires d\'ouverture',
                  style: FlutterFlowTheme.of(context).headlineMedium.override(
                        font: GoogleFonts.interTight(
                          fontWeight: FlutterFlowTheme.of(context)
                              .headlineMedium
                              .fontWeight,
                          fontStyle: FlutterFlowTheme.of(context)
                              .headlineMedium
                              .fontStyle,
                        ),
                        fontSize: 26.0,
                        letterSpacing: 0.0,
                        fontWeight: FlutterFlowTheme.of(context)
                            .headlineMedium
                            .fontWeight,
                        fontStyle: FlutterFlowTheme.of(context)
                            .headlineMedium
                            .fontStyle,
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
                  height: double.infinity,
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      fit: BoxFit.cover,
                      alignment: const AlignmentDirectional(-1.0, 1.0),
                      image: Image.asset(
                        'assets/images/Background.png',
                      ).image,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        20.0, 20.0, 20.0, 50.0),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            horaires.isEmpty
                                ? 'Ajoutez vos horaires.'
                                : 'Modifiez vos horaires jour par jour et ajoutez des plages si besoin.',
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
                                      .secondaryText,
                                  letterSpacing: 0.0,
                                  fontWeight: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .fontWeight,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .fontStyle,
                                ),
                          ),
                          Column(
                            children: _draftSchedules
                                .map(_buildDayCard)
                                .toList()
                                .divide(const SizedBox(height: 12.0)),
                          ),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: FFButtonWidget(
                                  onPressed: () async {
                                    final error = _validateDraft();
                                    if (error != null) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(error)),
                                      );
                                      return;
                                    }
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Modifications valides en local.'),
                                      ),
                                    );
                                  },
                                  text: 'Enregistrer',
                                  options: FFButtonOptions(
                                    width: double.infinity,
                                    height: 40.0,
                                    padding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                            16.0, 0.0, 16.0, 0.0),
                                    iconPadding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                            0.0, 0.0, 0.0, 0.0),
                                    color:
                                        FlutterFlowTheme.of(context).primary,
                                    textStyle: FlutterFlowTheme.of(context)
                                        .titleSmall
                                        .override(
                                          font: GoogleFonts.interTight(
                                            fontWeight:
                                                FlutterFlowTheme.of(context)
                                                    .titleSmall
                                                    .fontWeight,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .titleSmall
                                                    .fontStyle,
                                          ),
                                          color: Colors.white,
                                          letterSpacing: 0.0,
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .titleSmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .titleSmall
                                                  .fontStyle,
                                        ),
                                    elevation: 0.0,
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: FFButtonWidget(
                                  onPressed: () async {
                                    context.safePop();
                                  },
                                  text: 'Fermer',
                                  options: FFButtonOptions(
                                    width: double.infinity,
                                    height: 40.0,
                                    padding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                            16.0, 0.0, 16.0, 0.0),
                                    iconPadding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                            0.0, 0.0, 0.0, 0.0),
                                    color: FlutterFlowTheme.of(context)
                                        .primaryBackground,
                                    textStyle: FlutterFlowTheme.of(context)
                                        .titleSmall
                                        .override(
                                          font: GoogleFonts.interTight(
                                            fontWeight:
                                                FlutterFlowTheme.of(context)
                                                    .titleSmall
                                                    .fontWeight,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .titleSmall
                                                    .fontStyle,
                                          ),
                                          color:
                                              FlutterFlowTheme.of(context).primary,
                                          letterSpacing: 0.0,
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .titleSmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .titleSmall
                                                  .fontStyle,
                                        ),
                                    elevation: 0.0,
                                    borderSide: BorderSide(
                                      color:
                                          FlutterFlowTheme.of(context).primary,
                                      width: 1.0,
                                    ),
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                ),
                              ),
                            ].divide(const SizedBox(width: 12.0)),
                          ),
                        ].divide(const SizedBox(height: 16.0)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
