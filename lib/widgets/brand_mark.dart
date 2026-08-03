import 'package:flutter/material.dart';

import '../theme/haul_theme.dart';

/// The Brothers Hauling lockup: the boxed **BH** monogram over the stacked
/// wordmark, in the same colours and arrangement as the app icon.
///
/// Drawn in type rather than shipped as an image, so it stays crisp at any
/// size, scales with the reader's text setting, and adds nothing to the web
/// payload. The whole thing reads to a screen reader as the two words it is,
/// not as five separate fragments.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.scale = 1});

  /// Multiplies the whole lockup. 1 is the role-gate size.
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: 'Brothers Hauling',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Monogram(scale: scale),
          SizedBox(height: 14 * scale),
          _Wordmark(scale: scale),
        ],
      ),
    );
  }
}

/// "BH" inside an orange rule — the B in grey, the H in the brand orange.
class _Monogram extends StatelessWidget {
  const _Monogram({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final size = 62.0 * scale;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 14 * scale,
        vertical: 9 * scale,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: hc.brand, width: 3 * scale),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'B',
              style: TextStyle(color: hc.inkSoft),
            ),
            TextSpan(
              text: 'H',
              style: TextStyle(color: hc.brand),
            ),
          ],
        ),
        // The monogram is a logo, not prose: it holds its proportions instead
        // of growing with the reader's text setting, which would burst the box.
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontFamily: HaulFonts.black,
          fontSize: size,
          height: 1,
          letterSpacing: -2 * scale,
        ),
      ),
    );
  }
}

/// BROTHERS over HAULING, grey over orange, as on the icon.
class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final style = TextStyle(
      fontFamily: HaulFonts.black,
      fontSize: 27 * scale,
      height: 1.06,
      letterSpacing: 1.5 * scale,
    );

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'BROTHERS\n',
            style: style.copyWith(color: hc.ink),
          ),
          TextSpan(
            text: 'HAULING',
            style: style.copyWith(color: hc.brand),
          ),
        ],
      ),
      textScaler: TextScaler.noScaling,
    );
  }
}
