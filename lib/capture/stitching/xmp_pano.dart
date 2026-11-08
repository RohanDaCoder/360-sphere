/// XMP GPano metadata for equirectangular 360° photos.
///
/// Google (Street View, Photos) and most gallery apps recognize a 360°
/// photo by the `GPano` XMP packet embedded in the JPEG — *not* by its 2:1
/// aspect ratio. The original app's photos carry this metadata (added by
/// its cloud stitching service; the app itself maps Google's
/// "Not a 360° Photo" rejection when it is missing). This recreation
/// writes the packet itself, so stitched and imported photos behave like
/// real 360° photos everywhere.
///
/// The packet is inserted as an `APP1` segment directly after the SOI
/// marker, the standard location photo services look for it.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Namespace URI of the GPano schema.
const String gpanoNamespace = 'http://ns.google.com/photos/1.0/panorama/';

/// Standard XMP header that must prefix the packet inside APP1.
const String _xmpHeader = 'http://ns.adobe.com/xap/1.0/\x00';

/// Builds the GPano XMP packet for a full-frame equirectangular photo.
String buildGpanoXmp({
  required int width,
  required int height,
  String captureSoftware = '360Sphere',
  double? poseHeadingDegrees,
  String? title,
}) {
  final heading = poseHeadingDegrees == null
      ? ''
      : '\n     GPano:PoseHeadingDegrees="${poseHeadingDegrees.toStringAsFixed(1)}"';
  final dcTitle = (title == null || title.trim().isEmpty)
      ? ''
      : '\n    <dc:title>\n'
          '     <rdf:Alt>\n'
          '      <rdf:li xml:lang="x-default">${_xmlEscape(title)}</rdf:li>\n'
          '     </rdf:Alt>\n'
          '    </dc:title>';
  return '<?xpacket begin="\uFEFF" id="W5M0MpCehiHzreSzNTczkc9d"?>\n'
      '<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="360Sphere">\n'
      ' <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n'
      '  <rdf:Description rdf:about=""\n'
      '    xmlns:GPano="$gpanoNamespace"\n'
      '    xmlns:dc="http://purl.org/dc/elements/1.1/"\n'
      '    GPano:ProjectionType="equirectangular"\n'
      '     GPano:UsePanoramaViewer="True"\n'
      '     GPano:CaptureSoftware="${_xmlEscape(captureSoftware)}"\n'
      '     GPano:FullPanoWidthPixels="$width"\n'
      '     GPano:FullPanoHeightPixels="$height"\n'
      '     GPano:CroppedAreaImageWidthPixels="$width"\n'
      '     GPano:CroppedAreaImageHeightPixels="$height"\n'
      '     GPano:CroppedAreaLeftPixels="0"\n'
      '     GPano:CroppedAreaTopPixels="0"'
      '$heading\n'
      '  >$dcTitle\n'
      '  </rdf:Description>\n'
      ' </rdf:RDF>\n'
      '</x:xmpmeta>\n'
      '<?xpacket end="w"?>';
}

/// Inserts (or replaces) the GPano XMP APP1 segment in [jpeg] and returns
/// the new JPEG bytes.
Uint8List writeGpanoXmp(
  Uint8List jpeg, {
  required int width,
  required int height,
  String captureSoftware = '360Sphere',
  double? poseHeadingDegrees,
  String? title,
}) {
  if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) {
    throw ArgumentError('Not a JPEG (missing SOI marker)');
  }

  // Locate any existing XMP APP1 so it can be replaced.
  final existing = _findXmpSegment(jpeg);

  final packet = utf8.encode(buildGpanoXmp(
    width: width,
    height: height,
    captureSoftware: captureSoftware,
    poseHeadingDegrees: poseHeadingDegrees,
    title: title,
  ));
  final header = utf8.encode(_xmpHeader);
  final segmentDataLength = header.length + packet.length;
  final segment = Uint8List(4 + segmentDataLength);
  segment[0] = 0xFF;
  segment[1] = 0xE1; // APP1
  segment[2] = ((segmentDataLength + 2) >> 8) & 0xFF; // length incl. itself
  segment[3] = (segmentDataLength + 2) & 0xFF;
  segment.setRange(4, 4 + header.length, header);
  segment.setRange(4 + header.length, segment.length, packet);

  final out = BytesBuilder();
  if (existing == null) {
    // SOI + XMP + rest of the file.
    out.add(Uint8List.sublistView(jpeg, 0, 2));
    out.add(segment);
    out.add(Uint8List.sublistView(jpeg, 2));
  } else {
    out.add(Uint8List.sublistView(jpeg, 0, 2));
    out.add(segment);
    out.add(Uint8List.sublistView(jpeg, existing.end));
  }
  return out.toBytes();
}

/// Whether the JPEG carries an XMP packet mentioning the GPano namespace.
bool hasGpanoXmp(Uint8List jpeg) {
  final seg = _findXmpSegment(jpeg);
  if (seg == null) return false;
  final body = utf8.decode(
    Uint8List.sublistView(jpeg, seg.bodyStart, seg.end),
    allowMalformed: true,
  );
  return body.contains('GPano') || body.contains(gpanoNamespace);
}

/// Reads `GPano:ProjectionType` from the XMP packet, if present.
String? gpanoProjectionType(Uint8List jpeg) {
  final seg = _findXmpSegment(jpeg);
  if (seg == null) return null;
  final body = utf8.decode(
    Uint8List.sublistView(jpeg, seg.bodyStart, seg.end),
    allowMalformed: true,
  );
  final m = RegExp(r'GPano:ProjectionType="([^"]+)"').firstMatch(body);
  return m?.group(1);
}

class _App1Segment {
  const _App1Segment(this.start, this.end, this.bodyStart);
  final int start; // offset of the 0xFF marker
  final int end; // offset just past the segment
  final int bodyStart; // offset just past the APP1 length field
}

/// Finds the first APP1 segment carrying an XMP packet.
_App1Segment? _findXmpSegment(Uint8List jpeg) {
  if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) return null;
  var i = 2;
  final header = utf8.encode(_xmpHeader);
  while (i + 4 <= jpeg.length) {
    if (jpeg[i] != 0xFF) return null; // desynced — not a segment start
    final marker = jpeg[i + 1];
    if (marker == 0xD8 ||
        (marker >= 0xD0 && marker <= 0xD7) ||
        marker == 0x01) {
      i += 2; // standalone marker
      continue;
    }
    if (marker == 0xDA) return null; // start of scan — no XMP before it
    final len = (jpeg[i + 2] << 8) | jpeg[i + 3];
    if (marker == 0xE1 &&
        i + 4 + header.length <= jpeg.length &&
        _listEquals(jpeg, i + 4, header)) {
      return _App1Segment(i, i + 2 + len, i + 4 + header.length);
    }
    i += 2 + len;
  }
  return null;
}

bool _listEquals(Uint8List src, int start, List<int> pattern) {
  for (var k = 0; k < pattern.length; k++) {
    if (src[start + k] != pattern[k]) return false;
  }
  return true;
}

String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
