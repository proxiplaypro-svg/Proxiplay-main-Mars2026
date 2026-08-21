import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/models/monthly_challenge_models.dart';
import '/services/monthly_challenge_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CampaignMonthlyChallengeAdminPageWidget extends StatefulWidget {
  const CampaignMonthlyChallengeAdminPageWidget({
    super.key,
    this.challengeType = 'attendance',
  });

  final String challengeType;

  @override
  State<CampaignMonthlyChallengeAdminPageWidget> createState() =>
      _CampaignMonthlyChallengeAdminPageWidgetState();
}

class _CampaignMonthlyChallengeAdminPageWidgetState
    extends State<CampaignMonthlyChallengeAdminPageWidget> {
  final _service = MonthlyChallengeService();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _monthController;
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _targetDaysController;
  late final TextEditingController _prizeTitleController;
  late final TextEditingController _prizeDescriptionController;
  late final TextEditingController _prizeValueController;
  late final TextEditingController _imageUrlController;
  late final TextEditingController _restaurantRefController;
  late final TextEditingController _restaurantNameController;
  late final TextEditingController _restaurantImageUrlController;

  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  DateTime? _drawDate;

  @override
  void initState() {
    super.initState();
    _monthController = TextEditingController();
    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
    _targetDaysController = TextEditingController();
    _prizeTitleController = TextEditingController();
    _prizeDescriptionController = TextEditingController();
    _prizeValueController = TextEditingController();
    _imageUrlController = TextEditingController();
    _restaurantRefController = TextEditingController();
    _restaurantNameController = TextEditingController();
    _restaurantImageUrlController = TextEditingController();
    _loadConfig();
  }

  @override
  void dispose() {
    _monthController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _targetDaysController.dispose();
    _prizeTitleController.dispose();
    _prizeDescriptionController.dispose();
    _prizeValueController.dispose();
    _imageUrlController.dispose();
    _restaurantRefController.dispose();
    _restaurantNameController.dispose();
    _restaurantImageUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final config = await _service.adminGetMonthlyChallengeConfig(
      type: widget.challengeType,
      month: _monthController.text.trim(),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _enabled = config.enabled;
      _drawDate = config.drawDate?.toDate();
      _monthController.text = config.month;
      _titleController.text = config.title;
      _descriptionController.text = config.description;
      _targetDaysController.text = config.targetDays.toString();
      _prizeTitleController.text = config.prizeTitle;
      _prizeDescriptionController.text = config.prizeDescription;
      _prizeValueController.text = config.prizeValue.toString();
      _imageUrlController.text = config.imageUrl;
      _restaurantRefController.text = config.restaurantRef;
      _restaurantNameController.text = config.restaurantName;
      _restaurantImageUrlController.text = config.restaurantImageUrl;
      _loading = false;
    });
  }

  Future<void> _pickDrawDate() async {
    final now = DateTime.now();
    final initialDate = _drawDate ?? now.add(const Duration(days: 7));
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (pickedDate == null || !mounted) {
      return;
    }
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_drawDate ?? now),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _drawDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime?.hour ?? 9,
        pickedTime?.minute ?? 0,
      );
    });
  }

  DateTime? _parseMonthStart(String raw) {
    final value = raw.trim();
    final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(value);
    if (match == null) {
      return null;
    }
    final year = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    if (year == null || month == null || month < 1 || month > 12) {
      return null;
    }
    return DateTime(year, month);
  }

  int _daysInMonth(DateTime monthStart) {
    return DateTime(monthStart.year, monthStart.month + 1, 0).day;
  }

  String? _validateTargetDays(String? value) {
    final parsed = int.tryParse((value ?? '').trim());
    if (parsed == null || parsed <= 0) {
      return 'Nombre invalide';
    }
    final monthStart = _parseMonthStart(_monthController.text);
    if (monthStart != null && parsed > _daysInMonth(monthStart)) {
      return 'Depasse le nombre de jours du mois';
    }
    return null;
  }

  String? _validateDrawDate() {
    final monthStart = _parseMonthStart(_monthController.text);
    if (_drawDate == null) {
      return 'Date du tirage requise';
    }
    if (monthStart == null) {
      return null;
    }
    final monthEnd = DateTime(
      monthStart.year,
      monthStart.month + 1,
      0,
      23,
      59,
      59,
      999,
    );
    if (!_drawDate!.isAfter(monthEnd)) {
      return 'Le tirage doit etre apres la fin du mois du defi';
    }
    return null;
  }

  MonthlyChallengeConfigModel _buildConfig() {
    return MonthlyChallengeConfigModel.empty().copyWith(
      type: widget.challengeType,
      enabled: _enabled,
      month: _monthController.text.trim(),
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      targetDays: int.tryParse(_targetDaysController.text.trim()) ?? 15,
      prizeTitle: _prizeTitleController.text.trim(),
      prizeDescription: _prizeDescriptionController.text.trim(),
      prizeValue: int.tryParse(_prizeValueController.text.trim()) ?? 0,
      imageUrl: _imageUrlController.text.trim(),
      restaurantRef: _restaurantRefController.text.trim(),
      restaurantName: _restaurantNameController.text.trim(),
      restaurantImageUrl: _restaurantImageUrlController.text.trim(),
      drawDate: _drawDate == null ? null : Timestamp.fromDate(_drawDate!),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final drawDateError = _validateDrawDate();
    if (drawDateError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(drawDateError)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.adminUpsertMonthlyChallenge(_buildConfig());
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Défi mensuel enregistré.')),
      );
      await _loadConfig();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    if (_loading) {
      return Scaffold(
        backgroundColor: theme.secondaryBackground,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: theme.secondaryBackground,
      appBar: AppBar(
        title: Text(
          widget.challengeType == 'restaurant' ? 'Resto du mois' : 'Défi d’assiduité',
          style: theme.titleLarge.override(
            font: GoogleFonts.interTight(),
            letterSpacing: 0.0,
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20.0),
            children: [
              Container(
                padding: const EdgeInsets.all(18.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22.0),
                ),
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      value: _enabled,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Défi actif'),
                      onChanged: (value) => setState(() => _enabled = value),
                    ),
                    const SizedBox(height: 12.0),
                    TextFormField(
                      controller: _monthController,
                      decoration: _inputDecoration('Mois (YYYY-MM)'),
                      validator: (value) => _parseMonthStart(value ?? '') != null
                          ? null
                          : 'Format attendu: YYYY-MM',
                    ),
                    if (widget.challengeType == 'restaurant') ...[
                      const SizedBox(height: 12.0),
                      TextFormField(
                        controller: _restaurantRefController,
                        decoration: _inputDecoration('Référence restaurant (enseignes/{id})'),
                        validator: (value) => (value == null || !value.trim().startsWith('enseignes/'))
                            ? 'Sélectionne une référence enseigne valide'
                            : null,
                      ),
                      const SizedBox(height: 12.0),
                      TextFormField(
                        controller: _restaurantNameController,
                        decoration: _inputDecoration('Nom du restaurant'),
                        validator: (value) => (value == null || value.trim().isEmpty)
                            ? 'Champ requis'
                            : null,
                      ),
                      const SizedBox(height: 12.0),
                      TextFormField(
                        controller: _restaurantImageUrlController,
                        decoration: _inputDecoration('Image restaurant URL'),
                      ),
                    ],
                    const SizedBox(height: 12.0),
                    TextFormField(
                      controller: _titleController,
                      decoration: _inputDecoration('Titre'),
                      validator: (value) => (value == null || value.trim().isEmpty)
                          ? 'Champ requis'
                          : null,
                    ),
                    const SizedBox(height: 12.0),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: _inputDecoration('Description'),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12.0),
                    TextFormField(
                      controller: _targetDaysController,
                      decoration: _inputDecoration('Objectif en jours'),
                      keyboardType: TextInputType.number,
                      validator: _validateTargetDays,
                    ),
                    const SizedBox(height: 12.0),
                    TextFormField(
                      controller: _prizeTitleController,
                      decoration: _inputDecoration('Lot'),
                      validator: (value) => (value == null || value.trim().isEmpty)
                          ? 'Champ requis'
                          : null,
                    ),
                    const SizedBox(height: 12.0),
                    TextFormField(
                      controller: _prizeDescriptionController,
                      decoration: _inputDecoration('Détail du lot'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12.0),
                    TextFormField(
                      controller: _prizeValueController,
                      decoration: _inputDecoration('Valeur du lot'),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        final parsed = int.tryParse((value ?? '').trim());
                        if (parsed == null || parsed < 0) {
                          return 'Nombre invalide';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12.0),
                    TextFormField(
                      controller: _imageUrlController,
                      decoration: _inputDecoration('Image URL'),
                    ),
                    const SizedBox(height: 14.0),
                    OutlinedButton.icon(
                      onPressed: _pickDrawDate,
                      icon: const Icon(Icons.event_rounded),
                      label: Text(
                        _drawDate == null
                            ? 'Choisir la date du tirage'
                            : dateTimeFormat('d/M/y H:mm', _drawDate),
                      ),
                    ),
                    if (_validateDrawDate() != null) ...[
                      const SizedBox(height: 8.0),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _validateDrawDate()!,
                          style: theme.bodySmall.override(
                            font: GoogleFonts.inter(),
                            color: const Color(0xFFB42318),
                            letterSpacing: 0.0,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18.0),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        child: Text(
                          _saving ? 'Enregistrement...' : 'Enregistrer',
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
    );
  }
}
