# Web build

`index.html` is a self-contained browser port of the game — open it in any browser, or
publish it as a Claude Artifact. No build step, no dependencies, no bitmap art.

It is a port of the native simulation, not a rewrite: the same Kepler solver (including
the retrograde-by-reflection trick), the same fixed-step integrator, the same fuel
network and the same part numbers, so a rocket that reaches orbit here reaches orbit in
the Swift app.

What made the crossing:
- flight with throttle, rotation, staging, SAS holds and on-rails time warp
- atmospheric drag, aerodynamic stability, parachutes and re-entry
- the map view with the conic, apsis markers and Selene's sphere of influence
- the visual mods: scattering sky, cloud layer, pressure-driven plumes, reentry plasma,
  the textured planet with terminator and limb, and distant-object flares

What did not: the parts builder. The web build ships the three stock rockets instead.
