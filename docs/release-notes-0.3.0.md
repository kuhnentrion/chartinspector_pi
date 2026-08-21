# Chart Inspector 0.3.0 Preview

Chart Inspector 0.3.0 is the first functional preview of direct vector-chart inspection for OpenCPN.

The interaction is intentionally simple: move the pointer over a selectable chart feature, see the exact feature highlighted on the chart, and get a compact navigation-oriented explanation in a floating window.

## Highlights

- Live hover selection of vector chart objects.
- Cyan overlay highlighting for points, complete lines and complete area boundaries.
- Navigation-first information layout instead of a raw S-57 attribute dump.
- Prominent depth and clearance values where available.
- Decoded categories, status, restrictions and light information.
- S-57 colour chips with readable colour names.
- Associated light information for buoys and beacons.
- Configurable selectable feature classes.
- Natural/background geometry excluded from the default profile.
- Optional technical footer for S-57 class, geometry and portrayal metadata.
- Day/Dusk/Night-aware AppStyle v1 UI foundation.

## Example answers

Chart Inspector is designed to answer questions such as:

- What is this buoy and what colour is it?
- What is the light characteristic and nominal range?
- How deep is the underwater rock?
- What restriction applies to this area?
- What is this beacon, landmark, wreck, bridge or cable?

## Current development dependency

The preview depends on an experimental read-only vector-object query extension to OpenCPN and matching support from vector-chart providers. These changes are not upstream yet.

The OpenCPN change is being prepared separately as a small generic plugin API proposal. Chart Inspector is the reference implementation, not a special case in the API.

## Tested development setup

The current preview has been built and exercised on Windows with:

- OpenCPN development build
- OpenCPN plugin API 1.18
- wxWidgets 3.2.x
- o-charts vector charts
- MSVC / Windows SDK build

Additional platform and chart-provider testing is still required.

## Known preview limitations

- The generic vector-object query API is not yet available in upstream OpenCPN.
- Provider support is currently development-only.
- Some S-57 wording can still be improved for concise navigation presentation.
- User depth-unit integration is not final; S-57 depth values currently use the preview's available formatting path.
- Packaging through the normal OpenCPN plugin catalog has not started yet.

## AppStyle v1

This preview also establishes the first version of a reusable UI language for our OpenCPN plugins: native platform chrome, shared spacing and typography, rounded navigation-property cards, semantic Day/Dusk/Night colours and true S-57 colour chips.

See `docs/app-style-v1.md`.
