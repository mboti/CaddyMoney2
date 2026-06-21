import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Adds a subtle frosted blur + fade at the top and bottom edges of a scrollable.
///
/// Intended to make the transition between a list and surrounding UI feel smoother,
/// without affecting scroll interactions.
class ScrollEdgeFadeBlur extends StatelessWidget {
  /// The scrollable widget to decorate (typically a ListView).
  final Widget child;

  /// How strong the blur is.
  final double blurSigma;

  /// Height (in logical pixels) of the top/bottom fade regions.
  final double fadeExtent;

  /// Background color used for the fade/tint.
  ///
  /// Usually `Theme.of(context).scaffoldBackgroundColor`.
  final Color backgroundColor;

  /// Opacity for the tinted area (0..1). Higher = more “eclipse/frosted” feeling.
  final double tintOpacity;

  const ScrollEdgeFadeBlur({
    super.key,
    required this.child,
    required this.backgroundColor,
    this.blurSigma = 10,
    this.fadeExtent = 32,
    this.tintOpacity = 0.90,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        _EdgeBlurOverlay(
          alignment: Alignment.topCenter,
          blurSigma: blurSigma,
          extent: fadeExtent,
          backgroundColor: backgroundColor,
          tintOpacity: tintOpacity,
        ),
        _EdgeBlurOverlay(
          alignment: Alignment.bottomCenter,
          blurSigma: blurSigma,
          extent: fadeExtent,
          backgroundColor: backgroundColor,
          tintOpacity: tintOpacity,
        ),
      ],
    );
  }
}

class _EdgeBlurOverlay extends StatelessWidget {
  final Alignment alignment;
  final double blurSigma;
  final double extent;
  final Color backgroundColor;
  final double tintOpacity;

  const _EdgeBlurOverlay({
    required this.alignment,
    required this.blurSigma,
    required this.extent,
    required this.backgroundColor,
    required this.tintOpacity,
  });

  bool get _isTop => alignment == Alignment.topCenter;

  @override
  Widget build(BuildContext context) {
    final opaque = backgroundColor.withValues(alpha: tintOpacity);
    final transparent = backgroundColor.withValues(alpha: 0.0);

    final gradient = LinearGradient(
      begin: _isTop ? Alignment.topCenter : Alignment.bottomCenter,
      end: _isTop ? Alignment.bottomCenter : Alignment.topCenter,
      colors: [opaque, transparent],
      stops: const [0.0, 1.0],
    );

    return Positioned(
      left: 0,
      right: 0,
      top: _isTop ? 0 : null,
      bottom: _isTop ? null : 0,
      height: extent,
      child: IgnorePointer(
        child: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
          ),
        ),
      ),
    );
  }
}
