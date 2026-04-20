// Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-Present Datadog, Inc.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';
import 'package:datadog_flutter_plugin/datadog_internal.dart';
import 'package:flutter/widgets.dart';

import '../../../datadog_session_replay.dart';
import '../../datadog_session_replay_platform_interface.dart';
import '../../sr_data_models.dart';
import '../capture_node.dart';
import '../recorder.dart';
import '../view_tree_snapshot.dart';

// This size was chosen so that 'Content Image' would fit without
// overlapping other content in the replay.
const int _labelMinWidth = 125;

// Largest size of image we can process - larger than this and we
// start to hit concerns around memory usage and processing time.
// This is essentially an 800x800 image, with a raw size of 2meg
const int maxImageSize = 640000;

class ImageRecorder implements ElementRecorder {
  final KeyGenerator keyGenerator;
  final ImageDownscaling imageDownscaling;
  final InternalLogger? internalLogger;

  ImageRecorder(
    this.keyGenerator, {
    this.imageDownscaling = ImageDownscaling.disabled,
    this.internalLogger,
  });

  @override
  List<Type> get handlesTypes => [RawImage, Image];

  @override
  CaptureNodeSemantics? captureSemantics(
    Element element,
    CapturedViewAttributes attributes,
    TreeCapturePrivacy capturePrivacy,
  ) {
    final widget = element.widget;
    if (widget is Image &&
        capturePrivacy.imagePrivacyLevel ==
            ImagePrivacyLevel.maskNonAssetsOnly) {
      // Try to pull out an AssetImage from the image internals...
      final assetImage = _extractAssetImage(widget);

      if (assetImage != null) {
        // Loosen capturing for the tree under this asset
        return IgnoredElement(
          subtreeStrategy: CaptureNodeSubtreeStrategy.record,
          subtreePrivacy: TreeCapturePrivacy(
            textAndInputPrivacyLevel: capturePrivacy.textAndInputPrivacyLevel,
            imagePrivacyLevel: ImagePrivacyLevel.maskNone,
          ),
        );
      }
    }

    if (widget is! RawImage) return null;

    final uiImage = widget.image;
    if (uiImage == null) {
      // This image is likely still loading. We could put a placeholder here,
      // but we would then have to replace it later. Instead, we'll wait for
      // it to load before creating the capture node. We can, however,
      // ignore all children for the time being.
      return IgnoredElement(subtreeStrategy: CaptureNodeSubtreeStrategy.ignore);
    }

    final elementId = keyGenerator.keyForElement(element);
    // AssetImages loosen their masking to [ImagePrivacyLevel.maskNone] when
    // they need to, so if [ImagePrivacyLevel.maskNonAssetsOnly] is still set, then
    // we shouldn't capture this image.
    bool shouldCaptureImage =
        capturePrivacy.imagePrivacyLevel == ImagePrivacyLevel.maskNone;
    if (!shouldCaptureImage) {
      return SpecificElement(
        subtreeStrategy: CaptureNodeSubtreeStrategy.ignore,
        nodes: [
          PlaceholderNode(
            attributes,
            wireframeId: elementId,
            caption: 'Image',
            minWidth: _labelMinWidth,
          ),
        ],
      );
    }

    final totalPixelSize = uiImage.width * uiImage.height;
    if (totalPixelSize > maxImageSize &&
        imageDownscaling == ImageDownscaling.disabled) {
      return SpecificElement(
        subtreeStrategy: CaptureNodeSubtreeStrategy.ignore,
        nodes: [
          PlaceholderNode(
            attributes,
            wireframeId: elementId,
            caption: 'Large Image',
            minWidth: _labelMinWidth,
          ),
        ],
      );
    }

    final hasResourceKey = keyGenerator.hasImageKey(uiImage);
    if (hasResourceKey) {
      final resourceKey = keyGenerator.keyForImage(uiImage);
      return SpecificElement(
        subtreeStrategy: CaptureNodeSubtreeStrategy.ignore,
        nodes: [
          ResourceImageNode(
            attributes,
            wireframeId: elementId,
            resourceKey: resourceKey,
          ),
        ],
      );
    }

    return AdditionalProcessingElement(
      subtreeStrategy: CaptureNodeSubtreeStrategy.ignore,
      process: () => _captureImage(elementId, element, attributes, widget),
    );
  }

  Future<CaptureNodeSemantics> _captureImage(
    int elementId,
    Element element,
    CapturedViewAttributes attributes,
    RawImage widget,
  ) async {
    final List<CaptureNode> nodes = [];
    final image = widget.image;
    if (image == null) {
      return _emptyOrErrorImage(elementId, attributes);
    }

    final srcW = image.width;
    final srcH = image.height;
    final totalPixels = srcW * srcH;

    final (dstW, dstH) = _targetCaptureDimensions(
      srcW,
      srcH,
      attributes,
      element,
    );

    final needsRasterDownscale = imageDownscaling == ImageDownscaling.enabled &&
        (dstW != srcW || dstH != srcH);

    var encodingImage = image;
    ui.Image? scaledDisposable;

    if (needsRasterDownscale) {
      final stopwatch = Stopwatch()..start();
      final scaled = await _downscaleImage(image, dstW, dstH);
      stopwatch.stop();
      internalLogger?.log(
        CoreLoggerLevel.debug,
        'Session Replay image downscale: '
        '${srcW}x$srcH (${totalPixels}px) -> ${dstW}x$dstH '
        '(${dstW * dstH}px), '
        'viewBounds=${attributes.width.toStringAsFixed(1)}x'
        '${attributes.height.toStringAsFixed(1)}, '
        'oversized=${totalPixels > maxImageSize}, '
        'success=${scaled != null}, '
        'took ${stopwatch.elapsedMilliseconds}ms',
      );
      if (scaled != null) {
        encodingImage = scaled;
        if (!identical(scaled, image)) {
          scaledDisposable = scaled;
        }
      } else if (totalPixels > maxImageSize) {
        return _failedDownscalePlaceholder(elementId, attributes);
      }
    }

    if (identical(encodingImage, image) && totalPixels > maxImageSize) {
      return _failedDownscalePlaceholder(elementId, attributes);
    }

    try {
      // Prevent conversion of the image data to speed things up, we're going to
      // be hashing / compressing in the processor anyway
      final byteData = await encodingImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData != null) {
        final resourceKey = keyGenerator.keyForImage(image);
        await DatadogSessionReplayPlatform.instance.saveImageForProcessing(
          resourceKey,
          encodingImage.width,
          encodingImage.height,
          byteData,
        );
        nodes.add(
          ResourceImageNode(
            attributes,
            wireframeId: elementId,
            resourceKey: resourceKey,
          ),
        );
      }
    } finally {
      scaledDisposable?.dispose();
    }

    if (nodes.isEmpty) {
      return _emptyOrErrorImage(elementId, attributes);
    }

    return SpecificElement(
      subtreeStrategy: CaptureNodeSubtreeStrategy.ignore,
      nodes: nodes,
    );
  }

  static SpecificElement _failedDownscalePlaceholder(
    int elementId,
    CapturedViewAttributes attributes,
  ) {
    return SpecificElement(
      subtreeStrategy: CaptureNodeSubtreeStrategy.ignore,
      nodes: [
        PlaceholderNode(
          attributes,
          wireframeId: elementId,
          caption: 'Failed Downscale',
          minWidth: _labelMinWidth,
        ),
      ],
    );
  }

  static SpecificElement _emptyOrErrorImage(
    int elementId,
    CapturedViewAttributes attributes,
  ) {
    return SpecificElement(
      subtreeStrategy: CaptureNodeSubtreeStrategy.ignore,
      nodes: [
        PlaceholderNode(
          attributes,
          wireframeId: elementId,
          caption: 'Empty Image',
          minWidth: _labelMinWidth,
        ),
      ],
    );
  }

  /// Target width/height in physical pixels: fit inside on-screen bounds × DPR,
  /// then clamp total pixels to [maxImageSize].
  @visibleForTesting
  static (int, int) targetCaptureDimensionsForTest(
    int srcW,
    int srcH,
    CapturedViewAttributes attributes,
    double devicePixelRatio,
  ) =>
      _targetCaptureDimensionsForDpr(
        srcW,
        srcH,
        attributes,
        devicePixelRatio,
      );

  static (int, int) _targetCaptureDimensions(
    int srcW,
    int srcH,
    CapturedViewAttributes attributes,
    Element element,
  ) {
    final dpr = _devicePixelRatio(element);
    return _targetCaptureDimensionsForDpr(
      srcW,
      srcH,
      attributes,
      dpr,
    );
  }

  static (int, int) _targetCaptureDimensionsForDpr(
    int srcW,
    int srcH,
    CapturedViewAttributes attributes,
    double devicePixelRatio,
  ) {
    final renderedPhysW = math.max(1, (attributes.width * devicePixelRatio).ceil());
    final renderedPhysH = math.max(1, (attributes.height * devicePixelRatio).ceil());

    final scale1 = math.min(
      math.min(renderedPhysW / srcW, renderedPhysH / srcH),
      1.0,
    );
    var w = math.max(1, (srcW * scale1).round());
    var h = math.max(1, (srcH * scale1).round());

    final pixels = w * h;
    if (pixels > maxImageSize) {
      final scale2 = math.sqrt(maxImageSize / pixels);
      w = math.max(1, (w * scale2).floor());
      h = math.max(1, (h * scale2).floor());
    }
    return (w, h);
  }

  static double _devicePixelRatio(Element element) {
    final view = View.maybeOf(element);
    if (view != null) {
      return view.devicePixelRatio;
    }
    return WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
  }

  static Future<ui.Image?> _downscaleImage(
    ui.Image source,
    int dstW,
    int dstH,
  ) async {
    if (dstW < 1 || dstH < 1) {
      return null;
    }
    if (dstW == source.width && dstH == source.height) {
      return null;
    }
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, dstW.toDouble(), dstH.toDouble()),
      paint,
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(dstW, dstH);
    } catch (_) {
      return null;
    } finally {
      picture.dispose();
    }
  }

  AssetImage? _extractAssetImage(Image widget) {
    AssetImage? assetImage;
    if (widget.image is AssetImage) {
      assetImage = widget.image as AssetImage;
    } else if (widget.image is ResizeImage) {
      final resizeImage = widget.image as ResizeImage;
      if (resizeImage.imageProvider is AssetImage) {
        assetImage = resizeImage.imageProvider as AssetImage;
      }
    }
    return assetImage;
  }
}

@immutable
@visibleForTesting
class ResourceImageNode extends CaptureNode {
  final int wireframeId;
  final int resourceKey;

  const ResourceImageNode(
    super.attributes, {
    required this.wireframeId,
    required this.resourceKey,
  });

  @override
  List<SRWireframe> buildWireframes() {
    final resourceId = DatadogSessionReplayPlatform.instance.resourceIdForKey(
      resourceKey,
    );

    return [
      SRImageWireframe(
        id: wireframeId,
        x: attributes.x,
        y: attributes.y,
        width: attributes.width,
        height: attributes.height,
        resourceId: resourceId,
      ),
    ];
  }
}
