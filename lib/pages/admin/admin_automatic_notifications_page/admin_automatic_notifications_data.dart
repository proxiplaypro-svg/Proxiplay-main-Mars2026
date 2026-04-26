class AutomaticNotificationScenario {
  AutomaticNotificationScenario({
    required this.id,
    required this.templateKey,
    required this.title,
    required this.description,
    required this.message,
    required this.delayDays,
    required this.frequency,
    required this.sendHour,
    required this.sendMinute,
    required this.isEnabled,
    required this.filterRemainingParts,
  });

  final String id;
  String templateKey;
  String title;
  String description;
  String message;
  int delayDays;
  String frequency;
  int sendHour;
  int sendMinute;
  bool isEnabled;
  bool filterRemainingParts;

  AutomaticNotificationScenario copy() => AutomaticNotificationScenario(
        id: id,
        templateKey: templateKey,
        title: title,
        description: description,
        message: message,
        delayDays: delayDays,
        frequency: frequency,
        sendHour: sendHour,
        sendMinute: sendMinute,
        isEnabled: isEnabled,
        filterRemainingParts: filterRemainingParts,
      );

  String get scheduleText =>
      '$delayDays j - ${frequency == 'once' ? '1 fois' : 'répétée'} - ${sendHour.toString().padLeft(2, '0')}h${sendMinute.toString().padLeft(2, '0')}';

  String get summary {
    final filters = filterRemainingParts ? ' - parties restantes' : '';
    return 'Envoi après $scheduleText$filters';
  }
}

class AutomaticNotificationsRepository {
  AutomaticNotificationsRepository._();

  static final AutomaticNotificationsRepository instance =
      AutomaticNotificationsRepository._();

  final List<AutomaticNotificationScenario> _scenarios = [
    AutomaticNotificationScenario(
      id: 'birthday',
      templateKey: 'birthday',
      title: 'Anniversaire',
      description: 'Envoyer une notification spéciale le jour anniversaire.',
      message: 'Bon anniversaire ! Venez jouer et découvrir vos avantages du jour.',
      delayDays: 0,
      frequency: 'once',
      sendHour: 9,
      sendMinute: 0,
      isEnabled: false,
      filterRemainingParts: false,
    ),
    AutomaticNotificationScenario(
      id: 'remainingParts',
      templateKey: 'remainingParts',
      title: 'Parties non jouées / remaining parts',
      description: 'Relancer les joueurs qui ont encore des parties disponibles.',
      message: 'Il vous reste des parties à jouer. Revenez tenter votre chance.',
      delayDays: 3,
      frequency: 'repeated',
      sendHour: 18,
      sendMinute: 0,
      isEnabled: false,
      filterRemainingParts: true,
    ),
    AutomaticNotificationScenario(
      id: 'favoriteMerchant',
      templateKey: 'favoriteMerchant',
      title: 'Commerçant favori a ajouté un jeu',
      description: 'Notifier les joueurs quand un commerce suivi publie un jeu.',
      message: 'Un commerçant que vous suivez vient de publier un nouveau jeu.',
      delayDays: 0,
      frequency: 'once',
      sendHour: 10,
      sendMinute: 0,
      isEnabled: false,
      filterRemainingParts: false,
    ),
    AutomaticNotificationScenario(
      id: 'endingSoon',
      templateKey: 'endingSoon',
      title: 'Rappel J-3 avant fin d’un jeu',
      description: 'Rappeler qu’un jeu suivi se termine bientôt.',
      message: 'Tic tac. Un jeu que vous suivez se termine bientôt.',
      delayDays: 3,
      frequency: 'once',
      sendHour: 18,
      sendMinute: 0,
      isEnabled: true,
      filterRemainingParts: false,
    ),
    AutomaticNotificationScenario(
      id: 'inactivePlayer',
      templateKey: 'inactivePlayer',
      title: 'Joueur inactif depuis X jours',
      description: 'Relancer automatiquement selon l’ancienneté d’inactivité.',
      message: 'Cela fait un moment. Revenez jouer et découvrir les nouveaux jeux.',
      delayDays: 7,
      frequency: 'once',
      sendHour: 18,
      sendMinute: 0,
      isEnabled: false,
      filterRemainingParts: false,
    ),
  ];

  List<AutomaticNotificationScenario> all() =>
      _scenarios.map((scenario) => scenario.copy()).toList();

  AutomaticNotificationScenario? getById(String id) {
    final match = _scenarios.where((scenario) => scenario.id == id);
    return match.isEmpty ? null : match.first.copy();
  }

  void updateScenario(AutomaticNotificationScenario updated) {
    final index = _scenarios.indexWhere((scenario) => scenario.id == updated.id);
    if (index >= 0) {
      _scenarios[index] = updated.copy();
    }
  }

  void toggleScenario(String id, bool enabled) {
    final index = _scenarios.indexWhere((scenario) => scenario.id == id);
    if (index >= 0) {
      _scenarios[index].isEnabled = enabled;
    }
  }

  AutomaticNotificationScenario createDraft() {
    return AutomaticNotificationScenario(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      templateKey: 'birthday',
      title: 'Nouvelle notification automatique',
      description: 'Scénario personnalisé.',
      message: 'Personnalisez le message de cette notification automatique.',
      delayDays: 3,
      frequency: 'once',
      sendHour: 18,
      sendMinute: 0,
      isEnabled: true,
      filterRemainingParts: false,
    );
  }

  void addScenario(AutomaticNotificationScenario scenario) {
    _scenarios.add(scenario.copy());
  }
}

class AutomaticNotificationTemplates {
  static const Map<String, Map<String, String>> definitions = {
    'birthday': {
      'title': 'Anniversaire',
      'description': 'Envoyer une notification spéciale le jour anniversaire.',
      'message': 'Bon anniversaire ! Venez jouer et profiter de votre jour spécial.',
    },
    'remainingParts': {
      'title': 'Parties non jouées / remaining parts',
      'description': 'Relancer les joueurs qui ont encore des parties disponibles.',
      'message': 'Il vous reste des parties. Revenez jouer avant de les oublier.',
    },
    'favoriteMerchant': {
      'title': 'Commerçant favori a ajouté un jeu',
      'description': 'Notifier les joueurs quand un commerce suivi publie un jeu.',
      'message': 'Un commerçant favori vient de publier un nouveau jeu.',
    },
    'endingSoon': {
      'title': 'Rappel J-3 avant fin d’un jeu',
      'description': 'Rappeler qu’un jeu suivi se termine bientôt.',
      'message': 'Tic tac. Le jeu que vous suivez se termine bientôt.',
    },
    'inactivePlayer': {
      'title': 'Joueur inactif depuis X jours',
      'description': 'Relancer automatiquement selon l’ancienneté d’inactivité.',
      'message': 'Cela fait un moment. Revenez découvrir les nouveaux jeux.',
    },
  };
}
