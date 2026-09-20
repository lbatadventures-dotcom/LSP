# Web builds

Two self-contained HTML files, no build step and no bitmap art.

- **`index.html`** — the 3D build, designed for landscape. WebGL via three.js
  (loaded from a CDN); everything else is in the file.
- **`flat.html`** — the earlier 2D canvas build, kept because it needs no WebGL
  and is a clearer read of the same simulation.

Both are ports of the native simulation rather than rewrites: the same fixed-step
integrator, the same fuel network and the same part numbers, so a rocket that
reaches orbit in one reaches orbit in the others.

## What the 3D build adds

- **Orbits with inclination.** The perifocal Kepler solution is unchanged — it is the
  same validated in-plane maths — and is rotated into the inertial frame by the
  classical elements (i, RAAN, argument of periapsis) derived from the angular
  momentum and node vectors. Checked against RK4 to sub-millimetre across
  equatorial, polar, inclined, retrograde and hyperbolic cases.
- **Quaternion attitude** with three-axis control: pitch, yaw and roll, with angular
  rates carried in the body frame and SAS holds driving a PD controller on the
  axis-angle error.
- **A real planet**: an equirectangular surface generated from 3D value noise, a
  separate drifting cloud sheet, and a rim-lit atmosphere shell.
- **Local terrain patches.** A 600 km sphere cannot show ground detail at a rocket's
  scale, so near the surface the game builds a displaced grid around the vessel and
  tapers it back into the sphere's mean radius at its edge, leaving no seam.
- **Landscape-first layout**: instruments live in the left and right margins where
  thumbs already are, with a portrait prompt that can be dismissed.

## A note on scale

Render units are kilometres and the vessel sits at the origin — a floating origin.
A 600 km planet and a 12 m rocket span ten orders of magnitude, which no single
depth buffer handles, so the renderer runs a logarithmic depth buffer. Kilometres
rather than metres keeps float32 vertex precision near the surface at a few
centimetres.
