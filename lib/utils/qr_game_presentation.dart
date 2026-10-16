class QrGamePresentation {
  const QrGamePresentation({
    required this.mainPrizeDescription,
    required this.gameDescription,
  });

  final String mainPrizeDescription;
  final String gameDescription;
}

String _readText(Object? value) => value is String ? value.trim() : '';

QrGamePresentation resolveQrGamePresentation({
  required Object? description,
  required Object? mainPrizeDescription,
  required Object? mainPrizeTitle,
  required bool isQrOnly,
}) {
  final gameDescription = _readText(description);
  final resolvedMainPrizeDescription =
      _readText(mainPrizeDescription).isNotEmpty
      ? _readText(mainPrizeDescription)
      : _readText(mainPrizeTitle).isNotEmpty
      ? _readText(mainPrizeTitle)
      : gameDescription;

  return QrGamePresentation(
    mainPrizeDescription: resolvedMainPrizeDescription,
    gameDescription:
        isQrOnly &&
            gameDescription.isNotEmpty &&
            gameDescription != resolvedMainPrizeDescription
        ? gameDescription
        : '',
  );
}
