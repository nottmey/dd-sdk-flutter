// Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-Present Datadog, Inc.

import 'package:datadog_common_test/datadog_common_test.dart';
import 'package:datadog_session_replay/datadog_session_replay.dart';
import 'package:datadog_session_replay/src/capture/element_recorders/common_nodes.dart';
import 'package:datadog_session_replay/src/capture/element_recorders/container_recorder.dart';
import 'package:datadog_session_replay/src/capture/recorder.dart';
import 'package:datadog_session_replay/src/extensions.dart';
import 'package:datadog_session_replay/src/rum_context.dart';
import 'package:datadog_session_replay/src/sr_data_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'simple_test_capture.dart';

void main() {
  late SessionReplayRecorder recorder;
  late KeyGenerator keys;
  late RUMContext context;

  setUp(() {
    keys = KeyGenerator();
    recorder = SessionReplayRecorder.withCustomRecorders(
      [ContainerRecorder(keys)],
      defaultCapturePrivacy: TreeCapturePrivacy(
        textAndInputPrivacyLevel: TextAndInputPrivacyLevel.maskSensitiveInputs,
        imagePrivacyLevel: ImagePrivacyLevel.maskNonAssetsOnly,
      ),
      touchPrivacyLevel: TouchPrivacyLevel.show,
    );

    context = RUMContext(
      applicationId: randomString(),
      sessionId: randomString(),
    );
    recorder.updateContext(context);
  });

  group('dominantColorFromGradient', () {
    test('two-stop black/white defaults to mid gray', () {
      final c = dominantColorFromGradient(
        const LinearGradient(colors: [Colors.black, Colors.white]),
      );
      expect(c, isNotNull);
      expect(c!.toHexString(), '#808080ff');
    });

    test('respects explicit stops for weighted average', () {
      const colors = [Colors.red, Colors.green, Colors.blue];
      const stops = [0.0, 0.25, 1.0];
      final c = dominantColorFromGradient(
        const LinearGradient(colors: colors, stops: stops),
      );
      expect(c, isNotNull);

      var sumR = 0.0, sumG = 0.0, sumB = 0.0, sumA = 0.0, sumW = 0.0;
      for (var i = 0; i < colors.length; i++) {
        final prev = i == 0 ? 0.0 : (stops[i - 1] + stops[i]) / 2;
        final next =
            i == colors.length - 1 ? 1.0 : (stops[i] + stops[i + 1]) / 2;
        final w = (next - prev).clamp(0.0, 1.0);
        final col = colors[i];
        sumR += col.r * w;
        sumG += col.g * w;
        sumB += col.b * w;
        sumA += col.a * w;
        sumW += w;
      }
      expect(c!.r, closeTo(sumR / sumW, 1e-5));
      expect(c.g, closeTo(sumG / sumW, 1e-5));
      expect(c.b, closeTo(sumB / sumW, 1e-5));
      expect(c.a, closeTo(sumA / sumW, 1e-5));
    });
  });

  testWidgets('solid BoxDecoration captures background only', (tester) async {
    const w = 80.0;
    const h = 40.0;
    await tester.pumpWidget(
      SimpleTestCapture(
        key: const Key('solid'),
        recorder: recorder,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 200,
            height: 100,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Colors.red,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final capture = await recorder.performCapture();
    expect(capture, isNotNull);
    final node = capture!.viewTreeSnapshot.nodes.single as ContainerNode;
    expect(node.style.backgroundColor, Colors.red.toHexString());
    expect(node.style.shadows, isEmpty);

    final wfs = node.buildWireframes();
    expect(wfs, hasLength(1));
    final shape = wfs.single as SRShapeWireframe;
    expect(shape.shapeStyle?.backgroundColor, Colors.red.toHexString());
  });

  testWidgets('gradient BoxDecoration uses dominant color', (tester) async {
    const w = 80.0;
    const h = 40.0;
    await tester.pumpWidget(
      SimpleTestCapture(
        key: const Key('grad'),
        recorder: recorder,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 200,
            height: 100,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.black, Colors.white],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final capture = await recorder.performCapture();
    expect(capture, isNotNull);
    final node = capture!.viewTreeSnapshot.nodes.single as ContainerNode;
    expect(node.style.backgroundColor, '#808080ff');
    expect(node.buildWireframes(), hasLength(1));
  });

  testWidgets('BoxDecoration boxShadow emits shape behind container', (
    tester,
  ) async {
    const w = 80.0;
    const h = 40.0;
    await tester.pumpWidget(
      SimpleTestCapture(
        key: const Key('shadow1'),
        recorder: recorder,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 200,
            height: 100,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black,
                            offset: Offset(3, 4),
                            blurRadius: 2,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final capture = await recorder.performCapture();
    expect(capture, isNotNull);
    final node = capture!.viewTreeSnapshot.nodes.single as ContainerNode;
    expect(node.style.shadows, hasLength(1));

    final wfs = node.buildWireframes();
    expect(wfs, hasLength(2));

    final shadow = wfs[0] as SRShapeWireframe;
    final main = wfs[1] as SRShapeWireframe;
    expect(shadow.id, isNot(main.id));
    expect(shadow.shapeStyle?.backgroundColor, '#00000080');

    final spreadPx = (1.0 + 2.0 * 0.5).round(); // 2
    expect(shadow.x, main.x + 3 - spreadPx);
    expect(shadow.y, main.y + 4 - spreadPx);
    expect(shadow.width, main.width + 2 * spreadPx);
    expect(shadow.height, main.height + 2 * spreadPx);
  });

  testWidgets('multiple BoxShadow preserves order', (tester) async {
    await tester.pumpWidget(
      SimpleTestCapture(
        key: const Key('shadow2'),
        recorder: recorder,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 200,
            height: 100,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: SizedBox(
                    width: 60,
                    height: 30,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0xffff0000),
                            offset: Offset(1, 0),
                            blurRadius: 0,
                            spreadRadius: 0,
                          ),
                          BoxShadow(
                            color: Color(0xff00ff00),
                            offset: Offset(2, 0),
                            blurRadius: 0,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final capture = await recorder.performCapture();
    final node = capture!.viewTreeSnapshot.nodes.single as ContainerNode;
    expect(node.style.shadows, hasLength(2));

    final wfs = node.buildWireframes();
    expect(wfs, hasLength(3));
    expect(
        (wfs[0] as SRShapeWireframe).shapeStyle?.backgroundColor, '#ff000080');
    expect(
        (wfs[1] as SRShapeWireframe).shapeStyle?.backgroundColor, '#00ff0080');
  });

  testWidgets('ShapeDecoration gradient and shadows', (tester) async {
    await tester.pumpWidget(
      SimpleTestCapture(
        key: const Key('shape'),
        recorder: recorder,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 200,
            height: 100,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: SizedBox(
                    width: 70,
                    height: 35,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.blue, Colors.red],
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        shadows: const [
                          BoxShadow(
                            color: Colors.black54,
                            offset: Offset(0, 2),
                            blurRadius: 4,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final capture = await recorder.performCapture();
    final node = capture!.viewTreeSnapshot.nodes.single as ContainerNode;
    expect(node.style.backgroundColor, isNotNull);
    expect(node.style.shadows, hasLength(1));

    final wfs = node.buildWireframes();
    expect(wfs, hasLength(2));
    expect(wfs[0], isA<SRShapeWireframe>());
    expect(wfs[1], isA<SRShapeWireframe>());
  });

  testWidgets('shadow wireframe ids stable across captures', (tester) async {
    await tester.pumpWidget(
      SimpleTestCapture(
        key: const Key('stable'),
        recorder: recorder,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 200,
            height: 100,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black,
                            blurRadius: 0,
                            spreadRadius: 0,
                            offset: Offset(2, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final c1 = await recorder.performCapture();
    final c2 = await recorder.performCapture();
    expect(c1, isNotNull);
    expect(c2, isNotNull);

    final n1 = c1!.viewTreeSnapshot.nodes.single as ContainerNode;
    final n2 = c2!.viewTreeSnapshot.nodes.single as ContainerNode;

    final w1 = n1.buildWireframes();
    final w2 = n2.buildWireframes();
    expect((w1[0] as SRShapeWireframe).id, (w2[0] as SRShapeWireframe).id);
    expect((w1[1] as SRShapeWireframe).id, (w2[1] as SRShapeWireframe).id);
  });
}
