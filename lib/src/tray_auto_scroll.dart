import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Caps an auto page at [maxHeight] and scrolls its content past that height.
///
/// Content that fits keeps its own height, so the tray sizes to it. Taller
/// content stops at [maxHeight] and scrolls inside the tray.
///
/// A page that brings its own vertical scroll view, or uses flex children
/// such as `Expanded` or `Spacer`, needs a bounded height to lay out. It gets
/// [maxHeight] as before and owns its scrolling, so no scroll view is nested
/// inside another.
class TrayAutoScroll extends StatelessWidget {
  const TrayAutoScroll({
    super.key,
    required this.maxHeight,
    required this.child,
  });

  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        // The route's PrimaryScrollController belongs to the page's own scroll
        // view, if it has one.
        primary: false,
        child: _TrayScrollBody(maxHeight: maxHeight, child: child),
      ),
    );
  }
}

class _TrayScrollBody extends SingleChildRenderObjectWidget {
  const _TrayScrollBody({required this.maxHeight, super.child});

  final double maxHeight;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderTrayScrollBody(maxHeight);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTrayScrollBody renderObject,
  ) {
    renderObject.maxHeight = maxHeight;
  }
}

/// Lays the page out at its natural height so the scroll view can scroll it,
/// unless the page needs a bounded height, in which case it gets the cap.
class _RenderTrayScrollBody extends RenderProxyBox {
  _RenderTrayScrollBody(this._maxHeight);

  double _maxHeight;

  set maxHeight(double value) {
    if (value == _maxHeight) return;
    _maxHeight = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    final childConstraints = _needsBoundedHeight(child)
        ? constraints.copyWith(
            maxHeight: math.min(constraints.maxHeight, _maxHeight),
          )
        : constraints;
    child.layout(childConstraints, parentUsesSize: true);
    size = constraints.constrain(child.size);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return constraints.constrain(child.getDryLayout(constraints));
  }

  /// Whether the page holds something that cannot lay out with an unbounded
  /// height: a scroll viewport, or a vertical flex with flexible children.
  /// Subtrees under a fixed or capped height are skipped, since they are
  /// already bounded there.
  static bool _needsBoundedHeight(RenderObject root) {
    var found = false;
    void visit(RenderObject node) {
      if (found) return;
      if (node is RenderViewport || node is RenderListWheelViewport) {
        found = true;
        return;
      }
      if (node is RenderConstrainedBox &&
          node.additionalConstraints.hasBoundedHeight) {
        return;
      }
      if (node is RenderLimitedBox && node.maxHeight.isFinite) return;
      if (node is RenderFlex &&
          node.direction == Axis.vertical &&
          _hasFlexibleChild(node)) {
        found = true;
        return;
      }
      node.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  static bool _hasFlexibleChild(RenderFlex flex) {
    var child = flex.firstChild;
    while (child != null) {
      final parentData = child.parentData! as FlexParentData;
      if ((parentData.flex ?? 0) > 0) return true;
      child = parentData.nextSibling;
    }
    return false;
  }
}
