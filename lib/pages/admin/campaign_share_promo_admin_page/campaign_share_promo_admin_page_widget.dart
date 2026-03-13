import '/components/share_promo_banner_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/models/share_promo_models.dart';
import '/services/share_promo_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CampaignSharePromoAdminPageWidget extends StatefulWidget {
  const CampaignSharePromoAdminPageWidget({super.key});

  static String routeName = 'CampaignSharePromoAdminPage';
  static String routePath = 'campaignSharePromoAdminPage';

  @override
  State<CampaignSharePromoAdminPageWidget> createState() =>
      _CampaignSharePromoAdminPageWidgetState();
}

class _CampaignSharePromoAdminPageWidgetState
    extends State<CampaignSharePromoAdminPageWidget> {
  static const List<String> _kindOptions = <String>[
    'defaultInvite',
    'specialCampaign',
    'lowRemainingPlaysInvite',
  ];

  static const List<String> _audienceOptions = <String>[
    'all',
    'players',
    'high_value_players',
  ];

  static const List<String> _rewardTypeOptions = <String>[
    'all_games_until_midnight',
    'play_credit',
    'plays',
    'remaining_part',
    'game_bonus',
    'extra_play',
  ];

  final _service = SharePromoService();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _messageController;
  late final TextEditingController _ctaController;
  late final TextEditingController _rewardTypeController;
  late final TextEditingController _rewardValueController;
  late final TextEditingController _maxPerUserController;
  late final TextEditingController _maxPerInviteeController;

  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  bool _requireSignup = true;
  bool _isDraft = true;
  DateTime? _startAt;
  DateTime? _endAt;
  String _kind = 'defaultInvite';
  String _audience = 'all';

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _messageController = TextEditingController();
    _ctaController = TextEditingController();
    _rewardTypeController = TextEditingController();
    _rewardValueController = TextEditingController();
    _maxPerUserController = TextEditingController();
    _maxPerInviteeController = TextEditingController();
    _loadCampaign();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    _ctaController.dispose();
    _rewardTypeController.dispose();
    _rewardValueController.dispose();
    _maxPerUserController.dispose();
    _maxPerInviteeController.dispose();
    super.dispose();
  }

  Future<void> _loadCampaign() async {
    final campaign = await _service.loadCurrentCampaign();
    if (!mounted) {
      return;
    }
    setState(() {
      _enabled = campaign.enabled;
      _requireSignup = campaign.requireInviteeSignup;
      _isDraft = campaign.isDraft;
      _kind = _normalizeKind(campaign.kind);
      _audience = _normalizeAudience(campaign.audience);
      _startAt = campaign.startAt?.toDate();
      _endAt = campaign.endAt?.toDate();
      final normalizedRewardType = _isLegacyRewardType(campaign.rewardType)
          ? 'all_games_until_midnight'
          : _normalizeRewardType(campaign.rewardType);
      _titleController.text = _normalizeCampaignTitle(campaign.title);
      _messageController.text = _normalizeCampaignMessage(campaign.message);
      _ctaController.text = _normalizeCampaignCta(campaign.ctaText);
      _rewardTypeController.text = normalizedRewardType;
      _rewardValueController.text =
          normalizedRewardType == 'all_games_until_midnight'
              ? '0'
              : campaign.rewardValue.toString();
      _maxPerUserController.text = campaign.maxRewardsPerUser.toString();
      _maxPerInviteeController.text =
          campaign.maxRewardsPerInvitee.toString();
      _loading = false;
    });
  }

  String _normalizeKind(String value) {
    final normalized = value.trim();
    if (_kindOptions.contains(normalized)) {
      return normalized;
    }
    if (normalized == 'campaign') {
      return 'specialCampaign';
    }
    return 'defaultInvite';
  }

  String _normalizeAudience(String value) {
    final normalized = value.trim();
    if (_audienceOptions.contains(normalized)) {
      return normalized;
    }
    return 'all';
  }

  String _kindLabel(String value) {
    switch (value) {
      case 'defaultInvite':
        return 'Invitation standard';
      case 'specialCampaign':
        return 'Campagne speciale';
      case 'lowRemainingPlaysInvite':
        return 'Invitation relance joueur';
      default:
        return value;
    }
  }

  String _audienceLabel(String value) {
    switch (value) {
      case 'all':
        return 'Tous les joueurs';
      case 'players':
        return 'Joueurs actifs';
      case 'high_value_players':
        return 'Joueurs a forte valeur';
      default:
        return value;
    }
  }

  String _normalizeRewardType(String value) {
    final normalized = value.trim();
    if (_rewardTypeOptions.contains(normalized)) {
      return normalized;
    }
    return 'all_games_until_midnight';
  }

  String _rewardTypeLabel(String value) {
    switch (value) {
      case 'all_games_until_midnight':
        return 'Jeux jusqu a minuit';
      case 'play_credit':
      case 'plays':
      case 'remaining_part':
      case 'extra_play':
        return 'Parties supplementaires';
      case 'game_bonus':
        return 'Bonus de jeu';
      default:
        return value;
    }
  }

  bool _isLegacyRewardType(String value) {
    return <String>{
      'extra_play',
      'play_credit',
      'plays',
      'remaining_part',
    }.contains(value.trim());
  }

  String _normalizeCampaignTitle(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == 'Invitez vos proches') {
      return 'Inviter un ami';
    }
    return normalized;
  }

  String _normalizeCampaignMessage(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized == 'Partagez Proxiplay et gagnez des bonus.' ||
        normalized == 'Offrez 1 partie à un ami et débloquez un bonus' ||
        normalized == 'Offrez 1 partie a un ami et debloquez un bonus') {
      return 'Invite un ami et joue a tous les jeux jusqu a minuit.';
    }
    return normalized;
  }

  String _normalizeCampaignCta(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == 'Partager' || normalized == 'Inviter') {
      return 'Inviter un ami';
    }
    return normalized;
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initialDate =
        (isStart ? _startAt : _endAt) ?? DateTime.now().add(const Duration(days: 1));
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (pickedDate == null || !mounted) {
      return;
    }
    setState(() {
      if (isStart) {
        _startAt = pickedDate;
      } else {
        _endAt = pickedDate.add(const Duration(hours: 23, minutes: 59));
      }
    });
  }

  SharePromoCampaignModel _buildCampaign() {
    return SharePromoCampaignModel.empty().copyWith(
      enabled: _enabled,
      kind: _kind,
      title: _titleController.text.trim(),
      message: _messageController.text.trim(),
      ctaText: _ctaController.text.trim(),
      startAt: _startAt == null ? null : Timestamp.fromDate(_startAt!),
      endAt: _endAt == null ? null : Timestamp.fromDate(_endAt!),
      rewardType: _normalizeRewardType(_rewardTypeController.text),
      rewardValue: int.tryParse(_rewardValueController.text.trim()) ?? 0,
      maxRewardsPerUser: int.tryParse(_maxPerUserController.text.trim()) ?? 0,
      maxRewardsPerInvitee:
          int.tryParse(_maxPerInviteeController.text.trim()) ?? 0,
      requireInviteeSignup: _requireSignup,
      audience: _audience,
      isDraft: _isDraft,
    );
  }

  Future<void> _saveCampaign({bool disable = false}) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);
    try {
      final campaign = _buildCampaign().copyWith(
        enabled: disable ? false : _enabled,
        isDraft: disable ? true : _isDraft,
      );
      await _service.adminUpsertSharePromo(campaign);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(disable ? 'Campagne desactivee' : 'Campagne enregistree')),
      );
      await _loadCampaign();
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

  SharePromoData _previewData() {
    return SharePromoData(
      kind: SharePromoKind.defaultInvite,
      title: _titleController.text.trim().isEmpty
          ? 'Inviter un ami'
          : _titleController.text.trim(),
      subtitle: _messageController.text.trim().isEmpty
          ? 'Invite un ami et joue a tous les jeux jusqu a minuit.'
          : _messageController.text.trim(),
      ctaLabel: _ctaController.text.trim().isEmpty
          ? 'Inviter un ami'
          : _ctaController.text.trim(),
      icon: Icons.campaign_rounded,
      primaryColor: const Color(0xFF294C7A),
      secondaryColor: const Color(0xFF4E8BB8),
    );
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
          'Campagne de partage',
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
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Campagne active'),
                      value: _enabled,
                      onChanged: (value) => setState(() => _enabled = value),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Exiger l inscription du filleul'),
                      value: _requireSignup,
                      onChanged: (value) => setState(() => _requireSignup = value),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mode brouillon'),
                      value: _isDraft,
                      onChanged: (value) => setState(() => _isDraft = value),
                    ),
                    const SizedBox(height: 12.0),
                    DropdownButtonFormField<String>(
                      initialValue: _normalizeKind(_kind),
                      decoration: _inputDecoration('Type de campagne'),
                      items: _kindOptions
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(_kindLabel(item)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _kind = value ?? 'defaultInvite'),
                    ),
                    const SizedBox(height: 12.0),
                    TextFormField(
                      controller: _titleController,
                      decoration: _inputDecoration('Titre'),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? 'Champ requis' : null,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12.0),
                    TextFormField(
                      controller: _messageController,
                      decoration: _inputDecoration('Message'),
                      maxLines: 3,
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? 'Champ requis' : null,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12.0),
                    TextFormField(
                      controller: _ctaController,
                      decoration: _inputDecoration('Texte du bouton'),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? 'Champ requis' : null,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12.0),
                    Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: DropdownButtonFormField<String>(
                            initialValue: _normalizeRewardType(_rewardTypeController.text),
                            isExpanded: true,
                            decoration: _inputDecoration('Recompense').copyWith(
                              floatingLabelBehavior: FloatingLabelBehavior.always,
                              contentPadding: const EdgeInsetsDirectional.fromSTEB(
                                16.0,
                                18.0,
                                16.0,
                                18.0,
                              ),
                            ),
                            items: _rewardTypeOptions
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item,
                                    child: Text(
                                      _rewardTypeLabel(item),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) => setState(() {
                              final normalized =
                                  _normalizeRewardType(value ?? '');
                              _rewardTypeController.text = normalized;
                              if (normalized == 'all_games_until_midnight') {
                                _rewardValueController.text = '0';
                              }
                            }),
                          ),
                        ),
                        const SizedBox(width: 12.0),
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            controller: _rewardValueController,
                            decoration: _inputDecoration('Valeur'),
                            keyboardType: TextInputType.number,
                            validator: (value) =>
                                (int.tryParse(value ?? '') == null) ? 'Nombre invalide' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12.0),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _maxPerUserController,
                            decoration:
                                _inputDecoration('Max recompenses par parrain'),
                            keyboardType: TextInputType.number,
                            validator: (value) =>
                                (int.tryParse(value ?? '') == null) ? 'Nombre invalide' : null,
                          ),
                        ),
                        const SizedBox(width: 12.0),
                        Expanded(
                          child: TextFormField(
                            controller: _maxPerInviteeController,
                            decoration:
                                _inputDecoration('Max recompenses par filleul'),
                            keyboardType: TextInputType.number,
                            validator: (value) =>
                                (int.tryParse(value ?? '') == null) ? 'Nombre invalide' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12.0),
                    DropdownButtonFormField<String>(
                      initialValue: _normalizeAudience(_audience),
                      decoration: _inputDecoration('Audience'),
                      items: _audienceOptions
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(_audienceLabel(item)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _audience = value ?? 'all'),
                    ),
                    const SizedBox(height: 16.0),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickDate(isStart: true),
                            child: Text(
                              _startAt == null
                                  ? 'Debut'
                                  : dateTimeFormat('d/M/y', _startAt),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12.0),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickDate(isStart: false),
                            child: Text(
                              _endAt == null
                                  ? 'Fin'
                                  : dateTimeFormat('d/M/y', _endAt),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20.0),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _saving ? null : () => _saveCampaign(),
                            child: Text(
                              _saving ? 'Enregistrement...' : 'Enregistrer',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12.0),
                        Expanded(
                          child: OutlinedButton(
                            onPressed:
                                _saving ? null : () => _saveCampaign(disable: true),
                            child: const Text('Desactiver'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20.0),
              Text(
                'Apercu du bandeau joueur',
                style: theme.titleMedium.override(
                  font: GoogleFonts.interTight(),
                  letterSpacing: 0.0,
                ),
              ),
              const SizedBox(height: 12.0),
              SharePromoBanner(
                data: _previewData(),
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}
