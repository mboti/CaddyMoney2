import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A quick "flash" orbit animation: a glowing star travels along a circular ring
/// starting at the bottom, does a fast clockwise lap, pauses, and repeats.
///
/// Designed to be layered on top of a circular ring via a Stack.
class RingFlashOrbit extends StatefulWidget {
  final double size;
  final double ringRadius;
  final Color color;

  /// Called when the flash finishes its lap (i.e., at the end of [flashDuration]).
  ///
  /// This is useful to synchronize other UI accents (e.g., a glow pulse on a
  /// nearby button) with the completion of the orbit.
  final VoidCallback? onLapComplete;

  /// The angle (in radians) where the flash starts/ends.
  ///
  /// Angle 0 is at 3 o'clock (to the right). Positive values move clockwise
  /// because screen coordinates have +y downward.
  final double startAngleRad;

  /// How long the flash takes to travel around the ring.
  final Duration flashDuration;

  /// How long the animation rests before repeating.
  final Duration pauseDuration;

  /// Visual size of the star.
  final double starSize;

  const RingFlashOrbit({
    super.key,
    required this.size,
    required this.ringRadius,
    required this.color,
    // ~20% slower than the original (520ms -> 650ms)
    this.flashDuration = const Duration(milliseconds: 650),
    this.pauseDuration = const Duration(seconds: 3),
    this.starSize = 14,
    this.startAngleRad = math.pi / 2,
    this.onLapComplete,
  });

  @override
  State<RingFlashOrbit> createState() => _RingFlashOrbitState();
}

class _RingFlashOrbitState extends State<RingFlashOrbit> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _angle;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.flashDuration);
    _controller.addStatusListener(_handleStatus);

    // Screen coordinates (y grows downward). With the standard (cos, sin) mapping,
    // increasing angle moves clockwise.
    // Start at [startAngleRad] and do a full clockwise lap back to start.
    _angle = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic)
        .drive(Tween<double>(begin: widget.startAngleRad, end: widget.startAngleRad + (2 * math.pi)));

    _opacity = _controller.drive(
      TweenSequence<double>([
        TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 18),
        TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 55),
        TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 27),
      ]),
    );

    _scale = _controller.drive(
      TweenSequence<double>([
        TweenSequenceItem(tween: Tween<double>(begin: 0.6, end: 1.0).chain(CurveTween(curve: Curves.easeOutBack)), weight: 35),
        TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.92).chain(CurveTween(curve: Curves.easeInOut)), weight: 65),
      ]),
    );

    _startLoop();
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    widget.onLapComplete?.call();
  }

  void _startLoop() {
    // Start immediately.
    _controller.forward(from: 0);
    _timer?.cancel();
    _timer = Timer.periodic(widget.flashDuration + widget.pauseDuration, (_) {
      if (!mounted) return;
      _controller.forward(from: 0);
    });
  }

  @override
  void didUpdateWidget(covariant RingFlashOrbit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flashDuration != widget.flashDuration) _controller.duration = widget.flashDuration;
    // If the start angle changes we need to rebuild the tween.
    if (oldWidget.startAngleRad != widget.startAngleRad) {
      _angle = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic)
          .drive(Tween<double>(begin: widget.startAngleRad, end: widget.startAngleRad + (2 * math.pi)));
    }
    if (oldWidget.flashDuration != widget.flashDuration || oldWidget.pauseDuration != widget.pauseDuration) _startLoop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.removeStatusListener(_handleStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.size,
      width: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final angle = _angle.value;
            final r = widget.ringRadius;
            final dx = math.cos(angle) * r;
            final dy = math.sin(angle) * r;

            final opacity = _opacity.value;
            if (opacity <= 0.001) return const SizedBox.shrink();

            return Center(
              child: Transform.translate(
                offset: Offset(dx, dy),
                child: Opacity(
                  opacity: opacity,
                  child: Transform.scale(
                    scale: _scale.value,
                    child: _GlowingStar(color: widget.color, size: widget.starSize),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GlowingStar extends StatelessWidget {
  final Color color;
  final double size;

  const _GlowingStar({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final core = color;
    final outer = Color.lerp(core, cs.onSurface, 0.10) ?? core;

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: outer.withValues(alpha: 0.40), blurRadius: 18, spreadRadius: 2),
          BoxShadow(color: core.withValues(alpha: 0.55), blurRadius: 10, spreadRadius: 1),
        ],
      ),
      child: Icon(Icons.star_rounded, size: size, color: core),
    );
  }
}
