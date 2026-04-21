// Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-Present Datadog, Inc.

import 'package:flutter/widgets.dart';

import '../../../datadog_session_replay.dart';
import '../../extensions.dart';
import '../../sr_data_models.dart';
import '../capture_node.dart';
import '../recorder.dart';
import '../view_tree_snapshot.dart';

/// Detects `CustomPaint` widgets and represents them in Session Replay according
/// to [CustomPaintConfig].
@immutable
class CustomPaintRecorder implements ElementRecorder {
  final KeyGenerator keyGenerator;
  final CustomPaintConfig customPaintConfig;

  const CustomPaintRecorder(
    this.keyGenerator, {
    this.customPaintConfig = const CustomPaintConfig(),
  });

  @override
  List<Type> get handlesTypes => [CustomPaint];

  @override
  CaptureNodeSemantics? captureSemantics(
    Element element,
    CapturedViewAttributes attributes,
    TreeCapturePrivacy capturePrivacy,
  ) {
    final widget = element.widget;
    if (widget is! CustomPaint) return null;

    // If there's only a foreground painter, this is a decoration
    // overlay that shouldn't be captured as a placeholder.
    if (widget.painter == null) return null;

    switch (customPaintConfig.strategy) {
      case CustomPaintStrategy.hide:
        return null;
      case CustomPaintStrategy.placeholder:
        final elementId = keyGenerator.keyForElement(element);
        return AmbiguousElement(
          subtreeStrategy: CaptureNodeSubtreeStrategy.record,
          nodes: [CustomPaintNode(attributes, wireframeId: elementId)],
        );
      case CustomPaintStrategy.outlinedBox:
        final elementId = keyGenerator.keyForElement(element);
        return AmbiguousElement(
          subtreeStrategy: CaptureNodeSubtreeStrategy.record,
          nodes: [
            CustomPaintOutlineNode(
              attributes,
              wireframeId: elementId,
              borderColorHex: customPaintConfig.borderColor.toHexString(),
              borderWidthPx: customPaintConfig.borderWidth.round(),
            ),
          ],
        );
    }
  }
}

@immutable
class CustomPaintNode extends CaptureNode {
  final int wireframeId;

  const CustomPaintNode(super.attributes, {required this.wireframeId});

  @override
  List<SRWireframe> buildWireframes() {
    return [
      SRPlaceholderWireframe(
        id: wireframeId,
        x: attributes.x,
        y: attributes.y,
        width: attributes.width,
        height: attributes.height,
      ),
    ];
  }
}

@immutable
class CustomPaintOutlineNode extends CaptureNode {
  final int wireframeId;
  final String borderColorHex;
  final int borderWidthPx;

  const CustomPaintOutlineNode(
    super.attributes, {
    required this.wireframeId,
    required this.borderColorHex,
    required this.borderWidthPx,
  });

  @override
  List<SRWireframe> buildWireframes() {
    final w = borderWidthPx <= 0 ? 1 : borderWidthPx;
    return [
      SRShapeWireframe(
        id: wireframeId,
        x: attributes.x,
        y: attributes.y,
        width: attributes.width,
        height: attributes.height,
        shapeStyle: SRShapeStyle(
          backgroundColor: srTransparentColorString,
        ),
        border: SRShapeBorder(
          color: borderColorHex,
          width: w,
        ),
      ),
    ];
  }
}
