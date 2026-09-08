import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_animations.dart';

/// TempoDeck design system staggered list item.
///
/// Wraps a child widget with a slide-up + fade-in entrance animation.
/// Each item delays its start by [index] × [AppAnimations.staggerOffset]
/// to create a cascading reveal effect.
///
/// Usage:
/// ```dart
/// ListView.builder(
///   itemBuilder: (context, index) => TDStaggeredListItem(
///     index: index,
///     child: TDListTile(...),
///   ),
/// )
/// ```
class TDStaggeredListItem extends StatefulWidget {
  const TDStaggeredListItem({
    required this.child,
    required this.index,
    super.key,
  });

  final Widget child;

  /// Position in the list. Controls the stagger delay before the
  /// animation begins ([index] × [AppAnimations.staggerOffset]).
  final int index;

  @override
  State<TDStaggeredListItem> createState() => _TDStaggeredListItemState();
}

class _TDStaggeredListItemState extends State<TDStaggeredListItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: AppAnimations.normal,
      vsync: this,
    );

    final curvedAnimation = CurvedAnimation(
      parent: _controller,
      curve: AppAnimations.enter,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(curvedAnimation);

    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(curvedAnimation);

    unawaited(_startWithDelay());
  }

  Future<void> _startWithDelay() async {
    final delay = AppAnimations.staggerOffset * widget.index;
    await Future<void>.delayed(delay);
    if (mounted) {
      await _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: widget.child,
      ),
    );
  }
}
