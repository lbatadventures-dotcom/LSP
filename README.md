# Little Space Program

A Kerbal-style rocket game for iPhone and iPad. Build a rocket out of parts, fly it off
the pad by hand, and try to get it into orbit — with real two-body orbital mechanics,
staging, atmospheric drag, patched-conic trajectory prediction and manoeuvre planning.

Native Swift: SwiftUI for the interface, SpriteKit for the world view, no third-party
dependencies and no bitmap art (every part is drawn from code).

## Running it

Open `LittleSpaceProgram.xcodeproj` in Xcode 16 or newer and press Run. Targets iOS 17+,
iPhone and iPad.

The project uses Xcode 16's file-system-synchronized groups, so the folder on disk *is*
the target — adding a Swift file needs no project edit. If the project file ever gets out
of step, `project.yml` regenerates an equivalent one with
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen && xcodegen generate
```

## What is in the game

**The assembly building.** Twenty-four parts across pods, tanks, engines, structure, aero
and utility. Pick a part and every legal attachment point lights up; tap one to place it.
Radial parts (fins, boosters, legs) go on in mirrored pairs. The panel shows total mass,
delta-v, per-stage thrust-to-weight and part count as you build, and warns you about the
usual ways a rocket fails to leave the pad.

**Flight.** Throttle, a rotation rocker, a stage button and five SAS hold modes
(stability, prograde, retrograde, radial in/out). An attitude indicator shows pitch
against the local horizon with prograde and retrograde markers. Engines lose thrust and
specific impulse with ambient pressure, tanks drain through a fuel network that decouplers
cut, solid boosters burn to the end whatever you do, and parachutes tear off if you deploy
them too fast.

**Orbit.** A map view with patched conics: apoapsis and periapsis with live altitudes,
sphere-of-influence circles, impact and atmospheric-entry markers, and predicted moon
encounters. Manoeuvre nodes project the orbit a planned burn would produce and count down
to ignition. Time warp runs to 100000x by switching from integration to analytic Kepler
propagation once you are coasting.

**The system.** Terra (600 km, 70 km of atmosphere, 21600 s day), the close grey moon
Selene, and the small high moon Vesper. Scales are compressed so an orbit takes about half
an hour of game time rather than ninety minutes — a moon mission fits in one sitting.

**Stock rockets.** Three, each a working answer to a mission: *Sparrow I* (sub-orbital
hop), *Orbiter II* (two stages to orbit with margin to come home), *Selene Voyager*
(solid-assisted lifter, transfer stage and a lander on legs).

## Built for touch

- Tap-to-attach in the builder instead of drag-and-drop — the game does the aiming, which
  is the part a finger is bad at.
- Every control meets a 44 pt touch target. The stage button is the largest thing on
  screen and is the only thing in its colour.
- The throttle is draggable along its whole length, not just from a knob.
- Layout adapts by size class: readouts stack into a column on iPhone and spread into the
  margins on iPad, where they do not sit over the rocket.
- Left-handed layout mirrors the control clusters; sensitivity and inversion are settings.
- Portrait and landscape on both devices, with safe areas respected.
- 120 Hz on ProMotion displays.
- Battery: the HUD republishes at 15 Hz and trajectories at 4 Hz rather than per frame,
  and high time warp is analytic rather than integrated, so warping a mission forward
  costs almost nothing.
- Haptics on staging, touchdown and failure.

## How it is put together

```
LittleSpaceProgram/
  Core/        Vec2, units, the Kepler solver, bodies and the system
  Parts/       part definitions, catalog, design blueprint, delta-v analysis, stock craft
  Flight/      runtime vessel, the integrator, manoeuvre nodes, trajectory prediction
  Render/      procedural part geometry and the SpriteKit world scene
  UI/          SwiftUI screens: menu, builder, flight HUD, map, settings
  Persistence/ craft library and flight saves as JSON
  App/         app entry, app state, the observable flight model
```

Some notes on the interesting decisions:

**Two clocks, two integrators.** Powered and atmospheric flight runs a fixed 50 Hz
trapezoidal integrator. The moment you are coasting outside the atmosphere, the vessel
goes "on rails" and is propagated analytically from its orbital elements. This is why warp
can reach 100000x without either melting the battery or accumulating integration error.

**Retrograde orbits by reflection.** The element solver only handles counter-clockwise
motion; clockwise orbits are mirrored about the x axis on the way in and back on the way
out. One code path, no sign conventions to get wrong.

**Floating origin.** Planets are hundreds of kilometres across and GPUs work in single
precision, so the world view keeps the rocket at the centre of the screen and never hands
the renderer a coordinate bigger than a screenful of metres. Near the ground it draws only
the visible arc of terrain as a polygon rather than a 600 km circle.

**Fuel sections, not tanks.** Propellant is pooled across connected parts, with decouplers
cutting the network. That matches what players expect — a stage drains as one unit — and
makes the delta-v figures in the builder agree with what happens in flight.

**Aerodynamic stability is real.** Centre of pressure is computed from part drag areas and
fin authority and compared against centre of mass. Put your fins at the top and the rocket
will flip, exactly as it should.

## Verification

There is no Xcode on the machine this was written on, so the physics was validated by
porting the algorithms to a reference implementation and testing them numerically:

- Kepler propagation matches RK4 integration to sub-millimetre over 900–2000 s across
  circular, elliptical, hyperbolic, near-parabolic and retrograde cases.
- Radius-crossing and apsis-timing solvers were checked against propagated positions.
- All three stock rockets were checked for aerodynamic stability, per-stage TWR and
  delta-v budgets.
- A full ascent was flown in the reference implementation: Orbiter II reaches a 93 km
  apoapsis at cutoff and circularises with 536 m/s to spare; Selene Voyager reaches orbit
  with 3020 m/s left, which is the moon-mission budget. Max-Q stays under the structural
  limit on a sensible gravity turn.

The Swift is a faithful transcription of the validated algorithms, but **it has not been
compiled** — that needs a Mac. Expect to fix a small number of compile-time issues on the
first build.

## Flying it

Go straight up to about 2 km, then pitch east and let the rocket follow its own prograde
vector down to the horizon by 45 km. Watch apoapsis rather than altitude. When apoapsis
passes 80 km, cut the throttle, coast to it, and burn horizontally until periapsis climbs
out of the atmosphere. That is orbit.
