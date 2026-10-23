// DEV ONLY - isolated visual check of the ad components on a real device.
// Never part of the store app: it is only built with
//   flutter build apk --debug -t lib/dev/ad_preview_main.dart
// No Firebase at all: fictitious campaigns served by an in-memory service,
// creatives from the app's bundled images, events shown on screen instead of
// being sent. Production campaigns and data are never read nor written.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:flutter/material.dart';

import '/services/ad_system_service.dart';
import '/widgets/ad_banner_zone.dart';
import '/widgets/open_ad_gate.dart';

enum _Scenario { normal, slow, brokenImage, noAd, adultsOnlyMinor, adultsOnlyAdult }

const _scenarioLabels = {
  _Scenario.normal: 'Normal : 3 campagnes fictives',
  _Scenario.slow: 'Réseau lent (3 s) : interstitiel abandonné',
  _Scenario.brokenImage: 'Image cassée : rien ne s’affiche',
  _Scenario.noAd: 'Aucune campagne : aucun espace vide',
  _Scenario.adultsOnlyMinor: 'Campagne majeurs, compte mineur',
  _Scenario.adultsOnlyAdult: 'Campagne majeurs, compte majeur',
};

class _PreviewAds extends AdSystemService {
  _PreviewAds(this.scenario, this.log);
  final _Scenario scenario;
  final void Function(String) log;

  AdPlacementConfig _campaign(String placement, String asset) => AdPlacementConfig(
        enabled: true,
        imageUrl: scenario == _Scenario.brokenImage ? 'broken' : asset,
        destinationUrl: '',
        startAt: null,
        endAt: null,
        frequencyCapHours: 0,
        campaignId: 'fictive-$placement',
        // One banner per communication type to check their labels.
        communicationType: placement == 'home_banner' ? 'discovery'
            : placement == 'home_banner_referral' ? 'proxiplay_info' : 'advertisement',
        adultsOnly: scenario == _Scenario.adultsOnlyMinor || scenario == _Scenario.adultsOnlyAdult,
      );

  @override
  Future<AdPlacementConfig> getDisplayablePlacement(String placement,
      {required bool signedIn}) async {
    if (scenario == _Scenario.slow) await Future<void>.delayed(const Duration(seconds: 3));
    if (scenario == _Scenario.noAd) {
      return const AdPlacementConfig(enabled: false, imageUrl: '', destinationUrl: '',
          startAt: null, endAt: null, frequencyCapHours: null);
    }
    final asset = placement == 'open' ? 'assets/images/Background.png' : 'assets/images/logo_D_secondaire.png';
    final config = _campaign(placement, asset);
    // Same outcome as the server: an adults-only creative is only handed to
    // an adult account.
    if (scenario == _Scenario.adultsOnlyMinor) {
      log('$placement : campagne majeurs refusée (compte mineur)');
      return config.withCreative(imageUrl: '', destinationUrl: '');
    }
    return config;
  }

  @override
  Future<void> recordImpression(String placement, {String campaignId = ''}) async =>
      log('IMPRESSION $placement ($campaignId)');

  @override
  Future<void> recordClick(String placement, {String campaignId = ''}) async =>
      log('CLIC $placement ($campaignId)');
}

ImageProvider _creative(String url) =>
    url == 'broken' ? const AssetImage('assets/images/__absent__.png') : AssetImage(url);

void main() => runApp(const _AdPreviewApp());

class _AdPreviewApp extends StatefulWidget {
  const _AdPreviewApp();
  @override
  State<_AdPreviewApp> createState() => _AdPreviewAppState();
}

class _AdPreviewAppState extends State<_AdPreviewApp> {
  _Scenario _scenario = _Scenario.normal;
  int _run = 0;
  final _events = <String>[];

  void _log(String event) {
    final time = TimeOfDay.now();
    setState(() => _events.insert(0, '${time.hour}:${time.minute.toString().padLeft(2, '0')} $event'));
  }

  void _restart(_Scenario scenario) {
    OpenAdGate.resetAttemptForTest(); // simulates a cold start
    setState(() {
      _scenario = scenario;
      _run++;
      _events.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ads = _PreviewAds(_scenario, _log);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _PreviewHome(
        key: ValueKey(_run),
        ads: ads,
        scenario: _scenario,
        events: _events,
        onRestart: _restart,
      ),
    );
  }
}

class _PreviewHome extends StatelessWidget {
  const _PreviewHome({
    super.key,
    required this.ads,
    required this.scenario,
    required this.events,
    required this.onRestart,
  });

  final _PreviewAds ads;
  final _Scenario scenario;
  final List<String> events;
  final void Function(_Scenario) onRestart;

  Widget _fakeCards(String title) => Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 4,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => Container(
                  width: 140,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAEFFD),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text('Jeu fictif ${i + 1}'),
                ),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final adult = scenario == _Scenario.adultsOnlyAdult || scenario != _Scenario.adultsOnlyMinor;
    return OpenAdGate(
      signedIn: adult,
      service: ads,
      imageProviderFor: _creative,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Aperçu publicité (fictif)'),
          backgroundColor: const Color(0xFF2C2F5B),
          foregroundColor: Colors.white,
        ),
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              children: [
                const ListTile(title: Text('Scénario (relance à froid)')),
                for (final s in _Scenario.values)
                  ListTile(
                    title: Text(_scenarioLabels[s]!),
                    selected: s == scenario,
                    onTap: () {
                      Navigator.pop(context);
                      onRestart(s);
                    },
                  ),
              ],
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(10),
              color: const Color(0xFFFFF4D6),
              child: Text('Scénario : ${_scenarioLabels[scenario]}\n'
                  'Aucune donnée réelle. Événements (au lieu d’être envoyés) :\n'
                  '${events.isEmpty ? '—' : events.take(6).join('\n')}'),
            ),
            _fakeCards('JEUX À LA UNE'),
            AdBannerZone(
              placement: 'home_banner',
              configFuture: ads.getDisplayablePlacement('home_banner', signedIn: adult),
              service: ads,
              trailingSpace: 16,
              imageProviderFor: _creative,
            ),
            _fakeCards('NOUVEAUTÉS'),
            _fakeCards('BIENTÔT TERMINÉS'),
            Container(
              margin: const EdgeInsets.only(top: 20),
              height: 110,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6FB),
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: const Text('Bloc « Parrainer un commerçant » (fictif)'),
            ),
            AdBannerZone(
              placement: 'home_banner_referral',
              configFuture: ads.getDisplayablePlacement('home_banner_referral', signedIn: adult),
              service: ads,
              imageProviderFor: _creative,
            ),
            _fakeCards('ANIMATIONS'),
            const SizedBox(height: 400),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home), label: 'Accueil'),
            NavigationDestination(icon: Icon(Icons.favorite), label: 'Favoris'),
            NavigationDestination(icon: Icon(Icons.card_giftcard), label: 'Lots'),
            NavigationDestination(icon: Icon(Icons.person), label: 'Profil'),
          ],
        ),
      ),
    );
  }
}
