# Chart Inspector

Chart Inspector is an OpenCPN plugin for direct, readable inspection of vector chart objects.

Move the pointer over a chart feature and Chart Inspector highlights the selected object on the chart and shows the information which matters for navigation: object type, depth or clearance, category, colour, light characteristic, range, restrictions and other relevant attributes.

> **Status:** 0.3.0 preview. The plugin is functional and currently being tested with vector charts and o-charts. It depends on an experimental read-only vector-object query extension which is being prepared as a generic OpenCPN API proposal.

## Why

Vector charts contain much more information than can be displayed at once. OpenCPN can expose these attributes through its existing object-query workflow, but identifying the exact feature under the pointer can be slower than necessary.

Chart Inspector is intended to answer a simple question quickly:

> **What is that on my chart?**

## Current features

- Live hover selection of vector chart features.
- Cyan overlay highlighting without changing official chart symbology.
- Full line and area boundary highlighting.
- Compact floating information window which follows the selected chart object.
- Navigation-first presentation of S-57 attributes.
- Decoded object categories, colours and light information.
- S-57 colour chips for aids to navigation.
- Associated light information for buoys and beacons where available.
- Object-class filtering in plugin preferences.
- Natural/background chart geometry is excluded from the default selectable profile.
- Optional technical footer for S-57 class, geometry, SCAMIN and related metadata.
- Day/Dusk/Night-aware UI styling.

## Interaction

1. Move the pointer over a selectable vector feature.
2. The most relevant object near the pointer is highlighted.
3. Chart Inspector shows a concise navigation-oriented description.
4. Technical chart metadata can optionally be enabled in Preferences.

Examples of the intended presentation:

```text
Underwater rock / awash rock
Depth: 0.9 m

Water level effect     Always under water/submerged
```

```text
Buoy, safe water

Name                   No 5
Color                  [red] [white]  Red, White
Colour pattern         Vertical stripes
Light                  [white] LFl W 10 s
```

## Architecture

Chart Inspector remains a normal OpenCPN plugin. It does not parse proprietary chart files itself and does not modify chart portrayal.

```text
OpenCPN chart canvas
        |
        | pointer position
        v
Chart Inspector
        |
        | bounded, read-only vector object query
        v
OpenCPN chart abstraction
        |
        +-- native vector charts
        +-- plugin-provided vector charts
```

The proposed OpenCPN interface is intentionally generic. Chart Inspector is one reference use case; the same API could support contextual chart tools, route/object analysis, accessibility tools and other navigation plugins.

## Selection policy

The default profile focuses on visible physical, man-made and navigation-relevant objects such as buoys, beacons, lights, wrecks, landmarks, bridges and cables.

Background/natural chart geometry such as coastlines, depth areas and seabed polygons is not selected by default. Exact feature classes can be changed in Preferences.

OpenCPN portrayal controls remain authoritative. The plugin is not intended to resurrect objects explicitly hidden by the user's display settings.

## UI / AppStyle

Chart Inspector is also the reference implementation for a small reusable OpenCPN plugin UI language called **AppStyle v1**.

It uses:

- native platform fonts and window chrome;
- a 4 / 8 / 12 / 16 / 24 px spacing system;
- navigation-first information hierarchy;
- rounded property cards;
- semantic Day/Dusk/Night colours derived from OpenCPN;
- true S-57 navigation colours for chart-object colour chips.

See `docs/app-style-v1.md`.

## Development principles

- Provider-independent wherever possible.
- Read-only access to chart features.
- Preserve official chart symbology.
- Keep pointer-hover queries bounded and fast.
- Prefer small generic OpenCPN API improvements over provider-specific workarounds.
- Present navigation information before technical metadata.

## Building

The preview currently builds against OpenCPN plugin API 1.18 and wxWidgets. The experimental vector-object query host/provider changes are not yet part of upstream OpenCPN, so a matching development build is currently required.

## Roadmap

- [x] Canvas mouse interaction.
- [x] Vector-object hover highlighting.
- [x] Point, line and area geometry highlighting.
- [x] Compact navigation-first information window.
- [x] S-57 attribute decoding and colour chips.
- [x] Selectable feature-class preferences.
- [x] Shared AppStyle v1 foundation.
- [ ] Reduce and submit the generic OpenCPN vector-object query API upstream.
- [ ] Submit matching provider support where required.
- [ ] Test on additional platforms and chart providers.
- [ ] Package the first public preview through the normal OpenCPN plugin distribution workflow.

## Contributing

Testing with different vector chart sources and platforms is especially useful. Reports about wrong object selection, incomplete geometry, missing navigation attributes or UI issues in Day/Dusk/Night modes are welcome.

## License

GPL-2.0-or-later. See `LICENSE`.
