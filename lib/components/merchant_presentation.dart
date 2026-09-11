import 'package:flutter/material.dart';

import '/backend/backend.dart';
import '/backend/schema/enums/enums.dart';
import '/widgets/proxiplay_network_image.dart';

const merchantInk = Color(0xFF2B285F);
const merchantAccent = Color(0xFFA0134D);
const merchantPaper = Color(0xFFFEFFFE);

String merchantAddress(EnseignesRecord merchant) => [
      merchant.address.trim(),
      [merchant.areaCode.trim(), merchant.city.trim()]
          .where((part) => part.isNotEmpty)
          .join(' '),
    ].where((part) => part.isNotEmpty).join(', ');

/// Presentation only: the caller supplies data and retains all business actions.
class MerchantRating extends StatelessWidget {
  const MerchantRating({super.key, required this.merchant});
  final EnseignesRecord merchant;

  @override
  Widget build(BuildContext context) {
    final rating = merchant.googleRating;
    if (rating == null || !rating.isFinite || rating < 0 || rating > 5) {
      return const SizedBox.shrink();
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        const Icon(Icons.star_rounded, color: Color(0xFFF5AB16), size: 20),
        Text(
            '${formattedGoogleRating(merchant)} Google'
            '${merchant.hasGoogleReviewsCount() ? ' (${merchant.googleReviewsCount} avis)' : ''}',
            style: const TextStyle(color: merchantInk, fontSize: 13)),
      ],
    );
  }
}

/// Keeps the existing Proxiplay image source; one load per mounted reference.
class MerchantPhoto extends StatefulWidget {
  const MerchantPhoto({super.key, required this.reference, this.future});
  final DocumentReference? reference;
  final Future<List<ImagesRecord>>? future;

  @override
  State<MerchantPhoto> createState() => _MerchantPhotoState();
}

class _MerchantPhotoState extends State<MerchantPhoto> {
  late Future<List<ImagesRecord>> _photos;
  void _load() {
    _photos = widget.future ??
        (widget.reference == null
            ? Future.value(const <ImagesRecord>[])
            : queryImagesRecordOnce(
                parent: widget.reference, singleRecord: true));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MerchantPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference?.path != widget.reference?.path ||
        oldWidget.future != widget.future) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ImagesRecord>>(
        future: _photos,
        builder: (context, snapshot) => MerchantPhotoContent(
          url: snapshot.data?.firstOrNull?.url ?? '',
        ),
      );
}

class MerchantPhotoContent extends StatelessWidget {
  const MerchantPhotoContent({super.key, this.url = ''});
  final String url;
  @override
  Widget build(BuildContext context) => url.trim().isEmpty
      ? const ColoredBox(
          color: Color(0xFFF3EFF5),
          child: Center(
              child: Icon(Icons.storefront_outlined,
                  size: 44, color: merchantInk)),
        )
      : ProxiplayNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity);
}

class MerchantSummaryCard extends StatelessWidget {
  const MerchantSummaryCard(
      {super.key,
      required this.merchant,
      required this.onTap,
      this.favorite,
      this.photoFuture,
      this.compact = false});
  final EnseignesRecord merchant;
  final VoidCallback onTap;
  final Widget? favorite;
  final Future<List<ImagesRecord>>? photoFuture;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final information = Padding(
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              merchant.name.trim().isEmpty
                  ? 'Commerçant'
                  : merchant.name.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: merchantInk,
                  fontSize: compact ? 17 : 20,
                  fontWeight: FontWeight.w700,
                  height: 1.15)),
          if (!compact && merchant.description.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(merchant.description.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF656171), height: 1.4)),
          ],
          if (merchant.city.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.location_on_rounded,
                  size: 17, color: merchantInk),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(merchant.city.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: merchantInk))),
            ]),
          ],
          if (merchant.googleRating != null) ...[
            const SizedBox(height: 6),
            MerchantRating(merchant: merchant),
          ],
          const SizedBox(height: 10),
          const Row(children: [
            Flexible(
                child: Text('Voir le commerçant',
                    style: TextStyle(
                        color: merchantAccent, fontWeight: FontWeight.w600))),
            SizedBox(width: 4),
            Icon(Icons.arrow_forward_rounded, size: 17, color: merchantAccent),
          ]),
        ],
      ),
    );
    final photo =
        MerchantPhoto(reference: merchant.reference, future: photoFuture);
    return Material(
      color: merchantPaper,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFF0ECF1))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: compact
            ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                SizedBox(width: 88, height: 112, child: photo),
                Expanded(child: information),
                if (favorite != null) favorite!,
              ])
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Stack(children: [
                  AspectRatio(aspectRatio: 1.35, child: photo),
                  if (favorite != null)
                    Positioned(
                        top: 10,
                        right: 10,
                        child: Material(
                            color: merchantPaper,
                            shape: const CircleBorder(),
                            child: favorite!)),
                ]),
                information,
              ]),
      ),
    );
  }
}

String merchantScheduleLabel(HorairesRecord record) {
  if (!record.hasIsOpen()) return 'Horaires non renseignés';
  if (!record.isOpen) return 'Fermé';
  String? interval(DateTime? from, DateTime? to) {
    if (from == null || to == null) return null;
    String time(DateTime date) =>
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return '${time(from)} – ${time(to)}';
  }

  final periods = record.isFullDay
      ? [
          interval(record.openingMorning, record.closingMorning),
          interval(record.openingAfternoon, record.closingAfternoon)
        ]
      : [interval(record.openingDay, record.closingDay)];
  final labels = periods.whereType<String>().toList();
  return labels.isEmpty ? 'Horaires non renseignés' : labels.join('\n');
}

/// One read-only weekly schedule, shared by merchant and collection-point pages.
class MerchantHours extends StatelessWidget {
  const MerchantHours({super.key, required this.hours});
  final List<HorairesRecord> hours;

  @override
  Widget build(BuildContext context) {
    final ordered = [...hours]..sort((a, b) =>
        (a.day == null ? a.order : DayOfTheWeek.values.indexOf(a.day!))
            .compareTo(
                b.day == null ? b.order : DayOfTheWeek.values.indexOf(b.day!)));
    if (ordered.isEmpty) {
      return const Text('Horaires non renseignés',
          style: TextStyle(color: Color(0xFF656171)));
    }
    return Column(
        children: ordered
            .map((day) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child: Text(day.day?.name ?? 'Jour non renseigné',
                                style: const TextStyle(
                                    color: merchantInk,
                                    fontWeight: FontWeight.w500))),
                        const SizedBox(width: 12),
                        Flexible(
                            child: Text(merchantScheduleLabel(day),
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                    color: Color(0xFF656171), height: 1.4))),
                      ]),
                ))
            .toList());
  }
}

/// Uses the already loaded schedule; expanding never performs a read.
class MerchantTodayHours extends StatefulWidget {
  const MerchantTodayHours({super.key, required this.hours, this.today});
  final List<HorairesRecord> hours;
  final DateTime? today;

  @override
  State<MerchantTodayHours> createState() => _MerchantTodayHoursState();
}

class _MerchantTodayHoursState extends State<MerchantTodayHours> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.hours.isEmpty) return MerchantHours(hours: widget.hours);
    final weekday = (widget.today ?? DateTime.now()).weekday - 1;
    final today = widget.hours
        .where((record) => record.day == DayOfTheWeek.values[weekday])
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (expanded)
          MerchantHours(hours: widget.hours)
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                    child: Text("Aujourd'hui",
                        style: TextStyle(
                            color: merchantInk, fontWeight: FontWeight.w500))),
                const SizedBox(width: 12),
                Flexible(
                    child: Text(
                        today == null
                            ? 'Horaires non renseignés'
                            : merchantScheduleLabel(today),
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                            color: Color(0xFF656171), height: 1.4))),
              ],
            ),
          ),
        TextButton(
          onPressed: () => setState(() => expanded = !expanded),
          style: TextButton.styleFrom(foregroundColor: merchantAccent),
          child: Text(expanded ? 'Réduire' : 'Voir tous les horaires'),
        ),
      ],
    );
  }
}

class MerchantSection extends StatelessWidget {
  const MerchantSection({super.key, required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: merchantPaper,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFF0ECF1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: merchantInk)),
          const SizedBox(height: 16),
          child,
        ]),
      );
}
