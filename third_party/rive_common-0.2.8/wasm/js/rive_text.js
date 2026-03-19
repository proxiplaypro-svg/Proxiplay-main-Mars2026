RiveText["onRuntimeInitialized"] = function () {
  var nativeMakeGlyphPath = RiveText["makeGlyphPath"];
  var move = 0;
  var line = 1;
  var quad = 2;
  var cubic = 4;
  var close = 5;
  RiveText["makeGlyphPath"] = function (font, glyphId) {
    var glyph = nativeMakeGlyphPath(font, glyphId);
    var verbCount = glyph[3];
    var ptsPtr = glyph[1];
    var verbPtr = glyph[2];
    var verbs = RiveText["HEAPU8"]["subarray"](verbPtr, verbPtr + verbCount);

    let pointCount = 0;
    for (var verb of verbs) {
      switch (verb) {
        case move:
        case line:
          pointCount++;
          break;
        case quad:
          pointCount += 2;
          break;
        case cubic:
          pointCount += 3;
          break;
        default:
          break;
      }
    }

    const ptsStart = ptsPtr / 4;
    return {
      "rawPath": glyph[0],
      "verbs": verbs,
      "points": RiveText["HEAPF32"]["subarray"](
        ptsStart,
        ptsStart + pointCount * 2
      ),
    };
  };

  var nativeShapeText = RiveText["shapeText"];
  RiveText["shapeText"] = function (codeUnits, runsList) {
    var shapeResult = nativeShapeText(codeUnits, runsList);
    return {
      "rawResult": shapeResult,
      "results": RiveText["HEAPU8"]["subarray"](shapeResult),
    };
  };

  var nativeBreakLines = RiveText["breakLines"];
  RiveText["breakLines"] = function (shape, width, align) {
    var breakResult = nativeBreakLines(shape, width, align);
    return {
      "rawResult": breakResult,
      "results": RiveText["HEAPU8"]["subarray"](breakResult),
    };
  };

  var nativeFontFeatures = RiveText["fontFeatures"];
  RiveText["fontFeatures"] = function (font) {
    var featuresPtr = nativeFontFeatures(font);

    const view = new DataView(
      RiveText["HEAPU8"]["buffer"],
      RiveText["HEAPU8"]["byteOffset"] + featuresPtr
    );
    var dataPtr = view["getUint32"](0, true);
    var size = view["getUint32"](4, true);

    const dataView = new DataView(
      RiveText["HEAPU8"]["buffer"],
      RiveText["HEAPU8"]["byteOffset"] + dataPtr
    );

    var tags = [];
    for (var i = 0; i < size; i++) {
      var tag = dataView["getUint32"](i * 4, true);
      tags.push(tag);
    }

    RiveText["deleteFontFeatures"](featuresPtr);
    return tags;
  };
};
