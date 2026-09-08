import 'package:flutter_tts/flutter_tts.dart';

class TextToSpeechVoice {
  const TextToSpeechVoice({
    required this.name,
    required this.locale,
    this.identifier,
  });

  final String name;
  final String locale;
  final String? identifier;

  /// Human-readable label for UI display, e.g. "Samantha (en-US)".
  String get displayLabel => '$name ($locale)';

  @override
  bool operator ==(Object other) {
    return other is TextToSpeechVoice &&
        other.name == name &&
        other.locale == locale &&
        other.identifier == identifier;
  }

  @override
  int get hashCode => Object.hash(name, locale, identifier);
}

abstract class TextToSpeechClient {
  Future<void> awaitSpeakCompletion(bool awaitCompletion);
  Future<List<TextToSpeechVoice>> getVoices();
  Future<void> setLanguage(String language);
  Future<void> setVoice(TextToSpeechVoice voice);
  Future<void> speak(String text);
  Future<void> stop();
}

class FlutterTextToSpeechClient implements TextToSpeechClient {
  FlutterTextToSpeechClient({FlutterTts? flutterTts})
    : _flutterTts = flutterTts ?? FlutterTts();

  final FlutterTts _flutterTts;

  @override
  Future<void> awaitSpeakCompletion(bool awaitCompletion) async {
    await _flutterTts.awaitSpeakCompletion(awaitCompletion);
  }

  @override
  Future<List<TextToSpeechVoice>> getVoices() async {
    final rawVoices = await _flutterTts.getVoices;
    if (rawVoices is! List<Object?>) {
      throw StateError('flutter_tts returned an invalid voices payload.');
    }

    return rawVoices.map(_voiceFromObject).toList(growable: false);
  }

  @override
  Future<void> setLanguage(String language) async {
    await _flutterTts.setLanguage(language);
  }

  @override
  Future<void> setVoice(TextToSpeechVoice voice) async {
    final voicePayload = <String, String>{
      'name': voice.name,
      'locale': voice.locale,
    };
    if (voice.identifier != null) {
      voicePayload['identifier'] = voice.identifier!;
    }

    await _flutterTts.setVoice(voicePayload);
  }

  @override
  Future<void> speak(String text) async {
    await _flutterTts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _flutterTts.stop();
  }

  TextToSpeechVoice _voiceFromObject(Object? rawVoice) {
    if (rawVoice is! Map<Object?, Object?>) {
      throw StateError('flutter_tts returned a malformed voice entry.');
    }

    final name = _requireString(rawVoice['name'], 'name');
    final locale = _requireString(rawVoice['locale'], 'locale');
    final identifier = _optionalString(rawVoice['identifier']);

    return TextToSpeechVoice(
      name: name,
      locale: locale,
      identifier: identifier,
    );
  }

  String _requireString(Object? value, String key) {
    if (value is! String || value.isEmpty) {
      throw StateError('flutter_tts voice entry is missing a valid $key.');
    }

    return value;
  }

  String? _optionalString(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is! String || value.isEmpty) {
      throw StateError('flutter_tts voice entry contains an invalid identifier.');
    }

    return value;
  }
}
