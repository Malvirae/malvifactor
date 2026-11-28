import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:malvifactor/core/theme/app_theme.dart';

/// Tactile press wrapper with subtle 0.97 scale over 100ms + light haptic feedback.
/// Automatically respects [MediaQuery.disableAnimationsOf].
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.haptic = true,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;
  final BorderRadius? borderRadius;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    Widget content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: disabled ? null : (_) => _setPressed(true),
      onTapUp: disabled ? null : (_) => _setPressed(false),
      onTapCancel: disabled ? null : () => _setPressed(false),
      onTap: disabled
          ? null
          : () {
              if (widget.haptic) {
                HapticFeedback.selectionClick();
              }
              widget.onTap?.call();
            },
      child: AnimatedScale(
        scale: (!disableAnimations && _pressed) ? widget.scale : 1.0,
        duration: disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );

    if (widget.borderRadius != null) {
      content = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: content,
      );
    }
    return content;
  }
}

/// Smoothly animated linear progress bar respecting reduced motion settings.
class AnimatedMacroBar extends StatelessWidget {
  const AnimatedMacroBar({
    super.key,
    required this.value,
    required this.color,
    this.minHeight = 5,
    this.backgroundColor = AppColors.surfaceElevated,
  });

  final double value;
  final Color color;
  final double minHeight;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final clamped = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: clamped),
        duration: disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (_, animatedValue, __) => LinearProgressIndicator(
          value: animatedValue,
          minHeight: minHeight,
          backgroundColor: backgroundColor,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    );
  }
}

/// Soft pulsing dark skeleton placeholder used only on cold initial loads.
class SkeletonPulseBox extends StatefulWidget {
  const SkeletonPulseBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 14,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<SkeletonPulseBox> createState() => _SkeletonPulseBoxState();
}

class _SkeletonPulseBoxState extends State<SkeletonPulseBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (disableAnimations) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(color: AppColors.border),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_controller.value);
        final color = Color.lerp(
          AppColors.surface,
          AppColors.surfaceElevated,
          t,
        )!;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(color: AppColors.border),
          ),
        );
      },
    );
  }
}

/// Subtle one-time fade+slide entrance for Dashboard cards.
class SoftFadeIn extends StatefulWidget {
  const SoftFadeIn({
    super.key,
    required this.child,
    this.delayMs = 0,
  });

  final Widget child;
  final int delayMs;

  @override
  State<SoftFadeIn> createState() => _SoftFadeInState();
}

class _SoftFadeInState extends State<SoftFadeIn> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    if (widget.delayMs <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _visible = true);
      });
    } else {
      Future<void>.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return AnimatedOpacity(
      opacity: _visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.025),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
