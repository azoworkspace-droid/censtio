import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../providers/currency_provider.dart';
import '../services/gemini_service.dart';
import '../theme/app_theme.dart';

class VoiceAssistantDialog extends ConsumerStatefulWidget {
  final String title;
  final bool isExpense;

  const VoiceAssistantDialog({
    super.key,
    this.title = '🪄 AI Voice Assistant',
    this.isExpense = false,
  });

  @override
  ConsumerState<VoiceAssistantDialog> createState() =>
      _VoiceAssistantDialogState();
}

class _VoiceAssistantDialogState extends ConsumerState<VoiceAssistantDialog>
    with SingleTickerProviderStateMixin {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _speechAvailable = false;
  String? _localeId;
  String _text = 'Listening...';
  String _transcript = '';
  bool _isProcessing = false;
  bool _processingScheduled = false;

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (val) {
        if ((val == 'done' || val == 'notListening') && mounted) {
          // speech_to_text may report `done` before its final onResult event.
          // The final transcript is processed from onResult instead.
          setState(() => _isListening = false);
          _scheduleProcessing();
        }
      },
      onError: (val) {
        if (!mounted) return;
        final isNoMatch = val.errorMsg == 'error_no_match';
        setState(() {
          _isListening = false;
          _text = isNoMatch
              ? 'No speech recognized. Tap the microphone and speak clearly.'
              : 'Speech recognition error: ${val.errorMsg}';
        });
        _stopListening();
      },
    );
    if (!mounted) return;
    if (available) {
      _speechAvailable = true;
      final locales = await _speech.locales();
      final deviceLanguage =
          WidgetsBinding.instance.platformDispatcher.locale.languageCode;
      final matchingLocale = locales.where(
        (locale) => locale.localeId.toLowerCase().startsWith(deviceLanguage),
      );
      _localeId = matchingLocale.isNotEmpty
          ? matchingLocale.first.localeId
          : (locales.isNotEmpty ? locales.first.localeId : null);
      _startListening();
    } else {
      setState(() => _text = 'Speech recognition denied or not available.');
    }
  }

  void _startListening() {
    if (!_speechAvailable || _isProcessing || _isListening) return;
    setState(() {
      _isListening = true;
      _transcript = '';
      _text = 'Listening...';
    });
    _speech.listen(
      onResult: (val) {
        if (!mounted) return;
        final recognized = val.recognizedWords.trim();
        if (recognized.isNotEmpty) {
          _transcript = recognized;
        }
        setState(() {
          _text = _transcript.isEmpty ? 'Listening...' : _transcript;
        });
        if (val.finalResult && _transcript.isNotEmpty && !_isProcessing) {
          _scheduleProcessing();
        }
      },
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
        localeId: _localeId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
      ),
    );
  }

  void _scheduleProcessing() {
    if (_processingScheduled || _isProcessing) return;
    _processingScheduled = true;
    // Allow either the final onResult or the status callback to arrive first.
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      _processingScheduled = false;
      if (mounted && !_isProcessing && _transcript.trim().isNotEmpty) {
        _processAudio();
      }
    });
  }

  void _stopListening() {
    if (_isListening) {
      _speech.stop();
      if (mounted) setState(() => _isListening = false);
    }
  }

  Future<void> _processAudio() async {
    if (_isProcessing) return;
    final transcript = _transcript.trim();
    _stopListening();
    if (transcript.isEmpty) {
      if (mounted) {
        setState(
          () => _text = 'No speech detected. Tap the microphone and try again.',
        );
      }
      return;
    }

    setState(() {
      _isProcessing = true;
      _text = 'Processing with AI...';
    });

    try {
      final data = widget.isExpense
          ? await GeminiService.analyzeVoiceExpense(
              transcript,
              currencySymbol: ref.read(currencySymbolProvider),
            )
          : await GeminiService.analyzeVoiceInvoice(
              transcript,
              currencySymbol: ref.read(currencySymbolProvider),
            );

      if (!mounted) return;

      if (data != null) {
        Navigator.pop(context, data);
      } else {
        setState(() {
          _isProcessing = false;
          _text =
              'I could not find enough reliable information. Please try again.';
        });
      }
    } on AiServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _text = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _text = 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusLG),
          border: Border.all(color: AppTheme.glassBorder, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title, style: AppTheme.headlineMedium()),
            const SizedBox(height: 24),
            AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.emerald.withValues(
                      alpha: _isListening
                          ? 0.2 + (_animationController.value * 0.3)
                          : 0.1,
                    ),
                  ),
                  child: Center(
                    child: GestureDetector(
                      onTap: () {
                        if (_isProcessing) return;
                        if (_isListening) {
                          _processAudio();
                        } else {
                          _startListening();
                        }
                      },
                      child: Container(
                        width: 70,
                        height: 70,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.emerald,
                        ),
                        child: Icon(
                          _isListening
                              ? Icons.mic
                              : (_isProcessing
                                    ? Icons.hourglass_empty
                                    : Icons.mic_none),
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              _text,
              textAlign: TextAlign.center,
              style: AppTheme.bodyLarge(
                color: _isProcessing ? AppTheme.emerald : Colors.white70,
              ),
            ),
            const SizedBox(height: 16),
            if (!_isProcessing)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: AppTheme.bodyMedium(color: Colors.white54),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
