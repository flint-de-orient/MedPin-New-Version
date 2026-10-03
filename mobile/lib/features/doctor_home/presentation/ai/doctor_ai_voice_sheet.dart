import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../../core/theme/doctor_tokens.dart';
import '../../../../shared/providers/locale_provider.dart';

/// The listening sheet, from the canvas's Doctor-AI-Voice artboard.
///
/// Returns what was heard, or null if the doctor cancelled — or if the phone
/// has no speech recognition, which it says rather than sitting there with a
/// waveform that never moves.
Future<String?> askByVoice(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    barrierColor: D.scrim,
    backgroundColor: D.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(D.s6)),
    ),
    builder: (_) => const _VoiceSheet(),
  );
}

/// What the recogniser is called for each of the app's languages.
const _recogniserLocales = {'en': 'en_IN', 'bn': 'bn_IN', 'hi': 'hi_IN'};
const _spokenAs = {'en': 'English (India)', 'bn': 'বাংলা (ভারত)', 'hi': 'हिन्दी (भारत)'};

class _VoiceSheet extends ConsumerStatefulWidget {
  const _VoiceSheet();

  @override
  ConsumerState<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends ConsumerState<_VoiceSheet> with SingleTickerProviderStateMixin {
  final SpeechToText _speech = SpeechToText();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  String _heard = '';
  bool _listening = false;

  /// Said once, when the phone cannot listen at all — no recogniser, or the
  /// microphone refused.
  String? _unavailable;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _pulse.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _start() async {
    final language = ref.read(localeControllerProvider)?.languageCode ?? 'en';
    try {
      final ready = await _speech.initialize(
        onError: (e) => setState(() => _unavailable = 'The microphone could not be used.'),
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') setState(() => _listening = false);
        },
      );
      if (!ready) {
        setState(() => _unavailable = 'This phone has no speech recognition set up.');
        return;
      }
      setState(() => _listening = true);
      await _speech.listen(
        localeId: _recogniserLocales[language] ?? 'en_IN',
        listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true),
        onResult: (r) => setState(() => _heard = r.recognizedWords),
      );
    } catch (_) {
      setState(() => _unavailable = 'The microphone could not be used.');
    }
  }

  void _stopAndAsk() {
    _speech.stop();
    final said = _heard.trim();
    Navigator.of(context).pop(said.isEmpty ? null : said);
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(localeControllerProvider)?.languageCode ?? 'en';

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(D.s5, D.s3, D.s5, D.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: D.s8 + D.s1,
              height: D.s1,
              decoration: const BoxDecoration(color: D.line, borderRadius: D.rPill),
            ),
            SizedBox(height: D.s6),
            Text(
              _unavailable != null ? 'Cannot listen' : (_listening ? 'Listening…' : 'Ready'),
              style: D.screenTitle.copyWith(color: D.ink),
            ),
            SizedBox(height: D.gapTight),
            Text(
              _unavailable ?? 'Speak naturally. Say what you need about the patient you chose.',
              textAlign: TextAlign.center,
              style: D.body.copyWith(color: D.inkMuted),
            ),
            SizedBox(height: D.s6),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 84),
              padding: EdgeInsets.all(D.s4),
              decoration: BoxDecoration(
                color: D.ground,
                borderRadius: BorderRadius.circular(D.rCard),
              ),
              child: Text(
                _heard.isEmpty ? 'Nothing heard yet' : _heard,
                style: D.cardTitle.copyWith(
                  color: _heard.isEmpty ? D.inkFaint : D.ink,
                  fontWeight: FontWeight.w400,
                  height: 1.5,
                ),
              ),
            ),
            SizedBox(height: D.s6),
            _Waveform(pulse: _pulse, live: _listening),
            SizedBox(height: D.s6),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () {
                        _speech.cancel();
                        Navigator.of(context).pop();
                      },
                      child: Text('Cancel', style: D.dateLine.copyWith(color: D.inkMuted)),
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Stop and ask',
                  child: InkWell(
                    onTap: _stopAndAsk,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: D.brand,
                        shape: BoxShape.circle,
                        boxShadow: [
                          const BoxShadow(color: D.brandTint, blurRadius: 0, spreadRadius: D.s2),
                          ...D.liftBrand,
                        ],
                      ),
                      child: const Icon(Icons.stop_rounded, size: D.iconDisc, color: D.onBrand),
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        _speech.cancel();
                        Navigator.of(context).pop();
                      },
                      child: Text('Type instead', style: D.dateLine.copyWith(color: D.brand)),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: D.s4),
            Text(
              _spokenAs[language] ?? 'English (India)',
              style: D.statLabel.copyWith(color: D.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

/// The design's bars. They move while the phone is listening and sit still
/// when it is not — a waveform that dances at silence is a lie about whether
/// anything is being heard.
class _Waveform extends StatelessWidget {
  const _Waveform({required this.pulse, required this.live});

  final Animation<double> pulse;
  final bool live;

  static const _heights = [8.0, 14, 22, 30, 18, 40, 52, 34, 46, 56, 42, 50, 30, 38, 24, 44, 28, 18, 12, 8, 6];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: D.discLg + D.s1,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _heights.length; i++) ...[
                if (i > 0) SizedBox(width: D.s1 + 1),
                Container(
                  width: D.s1,
                  height: live
                      ? _heights[i] * (0.6 + 0.4 * ((pulse.value + i / _heights.length) % 1))
                      : _heights[i] * 0.5,
                  decoration: BoxDecoration(
                    color: live ? D.brand : D.line,
                    borderRadius: BorderRadius.circular(D.s1),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
