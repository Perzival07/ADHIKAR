import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// A widget that continuously blinks / pulses to catch the user's attention.
class ContinuousBlinkingWidget extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double minOpacity;
  final double maxOpacity;
  final bool enableScale;

  const ContinuousBlinkingWidget({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 650),
    this.minOpacity = 0.25,
    this.maxOpacity = 1.0,
    this.enableScale = true,
  });

  @override
  State<ContinuousBlinkingWidget> createState() => _ContinuousBlinkingWidgetState();
}

class _ContinuousBlinkingWidgetState extends State<ContinuousBlinkingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat(reverse: true);

    _opacityAnim = Tween<double>(
      begin: widget.minOpacity,
      end: widget.maxOpacity,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _scaleAnim = Tween<double>(
      begin: widget.enableScale ? 0.94 : 1.0,
      end: widget.enableScale ? 1.06 : 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnim.value,
          child: Transform.scale(
            scale: _scaleAnim.value,
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// Continuous blinking icon with glowing badge for BottomNavigationBar
class ContinuousBlinkingNavIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isActive;

  const ContinuousBlinkingNavIcon({
    super.key,
    required this.icon,
    required this.color,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: 24, color: color),
        Positioned(
          top: -3,
          right: -7,
          child: ContinuousBlinkingWidget(
            minOpacity: 0.3,
            maxOpacity: 1.0,
            duration: const Duration(milliseconds: 600),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
              decoration: BoxDecoration(
                color: AppTheme.accentSaffron,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentSaffron.withValues(alpha: 0.8),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Text(
                'NEW',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 7.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
