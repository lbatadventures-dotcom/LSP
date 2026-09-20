import Foundation

/// The visual mod stack, toggleable the way the originals are in a KSP install.
///
/// Each one is independent, and each one costs something, so they are individually
/// switchable and all of them respect the quality tier.
struct VisualSettings: Equatable {
    /// EVE: a real cloud layer, plus Scatterer's atmospheric scattering.
    var cloudsAndScattering = true
    /// Waterfall: layered engine plumes that bloom as ambient pressure drops.
    var volumetricPlumes = true
    /// Reentry Particle Effect: plasma sheath and ember wake on atmospheric entry.
    var reentryEffects = true
    /// Distant Object Enhancement: bodies as bright flares, with sky dimming.
    var distantObjects = true

    /// Drops texture resolution and particle counts across the board.
    var reduceEffects = false

    static let `default` = VisualSettings()

    /// Side length of generated body textures.
    var textureResolution: Int { reduceEffects ? 128 : 256 }
    /// Scales every emitter's birth rate.
    var particleScale: Double { reduceEffects ? 0.35 : 1.0 }
    var starCount: Int { reduceEffects ? 90 : 240 }
    /// Cloud puffs drawn in the surface-level band.
    var cloudBandDensity: Int { reduceEffects ? 10 : 26 }
}
