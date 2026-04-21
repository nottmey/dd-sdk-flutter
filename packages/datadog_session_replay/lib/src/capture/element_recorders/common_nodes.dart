// Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-Present Datadog, Inc.

import 'package:flutter/material.dart';

import '../../extensions.dart';
import '../../sr_data_models.dart';
import '../capture_node.dart';

/// Stop-weighted average of [gradient] colors for Session Replay, which has no
/// gradient field on wireframes.
Color? dominantColorFromGradient(Gradient gradient) {
  final colors = gradient.colors;
  if (colors.isEmpty) return null;
  if (colors.length == 1) return colors.first;

  final rawStops = gradient.stops;
  final stops = rawStops ??
      List<double>.generate(
        colors.length,
        (i) => i / (colors.length - 1),
      );

  if (stops.length != colors.length) {
    return colors.first;
  }

  var sumA = 0.0;
  var sumR = 0.0;
  var sumG = 0.0;
  var sumB = 0.0;
  var sumW = 0.0;
  for (var i = 0; i < colors.length; i++) {
    final prev = i == 0 ? 0.0 : (stops[i - 1] + stops[i]) / 2;
    final next = i == colors.length - 1 ? 1.0 : (stops[i] + stops[i + 1]) / 2;
    final w = (next - prev).clamp(0.0, 1.0);
    final c = colors[i];
    sumA += c.a * w;
    sumR += c.r * w;
    sumG += c.g * w;
    sumB += c.b * w;
    sumW += w;
  }
  if (sumW == 0) return colors.first;
  return Color.from(
    alpha: (sumA / sumW).clamp(0.0, 1.0),
    red: (sumR / sumW).clamp(0.0, 1.0),
    green: (sumG / sumW).clamp(0.0, 1.0),
    blue: (sumB / sumW).clamp(0.0, 1.0),
  );
}

@immutable
class CapturedShadow {
  /// Hex RGBA after alpha softening for replay (no blur in wireframe schema).
  final String color;
  final double offsetX;
  final double offsetY;

  /// Logical pixels to outset the shadow rect (`spreadRadius + blurRadius * 0.5`).
  final double spread;

  const CapturedShadow({
    required this.color,
    required this.offsetX,
    required this.offsetY,
    required this.spread,
  });
}

List<CapturedShadow> _capturedShadowsFrom(List<BoxShadow>? shadows) {
  if (shadows == null || shadows.isEmpty) return const [];
  final out = <CapturedShadow>[];
  for (final s in shadows) {
    final softened = s.color.withValues(
      alpha: (s.color.a * 0.5).clamp(0.0, 1.0),
    );
    if (softened.a <= 0) continue;
    final spreadExtra = s.spreadRadius + s.blurRadius * 0.5;
    out.add(
      CapturedShadow(
        color: softened.toHexString(),
        offsetX: s.offset.dx,
        offsetY: s.offset.dy,
        spread: spreadExtra,
      ),
    );
  }
  return out;
}

@immutable
class CapturedBorderStyle {
  final double? cornerRadius;
  final double? width;
  final String? color;

  const CapturedBorderStyle({
    required this.cornerRadius,
    required this.width,
    required this.color,
  });

  static CapturedBorderStyle? fromShapeBorder(
    ShapeBorder? shape,
    CapturedViewAttributes attributes,
  ) {
    switch (shape) {
      case final StadiumBorder _:
        final shortSide = attributes.paintBounds.shortestSide;
        return CapturedBorderStyle(
          cornerRadius: shortSide / 2,
          width: shape.side.width,
          color: shape.side.color.toHexString(),
        );
      case final CircleBorder _:
        final shortSide = attributes.paintBounds.shortestSide;
        return CapturedBorderStyle(
          cornerRadius: shortSide / 2,
          width: shape.side.width,
          color: shape.side.color.toHexString(),
        );
      case final RoundedRectangleBorder shape:
        // Text direction only matters for border radius if we support
        // per-side borders and per-corner border radius.
        return CapturedBorderStyle(
          cornerRadius: shape.borderRadius.resolve(null).topLeft.x,
          width: shape.side.width,
          color: shape.side.color.toHexString(),
        );
      case final UnderlineInputBorder shape:
        // TODO: Allow per-side borders
        return CapturedBorderStyle(
          cornerRadius: shape.borderRadius.resolve(null).topLeft.x,
          width: shape.borderSide.width,
          color: shape.borderSide.color.toHexString(),
        );
      case final OutlineInputBorder shape:
        // Text direction only matters for border radius if we support
        // per-side borders and per-corner border radius.
        return CapturedBorderStyle(
          cornerRadius: shape.borderRadius.resolve(null).topLeft.x,
          width: shape.borderSide.width,
          color: shape.borderSide.color.toHexString(),
        );
    }
    return null;
  }
}

@immutable
class ContainerStyle {
  final String? backgroundColor;
  final String? borderColor;
  final double? borderWidth;
  final double cornerRadius;
  final List<CapturedShadow> shadows;

  const ContainerStyle({
    required this.backgroundColor,
    this.borderColor,
    this.borderWidth,
    this.cornerRadius = 0.0,
    this.shadows = const [],
  });

  static ContainerStyle? fromDecoration(
    Decoration decoration,
    CapturedViewAttributes attributes,
  ) {
    switch (decoration) {
      case BoxDecoration boxDecoration:
        return _captureBoxDecoration(boxDecoration, attributes);
      case ShapeDecoration shapeDecoration:
        return _captureShapeDecoration(shapeDecoration, attributes);
    }
    return null;
  }

  static ContainerStyle? fromInputDecoration(
    InputDecoration decoration,
    bool isFocused,
    CapturedViewAttributes attributes,
  ) {
    bool hasError = decoration.errorText != null || decoration.error != null;
    InputBorder? border;
    if (!decoration.enabled) {
      border = hasError ? decoration.errorBorder : decoration.disabledBorder;
    } else if (isFocused) {
      border =
          hasError ? decoration.focusedErrorBorder : decoration.focusedBorder;
    } else {
      border = hasError ? decoration.errorBorder : decoration.enabledBorder;
    }
    border ??= decoration.border;
    border ??= _getDefaultInputBorder();

    final capturedBorder = CapturedBorderStyle.fromShapeBorder(
      border,
      attributes,
    );
    return ContainerStyle(
      backgroundColor: decoration.fillColor?.toHexString(),
      borderColor: capturedBorder?.color,
      cornerRadius: capturedBorder?.cornerRadius ?? 0,
      borderWidth: capturedBorder?.width,
    );
  }
}

InputBorder _getDefaultInputBorder() {
  // TODO: Query material state. See input_border.dart:2181
  return const UnderlineInputBorder();
}

ContainerStyle _captureBoxDecoration(
    BoxDecoration decoration, CapturedViewAttributes attributes) {
  double? cornerRadius = decoration.borderRadius?.resolve(null).topLeft.x;
  if (decoration.shape == BoxShape.circle) {
    // Show this as a circle even if it has border radius
    final shortSide = attributes.paintBounds.shortestSide;
    cornerRadius = shortSide / 2;
  }
  Color? backgroundColor = decoration.color;
  if (backgroundColor == null && decoration.gradient != null) {
    backgroundColor = dominantColorFromGradient(decoration.gradient!);
  }
  double? borderWidth;
  Color? borderColor;
  if (decoration.border case final border?) {
    // TODO: Look into non-uniform borders for SR
    if (border.top.width > 0) {
      borderWidth = border.top.width;
      borderColor = border.top.color;
    } else if (border.bottom.width > 0) {
      borderWidth = border.bottom.width;
      borderColor = border.bottom.color;
    }
  }

  return ContainerStyle(
    backgroundColor: backgroundColor?.toHexString(),
    borderColor: borderColor?.toHexString(),
    borderWidth: borderWidth,
    cornerRadius: cornerRadius ?? 0.0,
    shadows: _capturedShadowsFrom(decoration.boxShadow),
  );
}

ContainerStyle _captureShapeDecoration(
  ShapeDecoration decoration,
  CapturedViewAttributes attributes,
) {
  final borderStyle = CapturedBorderStyle.fromShapeBorder(
    decoration.shape,
    attributes,
  );
  Color? backgroundColor = decoration.color;
  if (backgroundColor == null && decoration.gradient != null) {
    backgroundColor = dominantColorFromGradient(decoration.gradient!);
  }
  return ContainerStyle(
    backgroundColor: backgroundColor?.toHexString(),
    borderColor: borderStyle?.color,
    borderWidth: borderStyle?.width,
    cornerRadius: borderStyle?.cornerRadius ?? 0.0,
    shadows: _capturedShadowsFrom(decoration.shadows),
  );
}

@immutable
class ContainerNode extends CaptureNode {
  final int wireframeId;
  final ContainerStyle style;

  /// One id per entry in [ContainerStyle.shadows], from [KeyGenerator.keysForAuxiliary].
  final List<int> shadowWireframeIds;

  const ContainerNode(
    super.attributes, {
    required this.wireframeId,
    required this.style,
    this.shadowWireframeIds = const [],
  });

  @override
  List<SRWireframe> buildWireframes() {
    assert(
      shadowWireframeIds.length == style.shadows.length,
      'shadowWireframeIds (${shadowWireframeIds.length}) must match '
      'style.shadows (${style.shadows.length})',
    );

    final attrs = attributes;
    final wireframes = <SRWireframe>[];

    for (var i = 0; i < style.shadows.length; i++) {
      final s = style.shadows[i];
      final spreadPx = s.spread.round();
      wireframes.add(
        SRShapeWireframe(
          id: shadowWireframeIds[i],
          x: attrs.x + s.offsetX.round() - spreadPx,
          y: attrs.y + s.offsetY.round() - spreadPx,
          width: attrs.width + 2 * spreadPx,
          height: attrs.height + 2 * spreadPx,
          shapeStyle: SRShapeStyle(
            backgroundColor: s.color,
            cornerRadius: style.cornerRadius,
          ),
        ),
      );
    }

    SRShapeStyle? shapeStyle;
    SRShapeBorder? shapeBorder;
    if (style.backgroundColor != null || style.borderWidth != null) {
      shapeStyle = SRShapeStyle(
        backgroundColor: style.backgroundColor ?? srTransparentColorString,
        cornerRadius: style.cornerRadius,
      );

      if (style.borderWidth != null) {
        shapeBorder = SRShapeBorder(
          color: style.borderColor!,
          width: style.borderWidth!.round(),
        );
      }
    }
    wireframes.add(
      SRShapeWireframe(
        id: wireframeId,
        x: attrs.x,
        y: attrs.y,
        width: attrs.width,
        height: attrs.height,
        shapeStyle: shapeStyle,
        border: shapeBorder,
      ),
    );
    return wireframes;
  }
}

@immutable
class TextElementCaptureNode extends CaptureNode {
  final int wireframeId;
  final String text;
  final String color;
  final String family;
  final int size;
  final SRHorizontalAlignment alignment;

  const TextElementCaptureNode(
    super.attributes, {
    required this.wireframeId,
    required this.text,
    required this.color,
    required this.family,
    required this.size,
    required this.alignment,
  });

  @override
  List<SRWireframe> buildWireframes() {
    return [
      SRTextWireframe(
        id: wireframeId,
        x: attributes.x,
        y: attributes.y,
        width: attributes.width,
        height: attributes.height,
        text: text,
        textStyle: SRTextStyle(color: color, family: family, size: size),
        textPosition: SRTextPosition(
          alignment: SRAlignment(horizontal: alignment),
        ),
      ),
    ];
  }
}
