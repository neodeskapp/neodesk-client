import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Languages with a flag in assets/flags/<code>.svg (Twemoji, as the web
/// console's language menu). A language spoken without one country of its
/// own (Catalan, Esperanto, Basque, Sardinian) gets no flag rather than a
/// wrong one.
const Set<String> kBdLangFlags = {
  'ar', 'be', 'bg', 'cs', 'da', 'de', 'el', 'en', 'es', 'et', 'fa', 'fi', //
  'fr', 'ge', 'gu', 'he', 'hi', 'hr', 'hu', 'id', 'it', 'ja', 'ko', 'kz', //
  'lt', 'lv', 'ml', 'nb', 'nl', 'pl', 'pt', 'ro', 'ru', 'sk', 'sl', 'sq', //
  'sr', 'sv', 'ta', 'th', 'tr', 'uk', 'ur', 'vi', 'zh-cn', 'zh-tw',
};

/// The flag of a language code in a 20 px box. A code without a flag gets
/// the empty box, so names in a list stay aligned.
class BdLangFlag extends StatelessWidget {
  const BdLangFlag(this.code, {super.key, this.size = 20});

  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final key = code.toLowerCase();
    if (!kBdLangFlags.contains(key)) {
      return SizedBox(width: size, height: size);
    }
    return SvgPicture.asset(
      'assets/flags/$key.svg',
      width: size,
      height: size,
      excludeFromSemantics: true,
    );
  }
}
