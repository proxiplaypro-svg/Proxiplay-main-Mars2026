import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/google_places/google_place_search_result.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/services/google_places_service.dart';

/// Ouvre la recherche "Votre établissement Google" en feuille modale.
///
/// Retourne le [GooglePlaceSearchResult] choisi, ou `null` si le
/// commerçant ferme la recherche sans sélection (établissement introuvable,
/// ou simplement pas envie de l'associer maintenant) -- l'association
/// Google reste toujours optionnelle.
Future<GooglePlaceSearchResult?> showGoogleEstablishmentPicker(
  BuildContext context,
) {
  return showModalBottomSheet<GooglePlaceSearchResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _GoogleEstablishmentPickerSheet(),
  );
}

class _GoogleEstablishmentPickerSheet extends StatefulWidget {
  const _GoogleEstablishmentPickerSheet();

  @override
  State<_GoogleEstablishmentPickerSheet> createState() =>
      _GoogleEstablishmentPickerSheetState();
}

class _GoogleEstablishmentPickerSheetState
    extends State<_GoogleEstablishmentPickerSheet> {
  final _service = GooglePlacesService();
  final _queryController = TextEditingController();

  List<GooglePlaceSearchResult> _results = const [];
  bool _isSearching = false;
  bool _hasSearched = false;
  String? _errorMessage;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });
    try {
      final results = await _service.searchEstablishments(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _hasSearched = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _hasSearched = true;
        _errorMessage =
            'La recherche Google est momentanément indisponible. Réessayez.';
      });
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(20.0),
          ),
        ),
        padding: EdgeInsets.only(
          left: 20.0,
          right: 20.0,
          top: 16.0,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16.0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Votre établissement Google',
                    style: theme.headlineSmall.override(
                      font: GoogleFonts.interTight(
                        fontWeight: FontWeight.w700,
                        fontStyle: theme.headlineSmall.fontStyle,
                      ),
                      letterSpacing: 0.0,
                      fontWeight: FontWeight.w700,
                      fontStyle: theme.headlineSmall.fontStyle,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4.0),
            Text(
              'Recherchez le nom de votre commerce pour retrouver sa fiche Google.',
              style: theme.bodySmall.override(
                font: GoogleFonts.inter(
                  fontStyle: theme.bodySmall.fontStyle,
                ),
                color: theme.secondaryText,
                letterSpacing: 0.0,
                fontStyle: theme.bodySmall.fontStyle,
              ),
            ),
            const SizedBox(height: 14.0),
            TextField(
              controller: _queryController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Nom de votre établissement',
                filled: true,
                fillColor: theme.primaryBackground,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 14.0,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: const BorderSide(color: Color(0x00000000)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide(color: theme.primary, width: 1.2),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _isSearching ? null : _search,
                ),
              ),
            ),
            const SizedBox(height: 16.0),
            if (_isSearching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_isSearching && _errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Text(
                  _errorMessage!,
                  style: theme.bodyMedium.override(
                    font: GoogleFonts.inter(),
                    color: theme.error,
                  ),
                ),
              ),
            if (!_isSearching &&
                _errorMessage == null &&
                _hasSearched &&
                _results.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Text(
                  'Aucun établissement trouvé pour cette recherche.',
                  style: theme.bodyMedium.override(
                    font: GoogleFonts.inter(),
                    color: theme.secondaryText,
                  ),
                ),
              ),
            if (!_isSearching && _results.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1.0,
                    color: theme.alternate,
                  ),
                  itemBuilder: (context, index) {
                    final result = _results[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        result.name,
                        style: theme.bodyLarge.override(
                          font: GoogleFonts.inter(fontWeight: FontWeight.w600),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        result.formattedAddress,
                        style: theme.bodySmall.override(
                          font: GoogleFonts.inter(),
                          color: theme.secondaryText,
                        ),
                      ),
                      onTap: () => Navigator.of(context).pop(result),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8.0),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Je ne trouve pas mon établissement'),
            ),
          ],
        ),
      ),
    );
  }
}
