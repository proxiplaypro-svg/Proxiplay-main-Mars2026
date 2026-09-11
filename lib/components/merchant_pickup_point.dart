import 'package:flutter/material.dart';

import '/backend/backend.dart';
import '/components/merchant_presentation.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/pages/joueur/enseigne_detail_joueur_page/enseigne_detail_joueur_page_widget.dart';

/// Receives only the prize's enseigneId, never the source game's merchant.
class MerchantPickupPoint extends StatefulWidget {
  const MerchantPickupPoint({super.key, required this.enseigneRef});
  final DocumentReference? enseigneRef;
  @override
  State<MerchantPickupPoint> createState() => _MerchantPickupPointState();
}

class _MerchantPickupPointState extends State<MerchantPickupPoint> {
  Stream<DocumentSnapshot>? _merchant;
  Future<List<HorairesRecord>>? _hours;

  void _load() {
    final ref = widget.enseigneRef;
    final valid = ref != null && ref.parent.path == 'enseignes';
    _merchant = valid ? ref.snapshots() : null;
    _hours = null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MerchantPickupPoint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enseigneRef != widget.enseigneRef) _load();
  }

  Widget _unavailable() => const MerchantSection(
      title: 'Point de retrait',
      child: Text('Informations du commerçant indisponibles.'));

  @override
  Widget build(BuildContext context) {
    // In particular, never issue a collection-group horaires query for null.
    if (_merchant == null) return _unavailable();
    return StreamBuilder<DocumentSnapshot>(
        stream: _merchant,
        builder: (context, snapshot) {
          if (snapshot.hasError ||
              (snapshot.hasData && !snapshot.data!.exists)) {
            return _unavailable();
          }
          if (!snapshot.hasData) {
            return const MerchantSection(
                title: 'Point de retrait',
                child: Text('Chargement du commerçant…'));
          }
          final merchant = EnseignesRecord.fromSnapshot(snapshot.data!);
          final address = merchantAddress(merchant);
          return MerchantSection(
              title: 'Point de retrait',
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                            backgroundColor: Color(0xFFF9EAF1),
                            child: Icon(Icons.storefront_outlined,
                                color: merchantAccent)),
                        title: Text(
                            merchant.name.trim().isEmpty
                                ? 'Commerçant'
                                : merchant.name.trim(),
                            style: const TextStyle(
                                color: merchantInk,
                                fontWeight: FontWeight.w700)),
                        subtitle: const Text('Voir la fiche commerçant'),
                        trailing: const Icon(Icons.chevron_right_rounded,
                            color: merchantAccent),
                        onTap: () => context.pushNamed(
                            EnseigneDetailJoueurPageWidget.routeName,
                            queryParameters: {
                              'enseigneDoc':
                                  serializeParam(merchant, ParamType.Document)
                            }.withoutNulls,
                            extra: <String, dynamic>{'enseigneDoc': merchant})),
                    const SizedBox(height: 8),
                    Text(address.isEmpty ? 'Adresse non renseignée' : address,
                        style:
                            const TextStyle(color: merchantInk, height: 1.5)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      if (address.isNotEmpty)
                        TextButton.icon(
                            style: TextButton.styleFrom(
                                foregroundColor: merchantAccent),
                            onPressed: () => launchURL(
                                'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}'),
                            icon: const Icon(Icons.directions_outlined),
                            label: const Text('Itinéraire')),
                      if (merchant.phoneNumber.trim().isNotEmpty)
                        TextButton.icon(
                            style: TextButton.styleFrom(
                                foregroundColor: merchantAccent),
                            onPressed: () =>
                                launchURL('tel:${merchant.phoneNumber.trim()}'),
                            icon: const Icon(Icons.phone_outlined),
                            label: const Text('Appeler')),
                    ]),
                    ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        shape: const Border(),
                        title: const Text('Horaires du point de retrait',
                            style: TextStyle(fontSize: 14, color: merchantInk)),
                        children: [
                          Builder(
                              builder: (context) => FutureBuilder<
                                      List<HorairesRecord>>(
                                  future: _hours ??= queryHorairesRecordOnce(
                                      parent: merchant.reference),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasError) {
                                      return const Text(
                                          'Horaires indisponibles');
                                    }
                                    if (!snapshot.hasData) {
                                      return const Text(
                                          'Chargement des horaires…');
                                    }
                                    return MerchantHours(hours: snapshot.data!);
                                  }))
                        ]),
                  ]));
        });
  }
}
