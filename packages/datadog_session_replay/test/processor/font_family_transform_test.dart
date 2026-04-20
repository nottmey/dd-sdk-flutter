// Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-Present Datadog, Inc.

import 'package:datadog_session_replay/datadog_session_replay.dart';
import 'package:datadog_session_replay/src/processor/font_family_transform.dart';
import 'package:datadog_session_replay/src/sr_data_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stripPackageFontPrefix', () {
    test('strips packages/<pkg>/ prefix', () {
      expect(
        stripPackageFontPrefix('packages/google_fonts/Roboto'),
        'Roboto',
      );
      expect(stripPackageFontPrefix('Roboto'), 'Roboto');
      expect(stripPackageFontPrefix('packages/foo/bar/Baz'), 'bar/Baz');
    });
  });

  group('FontFamilyTransform.apply', () {
    const iosStack = kIosParityFontStack;
    const smartConfig = FontFamilyTransformConfig(
      strategy: FontFamilyStrategy.smart,
    );

    test('none returns input unchanged', () {
      final t = FontFamilyTransform(
        const FontFamilyTransformConfig(strategy: FontFamilyStrategy.none),
      );
      const raw = 'packages/google_fonts/Roboto';
      expect(t.apply(raw), raw);
    });

    test('fallback always returns iOS-parity stack', () {
      final t = FontFamilyTransform(
        const FontFamilyTransformConfig(strategy: FontFamilyStrategy.fallback),
      );
      expect(t.apply(''), iosStack);
      expect(t.apply('Anything'), iosStack);
    });

    test('smart: empty becomes iOS-parity stack', () {
      final t = FontFamilyTransform(smartConfig);
      expect(t.apply(''), iosStack);
      expect(t.apply('   '), iosStack);
    });

    test('smart: rules empty key overrides fallback for empty captured', () {
      final t = FontFamilyTransform(
        FontFamilyTransformConfig(
          strategy: FontFamilyStrategy.smart,
          rules: {'': 'Georgia, serif'},
        ),
      );
      expect(t.apply(''), 'Georgia, serif');
      expect(t.apply('   '), 'Georgia, serif');
    });

    test('smart: rules empty key applies when only sentinels remain', () {
      final t = FontFamilyTransform(
        FontFamilyTransformConfig(
          strategy: FontFamilyStrategy.smart,
          rules: {'': 'Verdana, sans-serif'},
        ),
      );
      expect(t.apply('CupertinoSystemText'), 'Verdana, sans-serif');
    });

    test('smart: rules empty key whitespace-only value uses default stack', () {
      final t = FontFamilyTransform(
        FontFamilyTransformConfig(
          strategy: FontFamilyStrategy.smart,
          rules: {'': '   '},
        ),
      );
      expect(t.apply(''), iosStack);
    });

    test('smart: only sentinels become iOS-parity stack', () {
      final t = FontFamilyTransform(smartConfig);
      expect(t.apply('CupertinoSystemText'), iosStack);
      expect(t.apply('.SF UI Text'), iosStack);
    });

    test('smart: packages prefix stripped and sans-serif appended', () {
      final t = FontFamilyTransform(smartConfig);
      expect(
        t.apply('packages/google_fonts/Roboto'),
        'Roboto, sans-serif',
      );
    });

    test('smart: comma-separated list preserves order and drops sentinel', () {
      final t = FontFamilyTransform(smartConfig);
      expect(
        t.apply('Roboto, CupertinoSystemText'),
        'Roboto, sans-serif',
      );
    });

    test('smart: quotes spaces in family names', () {
      final t = FontFamilyTransform(smartConfig);
      expect(
        t.apply('Open Sans'),
        "'Open Sans', sans-serif",
      );
    });

    test('smart: rules override before sentinel strip', () {
      final t = FontFamilyTransform(
        FontFamilyTransformConfig(
          strategy: FontFamilyStrategy.smart,
          rules: {
            'CupertinoSystemText': 'Inter, sans-serif',
          },
        ),
      );
      expect(t.apply('CupertinoSystemText'), 'Inter, sans-serif');
    });

    test('smart: rules match stripped packages key', () {
      final t = FontFamilyTransform(
        FontFamilyTransformConfig(
          strategy: FontFamilyStrategy.smart,
          rules: {
            'Roboto': 'Lato, sans-serif',
          },
        ),
      );
      expect(
        t.apply('packages/google_fonts/Roboto'),
        'Lato, sans-serif',
      );
    });

    test('smart: rules prefer peeled key over stripped when both exist', () {
      final t = FontFamilyTransform(
        FontFamilyTransformConfig(
          strategy: FontFamilyStrategy.smart,
          rules: {
            'packages/foo/Roboto': 'FromPeeled',
            'Roboto': 'FromStripped',
          },
        ),
      );
      expect(t.apply('packages/foo/Roboto'), 'FromPeeled, sans-serif');
    });

    test('smart: does not append sans-serif when already generic', () {
      final t = FontFamilyTransform(smartConfig);
      expect(t.apply('serif'), 'serif');
      expect(t.apply('monospace'), 'monospace');
      expect(t.apply('Roboto, sans-serif'), 'Roboto, sans-serif');
    });

    test('smart: idempotent on iOS-parity stack', () {
      final t = FontFamilyTransform(smartConfig);
      final once = t.apply('');
      expect(once, iosStack);
      final twice = t.apply(once);
      expect(twice, once);
    });

    test('smart: idempotent on typical transformed output', () {
      final t = FontFamilyTransform(smartConfig);
      final once = t.apply('Roboto');
      final twice = t.apply(once);
      expect(once, 'Roboto, sans-serif');
      expect(twice, once);
    });

    test('rewrite updates SRTextWireframe textStyle.family', () {
      final t = FontFamilyTransform(smartConfig);
      final w = SRTextWireframe(
        id: 1,
        x: 0,
        y: 0,
        width: 10,
        height: 10,
        text: 'hi',
        textStyle: SRTextStyle(
          color: '#FF0000FF',
          family: '',
          size: 12,
        ),
      );
      final out = t.rewrite(w);
      expect(out.textStyle.family, iosStack);
      expect(identical(out, w), isFalse);
    });

    test('rewrite returns same instance when none strategy', () {
      final t = FontFamilyTransform(
        const FontFamilyTransformConfig(strategy: FontFamilyStrategy.none),
      );
      final w = SRTextWireframe(
        id: 1,
        x: 0,
        y: 0,
        width: 10,
        height: 10,
        text: 'hi',
        textStyle: SRTextStyle(
          color: '#FF0000FF',
          family: 'packages/x/Y',
          size: 12,
        ),
      );
      final out = t.rewrite(w);
      expect(identical(out, w), isTrue);
    });

    test('smart: re-applying iOS-parity stack is idempotent string', () {
      final t = FontFamilyTransform(smartConfig);
      expect(t.apply(kIosParityFontStack), kIosParityFontStack);
    });
  });
}
