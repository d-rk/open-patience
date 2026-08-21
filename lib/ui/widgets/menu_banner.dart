import 'package:flutter/material.dart';

/// The main-menu hero banner: a static Blender-rendered art asset with a
/// subtle, looping vertical float. The motion is disabled when the platform
/// requests reduced motion — that also keeps widget tests free of pending
/// animation timers.
class MenuBanner extends StatefulWidget {
  const MenuBanner({this.height = 168, super.key});

  final double height;

  @override
  State<MenuBanner> createState() => _MenuBannerState();
}

class _MenuBannerState extends State<MenuBanner>
    with SingleTickerProviderStateMixin {
  static const AssetImage _art = AssetImage('assets/images/menu_banner.png');

  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _controller?.dispose();
      _controller = null;
      return;
    }
    _controller ??= AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Widget image = Image(image: _art, fit: BoxFit.contain);
    final AnimationController? controller = _controller;
    if (controller == null) {
      return SizedBox(height: widget.height, child: image);
    }
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, Widget? child) {
          final double dy = (controller.value - 0.5) * 8; // ±4px float
          return Transform.translate(offset: Offset(0, dy), child: child);
        },
        child: image,
      ),
    );
  }
}
