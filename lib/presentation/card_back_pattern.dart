import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../ui/theme/game_palette.dart';

/// The fine, tone-on-tone diamond-and-pip texture drawn on the face-down card
/// back. Purely decorative: it takes a [size] and shows a dense lattice of
/// small green diamonds, each holding a tiny suit pip, all scaled to that size
/// so the texture stays uniform whether the card renders at 48px on a phone or
/// much larger.
///
/// It paints on a transparent background and draws no border of its own — the
/// card back supplies the gold border and green gradient, which show through
/// the frame band and behind this texture for a seamless look. A fine, uniform
/// texture (rather than a few big shapes) also fans cleanly: a stacked card's
/// thin visible sliver never breaks into ugly partial shapes.
///
/// The texture is ~140 vector paths. Re-tessellating them for every face-down
/// card on every animation frame is far too much GPU work (it hung FreeCell's
/// 52-card deal on a low-end Adreno GPU and made moves stutter on tablets), so
/// [DiamondPipPainter] runs once per size into a [ui.Image] — with the
/// [cornerRadius] clip baked in — via [CardBackRaster], and every card back
/// blits that shared image as a single textured quad.
class CardBackPattern extends StatelessWidget {
  const CardBackPattern({required this.size, this.cornerRadius = 0, super.key});

  final Size size;

  /// Radius of the rounded-rectangle clip baked into the texture.
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    final double pixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return RawImage(
      image: CardBackRaster.imageFor(size, cornerRadius, pixelRatio),
      width: size.width,
      height: size.height,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// A small process-wide cache of rasterised [DiamondPipPainter] textures, keyed
/// by logical size, corner radius and device pixel ratio. A board only ever
/// shows one card size at a time (two across a rotation), so the cache is tiny
/// and bounded; evicted images are left to the garbage collector because a
/// mounted [RawImage] may still reference them.
class CardBackRaster {
  const CardBackRaster._();

  static const int _maxEntries = 4;

  static final Map<(Size, double, double), ui.Image> _cache =
      <(Size, double, double), ui.Image>{};

  /// The texture for a [size] pattern clipped to [cornerRadius], rendered at
  /// [pixelRatio] physical pixels per logical pixel. Returns the identical
  /// [ui.Image] for identical arguments.
  static ui.Image imageFor(Size size, double cornerRadius, double pixelRatio) {
    final (Size, double, double) key = (size, cornerRadius, pixelRatio);
    final ui.Image? cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached; // re-insert as most recently used
      return cached;
    }
    final ui.Image image = _render(size, cornerRadius, pixelRatio);
    if (_cache.length >= _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = image;
    return image;
  }

  static ui.Image _render(Size size, double cornerRadius, double pixelRatio) {
    final int width = math.max(1, (size.width * pixelRatio).ceil());
    final int height = math.max(1, (size.height * pixelRatio).ceil());
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder)
      ..scale(pixelRatio)
      ..clipRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(math.max(0, cornerRadius)),
        ),
      );
    const DiamondPipPainter().paint(canvas, size);
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = picture.toImageSync(width, height);
    picture.dispose();
    return image;
  }
}

/// Paints a fine diamond lattice with tiny four-suit pips, in a single green
/// tone on a transparent background, proportioned to the card width.
///
/// The suit pips are drawn as **vector paths**, not text glyphs: the Unicode
/// suit characters render as colour-emoji on many platforms and would ignore
/// the tone-on-tone green (e.g. hearts turning red). Drawing them ourselves
/// keeps every suit the exact pattern colour.
///
/// All measurements derive from [Size.width] so the texture keeps the same
/// visual density at every render size:
/// - diamond cell: `0.15 x 0.21` of the width (aspect ≈ 1.4, matching the card),
/// - lattice stroke: `0.008 x width`,
/// - suit pip: `0.55` of the cell width, cycling ♠ ♥ ♦ ♣ across the grid.
class DiamondPipPainter extends CustomPainter {
  const DiamondPipPainter();

  static const double _cellWFactor = 0.15;
  static const double _cellAspect = 1.4; // cell height / cell width
  static const double _strokeFactor = 0.008;
  static const double _pipFactor = 0.55; // pip size / cell width

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double cellW = w * _cellWFactor;
    final double cellH = cellW * _cellAspect;
    if (cellW <= 0 || cellH <= 0) return;

    // One green tone for both the lattice and the pips.
    final Color tone = GamePalette.feltGreenLight.withValues(alpha: 0.6);
    final Paint lattice = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * _strokeFactor
      ..strokeJoin = StrokeJoin.round
      ..color = tone;
    final Paint pipFill = Paint()
      ..style = PaintingStyle.fill
      ..color = tone;

    final double hw = cellW / 2;
    final double hh = cellH / 2;
    final double pip = cellW * _pipFactor;

    final int cols = (w / cellW).ceil() + 1;
    final int rows = (size.height / cellH).ceil() + 1;

    for (int j = 0; j < rows; j++) {
      final double cy = cellH * (j + 0.5);
      for (int i = 0; i < cols; i++) {
        final double cx = cellW * (i + 0.5);

        final Path diamond = Path()
          ..moveTo(cx, cy - hh)
          ..lineTo(cx + hw, cy)
          ..lineTo(cx, cy + hh)
          ..lineTo(cx - hw, cy)
          ..close();
        canvas.drawPath(diamond, lattice);

        canvas.drawPath(_suitPath((i + 2 * j) % 4, cx, cy, pip), pipFill);
      }
    }
  }

  /// A filled suit silhouette centred at ([cx], [cy]) with overall size [s].
  /// [suit]: 0 = spade, 1 = heart, 2 = diamond, 3 = club.
  Path _suitPath(int suit, double cx, double cy, double s) {
    switch (suit) {
      case 1:
        return _heart(cx, cy, s);
      case 2:
        return _diamond(cx, cy, s);
      case 3:
        return _club(cx, cy, s);
      default:
        return _spade(cx, cy, s);
    }
  }

  Path _heart(double cx, double cy, double s) {
    final double w = s, h = s;
    return Path()
      ..moveTo(cx, cy + h * 0.34)
      ..cubicTo(
        cx - w * 0.52,
        cy - h * 0.02,
        cx - w * 0.5,
        cy - h * 0.46,
        cx,
        cy - h * 0.16,
      )
      ..cubicTo(
        cx + w * 0.5,
        cy - h * 0.46,
        cx + w * 0.52,
        cy - h * 0.02,
        cx,
        cy + h * 0.34,
      )
      ..close();
  }

  Path _diamond(double cx, double cy, double s) {
    final double w = s, h = s;
    return Path()
      ..moveTo(cx, cy - h * 0.44)
      ..lineTo(cx + w * 0.32, cy)
      ..lineTo(cx, cy + h * 0.44)
      ..lineTo(cx - w * 0.32, cy)
      ..close();
  }

  Path _spade(double cx, double cy, double s) {
    final double w = s, h = s;
    final Path p = Path()
      ..moveTo(cx, cy - h * 0.42)
      ..cubicTo(
        cx + w * 0.5,
        cy - h * 0.02,
        cx + w * 0.5,
        cy + h * 0.3,
        cx,
        cy + h * 0.12,
      )
      ..cubicTo(
        cx - w * 0.5,
        cy + h * 0.3,
        cx - w * 0.5,
        cy - h * 0.02,
        cx,
        cy - h * 0.42,
      )
      ..close();
    // Stem.
    p
      ..moveTo(cx - w * 0.14, cy + h * 0.4)
      ..lineTo(cx + w * 0.14, cy + h * 0.4)
      ..lineTo(cx + w * 0.05, cy + h * 0.1)
      ..lineTo(cx - w * 0.05, cy + h * 0.1)
      ..close();
    return p;
  }

  Path _club(double cx, double cy, double s) {
    final double w = s, h = s, r = w * 0.19;
    final Path p = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy - h * 0.2), radius: r))
      ..addOval(
        Rect.fromCircle(
          center: Offset(cx - w * 0.23, cy + h * 0.06),
          radius: r,
        ),
      )
      ..addOval(
        Rect.fromCircle(
          center: Offset(cx + w * 0.23, cy + h * 0.06),
          radius: r,
        ),
      );
    // Stem.
    p
      ..moveTo(cx - w * 0.13, cy + h * 0.42)
      ..lineTo(cx + w * 0.13, cy + h * 0.42)
      ..lineTo(cx + w * 0.05, cy + h * 0.05)
      ..lineTo(cx - w * 0.05, cy + h * 0.05)
      ..close();
    return p;
  }

  @override
  bool shouldRepaint(DiamondPipPainter oldDelegate) => false;
}
