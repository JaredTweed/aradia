import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:we_slide/we_slide.dart';

/// Gives the expanded player priority over the route underneath it.
class PlayerBackScope extends StatelessWidget {
  const PlayerBackScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WeSlideController>();
    return PopScope(
      canPop: !controller.isOpened,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && controller.isOpened) controller.hide();
      },
      child: child,
    );
  }
}
