// Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-Present Datadog, Inc.
import 'package:datadog_common_test/datadog_common_test.dart';
import 'package:datadog_session_replay/datadog_session_replay.dart';
import 'package:datadog_session_replay/src/capture/capture_node.dart';
import 'package:datadog_session_replay/src/capture/element_recorders/common_nodes.dart';
import 'package:datadog_session_replay/src/capture/element_recorders/container_recorder.dart';
import 'package:datadog_session_replay/src/capture/element_recorders/custom_paint_recorder.dart';
import 'package:datadog_session_replay/src/capture/recorder.dart';
import 'package:datadog_session_replay/src/rum_context.dart';
import 'package:datadog_session_replay/src/sr_data_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'simple_test_capture.dart';

class _FakeCustomPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

void main() {
  late SessionReplayRecorder recorder;
  late RUMContext context;

  setUp(() {
    recorder = SessionReplayRecorder.withCustomRecorders(
      [CustomPaintRecorder(KeyGenerator())],
      defaultCapturePrivacy: TreeCapturePrivacy(
        textAndInputPrivacyLevel: TextAndInputPrivacyLevel.maskSensitiveInputs,
        imagePrivacyLevel: ImagePrivacyLevel.maskNonAssetsOnly,
      ),
      touchPrivacyLevel: TouchPrivacyLevel.show,
    );

    registerFallbackValue(
      CapturedViewAttributes(paintBounds: Rect.zero, scaleX: 1.0, scaleY: 1.0),
    );

    context = RUMContext(
      applicationId: randomString(),
      sessionId: randomString(),
    );
    recorder.updateContext(context);
  });

  testWidgets('returns placeholder for custom paint', (tester) async {
    // Given
    final width = randomDouble(min: 10, max: 50);
    final height = randomDouble(min: 10, max: 50);
    final tree = SimpleTestCapture(
      key: Key('key'),
      recorder: recorder,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            SizedBox(
              width: width,
              height: height,
              child: CustomPaint(painter: _FakeCustomPainter()),
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(tree);

    // When
    final capture = await recorder.performCapture();

    // Then
    expect(capture, isNotNull);
    final treeCapture = capture!.viewTreeSnapshot;
    expect(treeCapture, isNotNull);
    expect(treeCapture.nodes.length, 1);
    final containerNode = treeCapture.nodes.first;
    expect(containerNode.attributes.x, 0);
    expect(containerNode.attributes.y, 0);
    expect(containerNode.attributes.width, width.round());
    expect(containerNode.attributes.height, height.round());

    final builtWireframes = containerNode.buildWireframes();
    expect(builtWireframes.length, 1);
    final shapeWireframe = builtWireframes.first as SRPlaceholderWireframe;
    expect(shapeWireframe.x, 0);
    expect(shapeWireframe.y, 0);
    expect(shapeWireframe.width, width.round());
    expect(shapeWireframe.height, height.round());
  });

  testWidgets('returns nothing for custom paint with only foreground painter', (
    tester,
  ) async {
    // Given
    final width = randomDouble(min: 10, max: 50);
    final height = randomDouble(min: 10, max: 50);
    final tree = SimpleTestCapture(
      key: Key('key'),
      recorder: recorder,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            SizedBox(
              width: width,
              height: height,
              child: CustomPaint(foregroundPainter: _FakeCustomPainter()),
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(tree);

    // When
    final capture = await recorder.performCapture();

    // Then
    expect(capture, isNull);
  });

  testWidgets('hide strategy emits no wireframe for custom paint alone', (
    tester,
  ) async {
    final keys = KeyGenerator();
    final hideRecorder = SessionReplayRecorder.withCustomRecorders(
      [
        CustomPaintRecorder(
          keys,
          customPaintConfig: const CustomPaintConfig(
            strategy: CustomPaintStrategy.hide,
          ),
        ),
      ],
      defaultCapturePrivacy: TreeCapturePrivacy(
        textAndInputPrivacyLevel: TextAndInputPrivacyLevel.maskSensitiveInputs,
        imagePrivacyLevel: ImagePrivacyLevel.maskNonAssetsOnly,
      ),
      touchPrivacyLevel: TouchPrivacyLevel.show,
    );
    hideRecorder.updateContext(context);

    final width = randomDouble(min: 10, max: 50);
    final height = randomDouble(min: 10, max: 50);
    await tester.pumpWidget(
      SimpleTestCapture(
        key: const Key('hide'),
        recorder: hideRecorder,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              SizedBox(
                width: width,
                height: height,
                child: CustomPaint(painter: _FakeCustomPainter()),
              ),
            ],
          ),
        ),
      ),
    );

    final capture = await hideRecorder.performCapture();
    expect(capture, isNull);
  });

  testWidgets('outlinedBox strategy emits shape wireframe with border', (
    tester,
  ) async {
    final keys = KeyGenerator();
    final outlineRecorder = SessionReplayRecorder.withCustomRecorders(
      [
        CustomPaintRecorder(
          keys,
          customPaintConfig: const CustomPaintConfig(
            strategy: CustomPaintStrategy.outlinedBox,
            borderColor: Color(0xFFFF0000),
            borderWidth: 3,
          ),
        ),
      ],
      defaultCapturePrivacy: TreeCapturePrivacy(
        textAndInputPrivacyLevel: TextAndInputPrivacyLevel.maskSensitiveInputs,
        imagePrivacyLevel: ImagePrivacyLevel.maskNonAssetsOnly,
      ),
      touchPrivacyLevel: TouchPrivacyLevel.show,
    );
    outlineRecorder.updateContext(context);

    final width = randomDouble(min: 10, max: 50);
    final height = randomDouble(min: 10, max: 50);
    await tester.pumpWidget(
      SimpleTestCapture(
        key: const Key('outline'),
        recorder: outlineRecorder,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              SizedBox(
                width: width,
                height: height,
                child: CustomPaint(painter: _FakeCustomPainter()),
              ),
            ],
          ),
        ),
      ),
    );

    final capture = await outlineRecorder.performCapture();
    expect(capture, isNotNull);
    final nodes = capture!.viewTreeSnapshot.nodes;
    expect(nodes.length, 1);

    final built = nodes.first.buildWireframes();
    expect(built.length, 1);
    final wf = built.first as SRShapeWireframe;
    expect(wf.shapeStyle?.backgroundColor, srTransparentColorString);
    expect(wf.border?.color, '#ff0000ff');
    expect(wf.border?.width, 3);
    expect(wf.width, width.round());
    expect(wf.height, height.round());
  });

  testWidgets('hide and outlinedBox still capture CustomPaint child ColoredBox', (
    tester,
  ) async {
    final width = randomDouble(min: 10, max: 50);
    final height = randomDouble(min: 10, max: 50);

    for (final strategy in [
      CustomPaintStrategy.hide,
      CustomPaintStrategy.outlinedBox,
    ]) {
      final keys = KeyGenerator();
      final r = SessionReplayRecorder.withCustomRecorders(
        [
          ContainerRecorder(keys),
          CustomPaintRecorder(
            keys,
            customPaintConfig: CustomPaintConfig(strategy: strategy),
          ),
        ],
        defaultCapturePrivacy: TreeCapturePrivacy(
          textAndInputPrivacyLevel: TextAndInputPrivacyLevel.maskSensitiveInputs,
          imagePrivacyLevel: ImagePrivacyLevel.maskNonAssetsOnly,
        ),
        touchPrivacyLevel: TouchPrivacyLevel.show,
      );
      r.updateContext(context);

      await tester.pumpWidget(
        SimpleTestCapture(
          key: Key('child-$strategy'),
          recorder: r,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              children: [
                SizedBox(
                  width: width,
                  height: height,
                  child: CustomPaint(
                    painter: _FakeCustomPainter(),
                    child: const ColoredBox(color: Color(0xFF112233)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final capture = await r.performCapture();
      expect(capture, isNotNull);
      final treeNodes = capture!.viewTreeSnapshot.nodes;
      final expectedCount =
          strategy == CustomPaintStrategy.hide ? 1 : 2;
      expect(treeNodes.length, expectedCount, reason: '$strategy');

      final hasColoredBox = treeNodes.any((n) {
        if (n is! ContainerNode) return false;
        final wfs = n.buildWireframes();
        if (wfs.length != 1 || wfs.first is! SRShapeWireframe) return false;
        final s = wfs.first as SRShapeWireframe;
        return s.shapeStyle?.backgroundColor == '#112233ff';
      });
      expect(hasColoredBox, isTrue, reason: '$strategy');

      if (strategy == CustomPaintStrategy.hide) {
        expect(treeNodes.single, isA<ContainerNode>());
        expect(
          treeNodes.every((n) {
            final wfs = n.buildWireframes();
            return wfs.every((w) => w is! SRPlaceholderWireframe);
          }),
          isTrue,
        );
      } else {
        expect(treeNodes.any((n) => n is CustomPaintOutlineNode), isTrue);
        expect(treeNodes.any((n) => n is ContainerNode), isTrue);
      }
    }
  });
}
