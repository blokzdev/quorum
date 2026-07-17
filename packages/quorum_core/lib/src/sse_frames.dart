/// The one place that knows SSE wire format (P5.2): decodes an SSE byte stream into the parsed
/// JSON payloads of its `data:` lines. Extracted from [SseTransport] so the pull stream can share
/// the frame layer WITHOUT sharing the event layer — run events and pull snapshots are separate
/// contracts by design (plan A1), and each transport applies its own frame filter on top.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Every parseable JSON object carried by a `data:` line. Skips `event:`/`id:`/comment lines,
/// empty payloads, and unparsable JSON. Callers filter their own heartbeats/noise (the run stream
/// drops type-less frames; the pull stream drops tag-less ones).
Stream<Map<String, dynamic>> sseJsonDataFrames(http.ByteStream body) async* {
  final lines = body.transform(utf8.decoder).transform(const LineSplitter());
  await for (final line in lines) {
    if (!line.startsWith('data:')) continue;
    final payload = line.substring(5).trim();
    if (payload.isEmpty) continue;
    try {
      yield jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      continue;
    }
  }
}
