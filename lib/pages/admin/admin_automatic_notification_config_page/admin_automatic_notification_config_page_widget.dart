import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '/auth/firebase_auth/auth_util.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '../admin_automatic_notifications_page/admin_automatic_notifications_data.dart';

const scenarioFirestoreMap = {
  'inactive_player': 'inactive_players_7d',
  'birthday': 'birthday',
  'remaining_parts': 'remaining_parts',
  'favorite_merchant_new_game': 'favorite_merchant_new_game',
  'game_end_reminder': 'game_end_reminder',
};

class AdminAutomaticNotificationConfigPageWidget extends StatefulWidget {
  const AdminAutomaticNotificationConfigPageWidget({
    super.key,
    this.scenarioId,
    this.isNew = false,
  });

  final String? scenarioId;
  final bool isNew;

  static String routeName = 'AdminAutomaticNotificationConfigPage';
  static String routePath = 'adminAutomaticNotificationConfig';

  @override
  State<AdminAutomaticNotificationConfigPageWidget> createState() =>
      _AdminAutomaticNotificationConfigPageWidgetState();
}

class _AdminAutomaticNotificationConfigPageWidgetState
    extends State<AdminAutomaticNotificationConfigPageWidget> {
  final _formKey = GlobalKey<FormState>();
  late AutomaticNotificationScenario _scenario;
  late TextEditingController _delayController;
  late TextEditingController _messageController;
  bool _isLoadingFirestoreConfig = false;

  @override
  void initState() {
    super.initState();
    final repository = AutomaticNotificationsRepository.instance;
    _scenario = widget.isNew
        ? repository.createDraft()
        : (repository.getById(widget.scenarioId ?? '') ?? repository.createDraft());
    _delayController = TextEditingController(text: _scenario.delayDays.toString());
    _messageController = TextEditingController(text: _scenario.message);
    _loadScenarioFromFirestore();
  }

  @override
  void dispose() {
    _delayController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _scenario.sendHour, minute: _scenario.sendMinute),
    );
    if (selected == null) return;
    setState(() {
      _scenario.sendHour = selected.hour;
      _scenario.sendMinute = selected.minute;
    });
  }

  void _applyTemplate(String templateKey) {
    final template = AutomaticNotificationTemplates.definitions[templateKey];
    if (template == null) return;
    setState(() {
      _scenario.templateKey = templateKey;
      _scenario.title = template['title'] ?? _scenario.title;
      _scenario.description = template['description'] ?? _scenario.description;
      _scenario.message = template['message'] ?? _scenario.message;
      _messageController.text = _scenario.message;
    });
  }

  String? _selectedScenarioKeyForFirestore(AutomaticNotificationScenario scenario) {
    switch (scenario.id) {
      case 'inactivePlayer':
        return 'inactive_player';
      case 'birthday':
        return 'birthday';
      case 'remainingParts':
        return 'remaining_parts';
      case 'favoriteMerchant':
        return 'favorite_merchant_new_game';
      case 'endingSoon':
        return 'game_end_reminder';
      default:
        return null;
    }
  }

  String? _automationDocIdForScenario(AutomaticNotificationScenario scenario) {
    final selectedScenario = _selectedScenarioKeyForFirestore(scenario);
    if (selectedScenario == null) {
      debugPrint(
        '[admin_automatic_notification_config] Unknown scenario id=${scenario.id}, skipping Firestore load/save.',
      );
      return null;
    }

    final docId = scenarioFirestoreMap[selectedScenario];
    if (docId == null) {
      debugPrint(
        '[admin_automatic_notification_config] Missing Firestore mapping for scenario=$selectedScenario.',
      );
      return null;
    }

    return docId;
  }

  String _normalizeFrequencyForUi(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    return raw == 'repeat' || raw == 'repeated' ? 'repeated' : 'once';
  }

  int _normalizeSendHour(dynamic value) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    if (parsed == null) {
      return 18;
    }
    return parsed.clamp(0, 23);
  }

  bool _readRemainingPartsOnly(Map<String, dynamic> data) {
    final filters = data['filters'];
    if (filters is Map<String, dynamic>) {
      return filters['remainingPartsOnly'] == true;
    }
    if (filters is Map) {
      return filters['remainingPartsOnly'] == true;
    }
    return false;
  }

  String _readDefaultMessageBody(Map<String, dynamic> data) {
    final messagesByStatus = data['messagesByStatus'];
    if (messagesByStatus is Map<String, dynamic>) {
      final defaultMessage = messagesByStatus['default'];
      if (defaultMessage is Map<String, dynamic>) {
        return (defaultMessage['body'] ?? '').toString().trim();
      }
      if (defaultMessage is Map) {
        return (defaultMessage['body'] ?? '').toString().trim();
      }
    }
    if (messagesByStatus is Map) {
      final defaultMessage = messagesByStatus['default'];
      if (defaultMessage is Map) {
        return (defaultMessage['body'] ?? '').toString().trim();
      }
    }
    return '';
  }

  Future<void> _loadScenarioFromFirestore() async {
    final docId = _automationDocIdForScenario(_scenario);
    if (docId == null) {
      return;
    }

    setState(() => _isLoadingFirestoreConfig = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('notification_automations')
          .doc(docId)
          .get();
      if (!snapshot.exists || !mounted) {
        return;
      }

      final data = snapshot.data() ?? <String, dynamic>{};
      final cooldownDays =
          data['cooldownDays'] is num ? (data['cooldownDays'] as num).toInt() : null;
      final frequency = _normalizeFrequencyForUi(data['frequency']);
      final sendHour = _normalizeSendHour(data['sendHour']);
      final remainingPartsOnly = _readRemainingPartsOnly(data);
      final isActive = data['isActive'] == true;
      final messageBody = _readDefaultMessageBody(data);

      setState(() {
        _scenario.delayDays = cooldownDays ?? _scenario.delayDays;
        _scenario.frequency = frequency;
        _scenario.sendHour = sendHour;
        _scenario.sendMinute = 0;
        _scenario.filterRemainingParts = remainingPartsOnly;
        _scenario.isEnabled = isActive;
        if (messageBody.isNotEmpty) {
          _scenario.message = messageBody;
          _messageController.text = messageBody;
        }
        _delayController.text = _scenario.delayDays.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingFirestoreConfig = false);
      }
    }
  }

  String _normalizeFrequencyForFirestore(String value) {
    return value == 'repeated' ? 'repeat' : 'once';
  }

  Future<void> _saveScenarioToFirestore() async {
    final docId = _automationDocIdForScenario(_scenario);
    if (docId == null) {
      return;
    }

    final ref =
        FirebaseFirestore.instance.collection('notification_automations').doc(docId);
    final snapshot = await ref.get();

    await ref.set(
      {
        'cooldownDays': _scenario.delayDays,
        'frequency': _normalizeFrequencyForFirestore(_scenario.frequency),
        'sendHour': _scenario.sendHour,
        'isActive': _scenario.isEnabled,
        'updatedAt': FieldValue.serverTimestamp(),
        'filters': {
          'remainingPartsOnly': _scenario.filterRemainingParts,
        },
        'messagesByStatus': {
          'default': {
            'body': _scenario.message,
          },
        },
        if (!snapshot.exists) 'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _saveScenario() async {
    if (!_formKey.currentState!.validate()) return;
    _scenario.delayDays = int.tryParse(_delayController.text.trim()) ?? 0;
    _scenario.message = _messageController.text.trim();

    await _saveScenarioToFirestore();

    final repository = AutomaticNotificationsRepository.instance;
    if (widget.isNew) {
      repository.addScenario(_scenario);
    } else {
      repository.updateScenario(_scenario);
    }
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (currentUserDocument == null && loggedIn) {
      return const Scaffold(body: Center(child: SizedBox.shrink()));
    }
    if (currentUserDocument?.userRole != Roles.admin) {
      return Scaffold(
        body: Center(
          child: Text('Admin only.', style: FlutterFlowTheme.of(context).bodyMedium),
        ),
      );
    }

    final timeLabel =
        '${_scenario.sendHour.toString().padLeft(2, '0')}h${_scenario.sendMinute.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew
            ? 'Créer une notification automatique'
            : 'Configuration de la notification'),
      ),
      body: SafeArea(
        child: _isLoadingFirestoreConfig
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _section(
                      context,
                      child: DropdownButtonFormField<String>(
                        value: _scenario.templateKey,
                        decoration: _inputDecoration(context, 'Type de scénario'),
                        items: AutomaticNotificationTemplates.definitions.entries
                            .map(
                              (entry) => DropdownMenuItem<String>(
                                value: entry.key,
                                child: Text(entry.value['title'] ?? entry.key),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          _applyTemplate(value);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      context,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_scenario.title,
                              style: FlutterFlowTheme.of(context).titleMedium),
                          const SizedBox(height: 4),
                          Text(_scenario.description,
                              style: FlutterFlowTheme.of(context).bodySmall),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      context,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _delayController,
                            keyboardType: TextInputType.number,
                            decoration: _inputDecoration(context, 'Délai (jours)'),
                            validator: (value) => value == null || value.trim().isEmpty
                                ? 'Requis'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _scenario.frequency,
                            decoration: _inputDecoration(context, 'Fréquence'),
                            items: const [
                              DropdownMenuItem(value: 'once', child: Text('Une fois')),
                              DropdownMenuItem(
                                  value: 'repeated', child: Text('Répétée')),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _scenario.frequency = value);
                            },
                          ),
                          const SizedBox(height: 12),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Heure d’envoi'),
                            subtitle: Text(timeLabel),
                            trailing: const Icon(Icons.schedule_outlined),
                            onTap: _pickTime,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      context,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _messageController,
                            minLines: 4,
                            maxLines: 6,
                            decoration: _inputDecoration(context, 'Message'),
                            validator: (value) => value == null || value.trim().isEmpty
                                ? 'Requis'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Filtrer sur les parties restantes'),
                            subtitle: const Text(
                              'Afficher uniquement les joueurs ayant encore des parties.',
                            ),
                            value: _scenario.filterRemainingParts,
                            onChanged: (value) {
                              setState(() => _scenario.filterRemainingParts = value);
                            },
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Activer le scénario'),
                            value: _scenario.isEnabled,
                            onChanged: (value) {
                              setState(() => _scenario.isEnabled = value);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      context,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Résumé', style: FlutterFlowTheme.of(context).titleSmall),
                          const SizedBox(height: 8),
                          Text(_scenario.summary),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _saveScenario,
                      child: Text(widget.isNew ? 'Créer le scénario' : 'Enregistrer'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _section(BuildContext context, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).primaryBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: FlutterFlowTheme.of(context).alternate),
      ),
      child: child,
    );
  }

  InputDecoration _inputDecoration(BuildContext context, String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: FlutterFlowTheme.of(context).secondaryBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }
}
