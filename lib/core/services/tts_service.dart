import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService extends ChangeNotifier {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isPlaying = false;
  String? _currentlySpeakingText;

  bool get isPlaying => _isPlaying;
  String? get currentlySpeakingText => _currentlySpeakingText;

  TtsService() {
    _initTts();
  }

  void _initTts() {
    _flutterTts.setStartHandler(() {
      _isPlaying = true;
      notifyListeners();
    });

    _flutterTts.setCompletionHandler(() {
      _isPlaying = false;
      _currentlySpeakingText = null;
      notifyListeners();
    });

    _flutterTts.setErrorHandler((msg) {
      _isPlaying = false;
      _currentlySpeakingText = null;
      notifyListeners();
    });
  }

  /// Speaks text with localized Indic TTS mapping
  Future<void> speak(String text, {String langCode = 'en', bool isHindi = false}) async {
    try {
      if (_isPlaying && _currentlySpeakingText == text) {
        await stop();
        return;
      }

      await _flutterTts.stop();
      _currentlySpeakingText = text;

      // Determine appropriate locale for Indian regional languages
      final effectiveCode = isHindi ? 'hi' : langCode;
      String ttsLocale;
      switch (effectiveCode) {
        case 'hi':
          ttsLocale = 'hi-IN';
          break;
        case 'mr':
          ttsLocale = 'mr-IN';
          break;
        case 'gu':
          ttsLocale = 'gu-IN';
          break;
        case 'bn':
          ttsLocale = 'bn-IN';
          break;
        case 'ta':
          ttsLocale = 'ta-IN';
          break;
        case 'te':
          ttsLocale = 'te-IN';
          break;
        case 'kn':
          ttsLocale = 'kn-IN';
          break;
        case 'ml':
          ttsLocale = 'ml-IN';
          break;
        case 'pa':
          ttsLocale = 'pa-IN';
          break;
        case 'or':
          ttsLocale = 'or-IN';
          break;
        case 'ur':
          ttsLocale = 'ur-IN';
          break;
        case 'as':
          ttsLocale = 'as-IN';
          break;
        case 'ne':
          ttsLocale = 'ne-NP';
          break;
        case 'sa':
          ttsLocale = 'sa-IN';
          break;
        case 'kok':
          ttsLocale = 'kok-IN';
          break;
        case 'mai':
          ttsLocale = 'mai-IN';
          break;
        case 'doi':
          ttsLocale = 'doi-IN';
          break;
        case 'brx':
          ttsLocale = 'brx-IN';
          break;
        case 'mni':
          ttsLocale = 'mni-IN';
          break;
        case 'sat':
          ttsLocale = 'sat-IN';
          break;
        case 'ks':
          ttsLocale = 'ks-IN';
          break;
        case 'sd':
          ttsLocale = 'sd-IN';
          break;
        default:
          ttsLocale = 'en-IN';
      }

      try {
        await _flutterTts.setLanguage(ttsLocale);
      } catch (e) {
        // Fallback to English if device engine lacks regional Indic pack
        await _flutterTts.setLanguage("en-IN");
      }

      await _flutterTts.setSpeechRate(0.48); // Natural, clear cadence for rural/elderly accessibility
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _isPlaying = true;
      notifyListeners();

      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint("TTS error: $e");
      _isPlaying = false;
      _currentlySpeakingText = null;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (_) {}
    _isPlaying = false;
    _currentlySpeakingText = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }
}
