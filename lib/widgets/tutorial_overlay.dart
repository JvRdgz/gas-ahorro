import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Tutorial overlay that highlights UI elements.
class TutorialOverlay extends StatelessWidget {
  const TutorialOverlay({
    super.key,
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.targetRect,
    required this.onSkip,
    required this.onNext,
  });

  final TutorialStep step;
  final int stepIndex;
  final int totalSteps;
  final Rect? targetRect;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final safe = media.padding;
    final screenHeight = media.size.height;
    final screenWidth = media.size.width;
    final hasTarget = targetRect != null;
    final hole =
        (targetRect ?? Rect.fromLTWH(0, screenHeight * 0.5, 0, 0)).inflate(12);
    final alignLeft = !hasTarget || hole.center.dx < screenWidth * 0.5;
    final cardWidth = math.min(screenWidth - 32, 320.0);
    final preferBelow = !hasTarget || hole.center.dy < screenHeight * 0.6;
    const maxCardHeight = 210.0;
    final minTop = safe.top + 16;
    final maxTop = screenHeight - safe.bottom - maxCardHeight - 16;
    final minBottom = safe.bottom + 16;
    final maxBottom = screenHeight - safe.top - maxCardHeight - 16;
    double? top;
    double? bottom;
    if (preferBelow) {
      final proposed = (hasTarget ? hole.bottom : screenHeight * 0.28) + 16;
      top = math.min(maxTop, math.max(minTop, proposed));
    } else {
      final proposed =
          (screenHeight - (hasTarget ? hole.top : screenHeight * 0.5)) + 16;
      bottom = math.min(maxBottom, math.max(minBottom, proposed));
    }

    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: SizedBox.expand(
              child: ClipPath(
                clipper: _TutorialScrimClipper(holeRect: hole),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: safe.top + 4,
            right: 16,
            child: FilledButton(
              onPressed: onSkip,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Saltar',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Positioned(
            left: alignLeft ? 16 : null,
            right: alignLeft ? null : 16,
            width: cardWidth,
            top: top,
            bottom: bottom,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      step.description,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          '${stepIndex + 1} / $totalSteps',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: onNext,
                          child: Text(
                            stepIndex == totalSteps - 1
                                ? 'Empezar'
                                : 'Siguiente',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One step of the tutorial walkthrough.
class TutorialStep {
  const TutorialStep({
    required this.title,
    required this.description,
    required this.targetKey,
  });

  final String title;
  final String description;
  final GlobalKey targetKey;
}

class _TutorialScrimClipper extends CustomClipper<Path> {
  _TutorialScrimClipper({required this.holeRect});

  final Rect holeRect;

  @override
  Path getClip(Size size) {
    final rect = Offset.zero & size;
    final path = Path()..addRect(rect);
    path.addRRect(
      RRect.fromRectAndRadius(holeRect, const Radius.circular(16)),
    );
    path.fillType = PathFillType.evenOdd;
    return path;
  }

  @override
  bool shouldReclip(covariant _TutorialScrimClipper oldDelegate) {
    return oldDelegate.holeRect != holeRect;
  }
}
