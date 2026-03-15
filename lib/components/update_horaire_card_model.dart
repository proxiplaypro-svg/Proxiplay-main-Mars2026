import '/flutter_flow/flutter_flow_util.dart';
import 'update_horaire_card_widget.dart' show UpdateHoraireCardWidget;
import 'package:flutter/material.dart';

class UpdateHoraireCardModel extends FlutterFlowModel<UpdateHoraireCardWidget> {
  ///  State fields for stateful widgets in this component.

  final formKey1 = GlobalKey<FormState>();
  final formKey2 = GlobalKey<FormState>();
  // State field(s) for SwitchDay widget.
  bool? switchDayValue;
  // State field(s) for SwitchCoupureMidi widget.
  bool? switchCoupureMidiValue;
  DateTime? datePicked1;
  DateTime? datePicked2;
  DateTime? datePicked3;
  DateTime? datePicked4;
  DateTime? datePicked5;
  DateTime? datePicked6;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {}
}
