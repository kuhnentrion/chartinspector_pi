# OpenCPN AppStyle v1

AppStyle v1 is the small shared UI language used by Chart Inspector and intended for reuse by other OpenCPN plugins.

The goal is not to replace native platform chrome. It is to make plugin content faster to scan underway, consistent between plugins, and compatible with OpenCPN Day/Dusk/Night modes.

## Principles

1. Navigation information first. Technical/source metadata is secondary and optional.
2. Preserve native window chrome and platform behaviour.
3. Use a small number of reusable components rather than per-dialog styling.
4. Derive UI colours from OpenCPN's active Day/Dusk/Night palette.
5. Reserve cyan for interaction/selection rather than decoration.
6. Prefer whitespace, alignment and hierarchy over borders and visual effects.

## Layout tokens

| Token | Value |
| --- | ---: |
| XS spacing | 4 px |
| Small spacing | 8 px |
| Medium spacing | 12 px |
| Large spacing | 16 px |
| XL spacing | 24 px |
| Card radius | 10 px |
| Card padding | 12 px |
| Property label column | 112 px |
| Colour chip | 16 px |

## Typography

Use the platform/OpenCPN system font. Do not bundle a custom font.

- Title: base size + 2 pt, bold
- Primary navigation value: base size + 1 pt, bold
- Property labels: base size, normal weight
- Property values: base size, normal weight
- Technical metadata: base size - 1 pt, secondary colour

## Semantic colours

Components use semantic tokens rather than fixed UI colours:

- `windowBackground`
- `cardBackground`
- `cardBorder`
- `textPrimary`
- `textSecondary`
- `accent`

The palette is derived from OpenCPN colours (`DILG0`, `DILG3`, `DILG4`) for the active Day/Dusk/Night scheme.

S-57 navigation colours remain true object colours and are not replaced by AppStyle accent colours.

## Core components

### Rounded card

A lightly separated card with a 10 px radius and 12 px internal padding. It groups related navigation properties without looking like a form or debug table.

### Property row

Two-column layout:

`Label | Value`

Labels guide scanning but do not compete with values. Long values may wrap in the value column.

### Colour chip

A 16 px colour sample shown before the decoded colour name. Multiple S-57 colours are shown as multiple chips.

### Technical footer

Optional, visually secondary information for S-57 class, geometry, SCAMIN and source/debug information. It is not part of the primary navigation card.

## Reference behaviour: Chart Inspector

The object name/type is the window content heading. A safety-critical primary value such as depth or vertical clearance is promoted directly beneath it. The card contains only navigation-relevant properties such as category, status, colour, light characteristic, range and restrictions.

Examples:

```text
Underwater rock / awash rock
Depth: 0.9 m

[ Water level effect | Always under water/submerged ]
```

```text
Buoy, safe water

[ Name           | No 5                    ]
[ Color          | [red][white] Red, White ]
[ Colour pattern | Vertical stripes        ]
[ Light          | [white] LFl W 10 s      ]
```

## Reuse

For another plugin, copy or share the `src/ui/app_style.*` and `src/ui/rounded_panel.*` components rather than recreating local constants. New shared components should only be added when at least two real plugin screens need them.

This is intentionally a small v1 design system. Stability and consistency are more important than adding many components.
