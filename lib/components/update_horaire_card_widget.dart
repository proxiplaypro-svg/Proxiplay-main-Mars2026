import '/backend/backend.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'update_horaire_card_model.dart';
export 'update_horaire_card_model.dart';

class _LocalTimeRange {
  _LocalTimeRange({
    required this.start,
    required this.end,
  });

  TimeOfDay start;
  TimeOfDay end;
}

class UpdateHoraireCardWidget extends StatefulWidget {
  const UpdateHoraireCardWidget({
    super.key,
    required this.day,
  });

  final HorairesRecord? day;

  @override
  State<UpdateHoraireCardWidget> createState() =>
      _UpdateHoraireCardWidgetState();
}

class _UpdateHoraireCardWidgetState extends State<UpdateHoraireCardWidget> {
  late UpdateHoraireCardModel _model;
  late bool _isClosed;
  late List<_LocalTimeRange> _ranges;

  @override
  void setState(VoidCallback callback) {
    super.setState(callback);
    _model.onUpdate();
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => UpdateHoraireCardModel());
    _isClosed = !(widget.day?.isOpen ?? false);
    _ranges = _buildRangesFromRecord(widget.day);
  }

  @override
  void dispose() {
    _model.maybeDispose();
    super.dispose();
  }

  List<_LocalTimeRange> _buildRangesFromRecord(HorairesRecord? record) {
    if (record == null || !record.isOpen) {
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
          start:
              TimeOfDay(hour: record.openingDay!.hour, minute: record.openingDay!.minute),
          end:
              TimeOfDay(hour: record.closingDay!.hour, minute: record.closingDay!.minute),
        ),
      ];
    }

    final ranges = <_LocalTimeRange>[];
    if (record.openingMorning != null && record.closingMorning != null) {
      ranges.add(
        _LocalTimeRange(
          start: TimeOfDay(
              hour: record.openingMorning!.hour,
              minute: record.openingMorning!.minute),
          end: TimeOfDay(
              hour: record.closingMorning!.hour,
              minute: record.closingMorning!.minute),
        ),
      );
    }
    if (record.openingAfternoon != null && record.closingAfternoon != null) {
      ranges.add(
        _LocalTimeRange(
          start: TimeOfDay(
              hour: record.openingAfternoon!.hour,
              minute: record.openingAfternoon!.minute),
          end: TimeOfDay(
              hour: record.closingAfternoon!.hour,
              minute: record.closingAfternoon!.minute),
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

  int _toMinutes(TimeOfDay value) => value.hour * 60 + value.minute;

  String? _validateRanges() {
    final sorted = [..._ranges]
      ..sort((a, b) => _toMinutes(a.start).compareTo(_toMinutes(b.start)));

    for (final range in sorted) {
      if (_toMinutes(range.start) >= _toMinutes(range.end)) {
        return 'Une plage est invalide.';
      }
    }

    for (var i = 1; i < sorted.length; i++) {
      if (_toMinutes(sorted[i].start) < _toMinutes(sorted[i - 1].end)) {
        return 'Deux plages se chevauchent.';
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

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 1.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Container(
        width: MediaQuery.sizeOf(context).width * 1.0,
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  widget.day?.day?.name ?? 'Jour',
                  style: FlutterFlowTheme.of(context).bodyLarge.override(
                        font: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontStyle:
                              FlutterFlowTheme.of(context).bodyLarge.fontStyle,
                        ),
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.w600,
                        fontStyle:
                            FlutterFlowTheme.of(context).bodyLarge.fontStyle,
                      ),
                ),
                Row(
                  children: [
                    Checkbox(
                      value: _isClosed,
                      onChanged: (value) {
                        safeSetState(() {
                          _isClosed = value ?? false;
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
                if (!_isClosed)
                  Column(
                    children: _ranges
                        .asMap()
                        .entries
                        .map((entry) {
                          final index = entry.key;
                          final range = entry.value;
                          return Row(
                            children: <Widget>[
                              _buildTimeChip(
                                value: range.start,
                                onTap: () =>
                                    _pickTime(range: range, isStart: true),
                              ),
                              _buildTimeChip(
                                value: range.end,
                                onTap: () =>
                                    _pickTime(range: range, isStart: false),
                              ),
                              if (_ranges.length > 1)
                                IconButton(
                                  onPressed: () {
                                    safeSetState(() {
                                      _ranges.removeAt(index);
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
                if (!_isClosed)
                  FFButtonWidget(
                    onPressed: () async {
                      safeSetState(() {
                        _ranges.add(
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
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          14.0, 0.0, 14.0, 0.0),
                      iconPadding: const EdgeInsetsDirectional.fromSTEB(
                          0.0, 0.0, 0.0, 0.0),
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
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FFButtonWidget(
                        onPressed: () async {
                          final error = _isClosed ? null : _validateRanges();
                          if (error != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error)),
                            );
                            return;
                          }
                          Navigator.pop(context);
                        },
                        text: 'Enregistrer',
                        options: FFButtonOptions(
                          width: double.infinity,
                          height: 40.0,
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              16.0, 0.0, 16.0, 0.0),
                          iconPadding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          color: FlutterFlowTheme.of(context).primary,
                          textStyle:
                              FlutterFlowTheme.of(context).titleSmall.override(
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
                    Expanded(
                      child: FFButtonWidget(
                        onPressed: () async {
                          Navigator.pop(context);
                        },
                        text: 'Fermer',
                        options: FFButtonOptions(
                          width: double.infinity,
                          height: 40.0,
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              16.0, 0.0, 16.0, 0.0),
                          iconPadding: const EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          color: FlutterFlowTheme.of(context).primaryBackground,
                          textStyle:
                              FlutterFlowTheme.of(context).titleSmall.override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .titleSmall
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .titleSmall
                                          .fontStyle,
                                    ),
                                    color: FlutterFlowTheme.of(context).primary,
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .titleSmall
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .titleSmall
                                        .fontStyle,
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
                  ].divide(const SizedBox(width: 12.0)),
                ),
              ].divide(const SizedBox(height: 12.0)),
            ),
          ),
        ),
      ),
    );
  }
}
