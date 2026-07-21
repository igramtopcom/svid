import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/config/brand_config.dart';

/// Variant gives each tab a distinct "character" within the same
/// 4-layer atmosphere system. Full intensity across all — only the
/// drift rhythm, particle density, and palette tilt differ.
enum AuroraVariant {
  /// Home dashboard — baseline cinematic: 4 blobs, 50 particles, wine-balanced.
  cinematic,

  /// YouTube Explore — same as cinematic but reacts to `isExtracting`
  /// (speed ×1.8 + bloom) when viewing search results.
  explore,

  /// Converter / Forge — "workbench" feel. Warmer palette (brandDark-tilted),
  /// drift ×0.8 (heavier mass), 35 particles (steadier, less noise).
  forge,

  /// Subscriptions / Archive — "library at night". Cooler palette
  /// (gradientMid-tilted), drift ×0.6 (almost still), 30 particles.
  archive,

  /// Browser new-tab / Portal — "command center / flight deck". Dark keeps
  /// cinematic wine for brand continuity. Light swaps the pink-blush palette
  /// for cool silver + steel + ink (the default light palette reads as
  /// "valentine" in a browser surface). Drift ×1.0, 45 particles.
  portal,

  /// Support / Vault — "help desk / safe storage". Reassuring, grounded.
  /// Light: moss + parchment + sage; dark: muted wine (quieter than home).
  /// Drift ×0.7, 28 particles.
  vault,

  /// AI Assistant / Dawn — "thinking at daybreak". Cool lavender-indigo,
  /// slow drift, contemplative. Drift ×0.75, 40 particles.
  dawn,

  /// Premium / Crown — "throne room". Gold + obsidian dark, champagne +
  /// gold light. Slightly richer drift and extra orb presence. Drift ×0.9,
  /// 42 particles.
  crown,
}

/// Cinematic Aurora — breakthrough atmospheric background.
///
/// Four layers stacked, driven by a single 60s ticker:
///   1. Aurora mesh gradient — soft color blobs drift on Lissajous curves.
///   2. Drifting orbs — blurred orbs drift + track mouse parallax.
///   3. Particle field — dust motes drift on seeded velocities.
///   4. Extraction bloom — central pulse overlay while extracting.
///
/// Brand-aware (via `BrandConfig.current.colors`) and light/dark adaptive.
/// When `isExtracting`, time scales 1.8× and the bloom overlay fades in.
///
/// Use `variant` to give each tab its own atmospheric signature (drift
/// rhythm, particle count, palette tilt). `intensity` is legacy — prefer
/// variants for differentiation.
class CinematicAuroraBackground extends StatefulWidget {
  final bool isExtracting;

  /// Per-tab character. See [AuroraVariant].
  final AuroraVariant variant;

  /// Legacy alpha/speed scaler. 1.0 = full. Kept for back-compat; prefer
  /// variants going forward.
  final double intensity;

  const CinematicAuroraBackground({
    super.key,
    this.isExtracting = false,
    this.variant = AuroraVariant.cinematic,
    this.intensity = 1.0,
  });

  @override
  State<CinematicAuroraBackground> createState() =>
      _CinematicAuroraBackgroundState();
}

class _CinematicAuroraBackgroundState extends State<CinematicAuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;
  Offset _mouseNorm = Offset.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
    // Per-variant seed so each tab has its own particle constellation —
    // not the same 50 motes drifting identically in 4 places.
    final seed = switch (widget.variant) {
      AuroraVariant.cinematic => 0xA05A,
      AuroraVariant.explore => 0xB17C,
      AuroraVariant.forge => 0xF07E,
      AuroraVariant.archive => 0xAC71,
      AuroraVariant.portal => 0x90B7,
      AuroraVariant.vault => 0x5E9A,
      AuroraVariant.dawn => 0x2C4F,
      AuroraVariant.crown => 0xC3A1,
    };
    final count = switch (widget.variant) {
      AuroraVariant.cinematic || AuroraVariant.explore => 50,
      AuroraVariant.forge => 35,
      AuroraVariant.archive => 30,
      AuroraVariant.portal => 45,
      AuroraVariant.vault => 28,
      AuroraVariant.dawn => 40,
      AuroraVariant.crown => 42,
    };
    final rng = math.Random(seed);
    _particles = List.generate(count, (_) => _Particle.random(rng));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Windows/ANGLE can render tiny animated white motes as one-frame
    // subpixel streaks on dark surfaces. Keep the smooth aurora/orb layers,
    // but remove random dust so dark Windows feels stable instead of glitchy.
    final suppressParticleField =
        isDark && defaultTargetPlatform == TargetPlatform.windows;
    final palette = _AuroraPalette.resolve(
      BrandConfig.current,
      isDark,
      intensity: widget.intensity,
      variant: widget.variant,
    );
    // Each variant has its own drift rhythm — the big atmospheric tell.
    // forge = heavier/slower (workbench mass), archive = still (library night).
    final variantSpeed = switch (widget.variant) {
      AuroraVariant.cinematic || AuroraVariant.explore || AuroraVariant.portal => 1.0,
      AuroraVariant.forge => 0.8,
      AuroraVariant.archive => 0.6,
      AuroraVariant.vault => 0.7,
      AuroraVariant.dawn => 0.75,
      AuroraVariant.crown => 0.9,
    };
    final speedMul = (widget.isExtracting ? 1.8 : 1.0) *
        (0.55 + 0.45 * widget.intensity.clamp(0.0, 1.0)) *
        variantSpeed;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        if (w == 0 || h == 0) return const SizedBox.shrink();

        return MouseRegion(
          opaque: false,
          hitTestBehavior: HitTestBehavior.translucent,
          onHover: (event) {
            if (!mounted) return;
            final dx =
                ((event.localPosition.dx / w) * 2 - 1).clamp(-1.0, 1.0);
            final dy =
                ((event.localPosition.dy / h) * 2 - 1).clamp(-1.0, 1.0);
            if (dx != _mouseNorm.dx || dy != _mouseNorm.dy) {
              setState(() => _mouseNorm = Offset(dx, dy));
            }
          },
          onExit: (_) {
            if (!mounted) return;
            setState(() => _mouseNorm = Offset.zero);
          },
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value * speedMul;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Base wash — prevents banding between layers.
                    DecoratedBox(
                      decoration: BoxDecoration(color: palette.base),
                    ),
                    RepaintBoundary(
                      child: _AuroraMeshLayer(t: t, palette: palette),
                    ),
                    RepaintBoundary(
                      child: _DriftingOrbLayer(
                        t: t,
                        palette: palette,
                        mouseNorm: _mouseNorm,
                      ),
                    ),
                    if (!suppressParticleField)
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: _ParticleFieldPainter(
                            particles: _particles,
                            t: t,
                            color: palette.particle,
                            speedBoost: widget.isExtracting ? 1.8 : 1.0,
                          ),
                          size: Size.infinite,
                        ),
                      ),
                    if (widget.isExtracting && widget.intensity >= 0.3)
                      _ExtractionBloom(
                        t: _controller.value,
                        color: palette.bloom,
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Layer 1 — Aurora mesh: 4 soft radial blobs drifting on Lissajous paths.
// ─────────────────────────────────────────────────────────────────────────────

class _AuroraMeshLayer extends StatelessWidget {
  final double t;
  final _AuroraPalette palette;

  const _AuroraMeshLayer({required this.t, required this.palette});

  @override
  Widget build(BuildContext context) {
    final blobs = palette.meshBlobs;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (int i = 0; i < blobs.length; i++)
          _MeshBlob(
            alignment: _lissajousAlignment(t, i),
            color: blobs[i],
            radius: 0.9 + 0.15 * math.sin(2 * math.pi * (t * 0.6 + i * 0.25)),
          ),
      ],
    );
  }

  // Non-repeating drift paths: irrational frequency ratios per blob.
  Alignment _lissajousAlignment(double t, int i) {
    const freqsX = [0.37, 0.51, 0.29, 0.44];
    const freqsY = [0.43, 0.33, 0.47, 0.39];
    const phaseX = [0.0, 1.3, 2.6, 4.1];
    const phaseY = [0.7, 2.2, 3.4, 5.0];
    final x = math.sin(2 * math.pi * freqsX[i] * t + phaseX[i]);
    final y = math.cos(2 * math.pi * freqsY[i] * t + phaseY[i]);
    return Alignment(x * 0.95, y * 0.95);
  }
}

class _MeshBlob extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final double radius;

  const _MeshBlob({
    required this.alignment,
    required this.color,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: alignment,
          radius: radius,
          colors: [color, color.withValues(alpha: 0)],
          stops: const [0.0, 1.0],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Layer 2 — Drifting orbs (blur + mouse parallax).
// ─────────────────────────────────────────────────────────────────────────────

class _DriftingOrbLayer extends StatelessWidget {
  final double t;
  final _AuroraPalette palette;
  final Offset mouseNorm;

  const _DriftingOrbLayer({
    required this.t,
    required this.palette,
    required this.mouseNorm,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        final orbs = palette.orbs;
        return Stack(
          fit: StackFit.expand,
          children: [
            for (int i = 0; i < orbs.length; i++) _buildOrb(i, orbs[i], w, h),
          ],
        );
      },
    );
  }

  Widget _buildOrb(int index, Color color, double w, double h) {
    // Per-orb drift frequency + phase + parallax strength (back → front).
    const drift = [
      (fx: 0.11, fy: 0.09, px: 1.1, py: 2.3, pxMul: 6.0, pyMul: 6.0, size: 720.0, blur: 70.0),
      (fx: 0.17, fy: 0.13, px: 3.4, py: 0.6, pxMul: 14.0, pyMul: 14.0, size: 560.0, blur: 45.0),
      (fx: 0.23, fy: 0.19, px: 5.1, py: 4.7, pxMul: 28.0, pyMul: 28.0, size: 420.0, blur: 20.0),
    ];
    final d = drift[index];
    final dx = math.sin(2 * math.pi * d.fx * t + d.px);
    final dy = math.cos(2 * math.pi * d.fy * t + d.py);

    // Drift range: half the off-screen margin so orbs stay partially bleeding.
    final cx = w * 0.5 + dx * w * 0.35 + mouseNorm.dx * d.pxMul;
    final cy = h * 0.5 + dy * h * 0.35 + mouseNorm.dy * d.pyMul;
    final r = d.size;

    return Positioned(
      left: cx - r / 2,
      top: cy - r / 2,
      width: r,
      height: r,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: d.blur, sigmaY: d.blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Layer 3 — Particle dust field.
// ─────────────────────────────────────────────────────────────────────────────

class _Particle {
  final double x0, y0;
  final double vx, vy;
  final double size;
  final double phase;

  _Particle({
    required this.x0,
    required this.y0,
    required this.vx,
    required this.vy,
    required this.size,
    required this.phase,
  });

  factory _Particle.random(math.Random rng) {
    return _Particle(
      x0: rng.nextDouble(),
      y0: rng.nextDouble(),
      vx: (rng.nextDouble() - 0.5) * 0.08,
      vy: (rng.nextDouble() - 0.5) * 0.08,
      size: 0.6 + rng.nextDouble() * 1.8,
      phase: rng.nextDouble() * 2 * math.pi,
    );
  }
}

class _ParticleFieldPainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;
  final Color color;
  final double speedBoost;

  _ParticleFieldPainter({
    required this.particles,
    required this.t,
    required this.color,
    required this.speedBoost,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final tt = t * speedBoost;
    for (final p in particles) {
      // Torus wrap so particles never disappear abruptly.
      final nx = (p.x0 + p.vx * tt * 60) % 1.0;
      final ny = (p.y0 + p.vy * tt * 60) % 1.0;
      final x = ((nx + 1) % 1.0) * size.width;
      final y = ((ny + 1) % 1.0) * size.height;
      final breath = 0.45 + 0.55 * (0.5 + 0.5 * math.sin(tt * 2 + p.phase));
      paint.color = color.withValues(alpha: color.a * breath);
      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticleFieldPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Layer 4 — Extraction bloom overlay.
// ─────────────────────────────────────────────────────────────────────────────

class _ExtractionBloom extends StatelessWidget {
  final double t;
  final Color color;

  const _ExtractionBloom({required this.t, required this.color});

  @override
  Widget build(BuildContext context) {
    // Pulse at 1.2 Hz — fast enough to read as "working", not anxious.
    final pulse = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * 2 * math.pi * 1.2));
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.0, -0.15),
              radius: 0.7,
              colors: [
                color.withValues(alpha: color.a * pulse),
                color.withValues(alpha: 0),
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Palette resolver — brand + theme → concrete colors for every layer.
// ─────────────────────────────────────────────────────────────────────────────

class _AuroraPalette {
  final Color base;
  final List<Color> meshBlobs;
  final List<Color> orbs;
  final Color particle;
  final Color bloom;

  const _AuroraPalette({
    required this.base,
    required this.meshBlobs,
    required this.orbs,
    required this.particle,
    required this.bloom,
  });

  static _AuroraPalette resolve(
    BrandConfig cfg,
    bool isDark, {
    double intensity = 1.0,
    AuroraVariant variant = AuroraVariant.cinematic,
  }) {
    final c = cfg.colors;
    final k = intensity.clamp(0.0, 1.0);
    Color scale(Color base, double a) => base.withValues(alpha: a * k);

    // Tilt = (warm, cool) weights per variant — shifts blob emphasis without
    // changing the brand palette. forge leans warm (furnace), archive leans
    // strongly cool (library at night — wine should recede, not lead).
    final (warm, cool) = switch (variant) {
      AuroraVariant.forge => (1.35, 0.75),
      AuroraVariant.archive => (0.45, 1.55),
      AuroraVariant.vault => (0.85, 1.10), // grounded, slight cool lean
      AuroraVariant.dawn => (0.55, 1.35), // cool indigo lean
      AuroraVariant.crown => (1.15, 0.95), // warm gold lean
      _ => (1.0, 1.0),
    };

    // Dawn dark — lavender/indigo (not brand wine). Brand identity is a
    // whisper, not the lead. Override dark path entirely for dawn + crown.
    if (isDark && variant == AuroraVariant.dawn) {
      const indigoDeep = Color(0xFF1A1A2E);
      const lavender = Color(0xFF7A6FB4);
      const mist = Color(0xFF4A5680);
      const nightBlue = Color(0xFF2E3A5F);
      return _AuroraPalette(
        base: indigoDeep,
        meshBlobs: [
          scale(lavender, 0.32),
          scale(mist, 0.28),
          scale(nightBlue, 0.30),
          scale(c.brandDark, 0.14), // faint wine hint
        ],
        orbs: [
          scale(lavender, 0.34),
          scale(mist, 0.28),
          scale(nightBlue, 0.18),
        ],
        particle: Colors.white.withValues(alpha: 0.12 * k),
        bloom: scale(lavender, 0.20),
      );
    }

    // Crown dark — gold on obsidian. Throne room vibe.
    if (isDark && variant == AuroraVariant.crown) {
      const obsidian = Color(0xFF14100C);
      const gold = Color(0xFFD4A84B);
      const amberDeep = Color(0xFF8A5A1E);
      const emberRed = Color(0xFF7A2F2A);
      return _AuroraPalette(
        base: obsidian,
        meshBlobs: [
          scale(gold, 0.30),
          scale(amberDeep, 0.34),
          scale(c.brandDark, 0.26), // wine stays present (regal cinematic)
          scale(emberRed, 0.22),
        ],
        orbs: [
          scale(gold, 0.34),
          scale(amberDeep, 0.30),
          scale(c.brandDark, 0.22),
        ],
        particle: gold.withValues(alpha: 0.14 * k),
        bloom: scale(gold, 0.22),
      );
    }

    if (isDark) {
      return _AuroraPalette(
        base: c.darkBase,
        meshBlobs: [
          scale(c.gradientStart, 0.35 * warm),
          scale(c.accentHighlight, 0.28 * warm),
          scale(c.brandDark, 0.32 * warm),
          scale(c.gradientMid, 0.26 * cool),
        ],
        orbs: [
          scale(c.brandDark, 0.38 * warm),
          scale(c.gradientMid, 0.30 * cool),
          scale(c.accentHighlight, 0.18 * warm),
        ],
        particle: Colors.white.withValues(alpha: 0.10 * k),
        bloom: scale(c.accentHighlight, 0.18),
      );
    }

    // Forge light has its own metaphor: a forge is fire + heat, and the brand's
    // pink-blush light palette reads as "candy store" in that context. Override
    // with warm-neutral amber/copper tones — "morning workshop" instead.
    if (variant == AuroraVariant.forge) {
      const cream = Color(0xFFF7F2EA); // warm off-white base
      const amber = Color(0xFFE6A94F); // morning sunbeam
      const copper = Color(0xFFB8651D); // heated metal
      const ember = Color(0xFFD97B3A); // soft ember glow
      return _AuroraPalette(
        base: cream,
        meshBlobs: [
          scale(amber, 0.46),
          scale(ember, 0.38),
          scale(copper, 0.30),
          scale(c.brandDark, 0.18), // hint of wine so it reads as "Svid"
        ],
        orbs: [
          scale(amber, 0.48),
          scale(ember, 0.36),
          scale(copper, 0.24),
        ],
        particle: scale(copper, 0.14),
        bloom: scale(ember, 0.20),
      );
    }

    // Archive light — "library at morning" instead of "valentine".
    // The brand's pink light palette fights the "archive/quiet reading room"
    // metaphor completely. Use parchment + muted slate-blue + ink-gray,
    // low saturation so content reads clearly over the top.
    if (variant == AuroraVariant.archive) {
      const parchment = Color(0xFFF4F1EA); // aged paper base
      const slate = Color(0xFF6B7A8F); // cool library dust
      const dust = Color(0xFFA8B3C5); // morning light through shelves
      const ink = Color(0xFF3D4A5E); // deep archival shadow
      return _AuroraPalette(
        base: parchment,
        meshBlobs: [
          scale(dust, 0.30),
          scale(slate, 0.24),
          scale(ink, 0.14),
          scale(c.brandDark, 0.10), // faint wine hint for identity only
        ],
        orbs: [
          scale(dust, 0.32),
          scale(slate, 0.22),
          scale(ink, 0.14),
        ],
        particle: scale(ink, 0.10),
        bloom: scale(slate, 0.14),
      );
    }

    // Vault light — "help desk at morning". Moss + parchment + sage.
    // Reassuring, grounded. Brand wine stays a hint.
    if (variant == AuroraVariant.vault) {
      const parchment = Color(0xFFF5F2E9);
      const moss = Color(0xFF8AA48B);
      const sage = Color(0xFFBFCBB4);
      const deepMoss = Color(0xFF5A7060);
      return _AuroraPalette(
        base: parchment,
        meshBlobs: [
          scale(sage, 0.36),
          scale(moss, 0.28),
          scale(deepMoss, 0.16),
          scale(c.brandDark, 0.10),
        ],
        orbs: [
          scale(sage, 0.36),
          scale(moss, 0.26),
          scale(deepMoss, 0.16),
        ],
        particle: scale(deepMoss, 0.12),
        bloom: scale(moss, 0.16),
      );
    }

    // Dawn light — "thinking at daybreak". Soft lavender + cream + indigo
    // mist. Contemplative, not energetic.
    if (variant == AuroraVariant.dawn) {
      const cream = Color(0xFFF6F3F9);
      const lavender = Color(0xFFB5A8D4);
      const indigoMist = Color(0xFF8B8FB8);
      const dawnInk = Color(0xFF4B4F74);
      return _AuroraPalette(
        base: cream,
        meshBlobs: [
          scale(lavender, 0.38),
          scale(indigoMist, 0.30),
          scale(dawnInk, 0.14),
          scale(c.brandDark, 0.10),
        ],
        orbs: [
          scale(lavender, 0.40),
          scale(indigoMist, 0.28),
          scale(dawnInk, 0.14),
        ],
        particle: scale(dawnInk, 0.12),
        bloom: scale(lavender, 0.18),
      );
    }

    // Crown light — "throne room at dusk". Champagne + gold + warm ivory.
    if (variant == AuroraVariant.crown) {
      const ivory = Color(0xFFFAF5EB);
      const champagne = Color(0xFFE8D7A3);
      const gold = Color(0xFFC99C45);
      const bronze = Color(0xFF8F6226);
      return _AuroraPalette(
        base: ivory,
        meshBlobs: [
          scale(champagne, 0.42),
          scale(gold, 0.34),
          scale(bronze, 0.20),
          scale(c.brandDark, 0.14),
        ],
        orbs: [
          scale(champagne, 0.44),
          scale(gold, 0.32),
          scale(bronze, 0.18),
        ],
        particle: scale(bronze, 0.14),
        bloom: scale(gold, 0.20),
      );
    }

    // Portal light — "command center at daylight". Browser is a portal to the
    // internet; pink-blush reads as valentine, not flight deck. Use cool
    // silver/steel/ink with a faint wine vertical for brand identity.
    if (variant == AuroraVariant.portal) {
      const fog = Color(0xFFF2F4F7); // silver fog base
      const steel = Color(0xFF8793A8); // steel blue
      const mist = Color(0xFFB8C3D4); // cool daylight mist
      const ink = Color(0xFF3B475C); // deep portal shadow
      return _AuroraPalette(
        base: fog,
        meshBlobs: [
          scale(mist, 0.36),
          scale(steel, 0.28),
          scale(ink, 0.14),
          scale(c.brandDark, 0.12), // faint wine identity hint
        ],
        orbs: [
          scale(mist, 0.38),
          scale(steel, 0.26),
          scale(ink, 0.16),
        ],
        particle: scale(ink, 0.12),
        bloom: scale(steel, 0.16),
      );
    }

    return _AuroraPalette(
      base: c.lightBase,
      meshBlobs: [
        scale(c.gradientTail, 0.58 * warm),
        scale(c.brandLight, 0.48 * warm),
        scale(c.accentHighlight, 0.32 * warm),
        scale(c.gradientStart, 0.26 * cool),
      ],
      orbs: [
        scale(c.gradientTail, 0.58 * warm),
        scale(c.brandLight, 0.46 * warm),
        scale(c.accentHighlight, 0.34 * cool),
      ],
      particle: scale(c.brandDark, 0.12),
      bloom: scale(c.accentHighlight, 0.16),
    );
  }
}
