# Upstream plan: generic vector-object query API

This document separates the OpenCPN core proposal from Chart Inspector UI policy and provider-specific implementation details.

## Goal

Expose a small, bounded, read-only way for plugins to ask which vector-chart objects are present at or near a geographic position and receive copied geometry and chart attributes.

Chart Inspector is the reference implementation, but the API must remain useful for other plugins.

## Repository split

### OpenCPN/OpenCPN

Generic core/API change only:

- versioned POD query/result structures;
- exported `QueryVectorChartObjectsV1` entry point;
- native vector-chart adapter;
- provider dispatch through the chart abstraction;
- validation and safety limits;
- API lifetime/error documentation.

No Chart Inspector selection or UI policy belongs in core.

### bdbcat/o-charts_pi

Separate provider implementation:

- opt in to the generic query interface;
- reuse existing eSENC object/geometry machinery;
- copy feature class, object name, geometry and attributes into callback-lifetime POD buffers;
- never expose internal S-57/render pointers;
- preserve OpenCPN/o-charts portrayal visibility decisions.

### kuhnentrion/chartinspector_pi

Consumer/reference implementation:

- call `QueryVectorChartObjectsV1`;
- copy callback data immediately;
- perform screen-space Point/Line/Area hit testing and ranking;
- retain S-57 catalogue decoding and navigation-first presentation;
- keep selectable feature-class policy entirely inside the plugin.

## Proposed v1 scope

Keep the first upstream proposal deliberately small:

- read-only query;
- geographic position plus pixel/search radius;
- Point / Line / Area geometry mask;
- bounded maximum number of returned objects;
- bounded maximum points per object;
- feature class, object name and raw attributes;
- complete object geometry represented as POD points/parts;
- callback-based result delivery;
- native vector charts and plugin-provided vector charts through the chart abstraction;
- no wxWidgets/STL ownership crossing the plugin ABI boundary.

## Explicitly out of scope for the first PR

Do **not** require the experimental behaviour used while developing Chart Inspector:

- selecting objects hidden only by SCAMIN;
- preferring a more detailed inactive chart cell;
- loading charts during a query;
- overriding display category or NoShow settings;
- Chart Inspector feature-class filtering;
- navigation-specific ranking or presentation;
- provider-specific chart-file parsing in OpenCPN core.

These can be added later as compatible flags only if broader plugin use cases justify them.

## Behaviour principle

The first version should follow one simple rule:

> Query objects from the currently relevant vector-chart context while preserving normal OpenCPN portrayal and visibility decisions.

The API reports chart objects. It does not change portrayal, decide navigation importance, or resurrect objects hidden by user display settings.

## Why this is generic

Potential consumers include:

- contextual chart inspectors;
- direct feature context menus;
- route/object analysis tools;
- accessibility and navigation-assistance tools;
- chart QA/debugging utilities;
- training and educational plugins.

## ABI principles

1. Versioned structures carry `struct_size`.
2. Query/result data is plain C-compatible POD.
3. Provider-owned pointers are valid only during the callback.
4. Consumers copy data they need to retain.
5. Existing providers remain compatible when they do not implement the new interface.
6. `true` with zero callbacks means a supported query with no matching objects; `false` means unsupported/error.
7. All array/object counts are bounded and validated by the host.

## Upstream acceptance criteria

The OpenCPN patch is ready to propose when:

1. Current OpenCPN builds and behaves unchanged when no new provider support is present.
2. Existing chart providers continue to load without recompilation where ABI rules require it.
3. Native vector charts return Point, Line and Area objects with attributes.
4. Multipart line/area geometry is complete.
5. Malformed provider results cannot crash the host/consumer path.
6. No provider-owned pointer survives a callback.
7. No STL/wx ownership crosses the provider ABI.
8. The API contains no Chart Inspector UI/selection policy.
9. Public documentation specifies lifetime, geometry and error semantics.
10. A minimal consumer plus Chart Inspector validate the same API.

## Target OpenCPN diff

The current local prototype modifies only two OpenCPN files but contains additional experiments. Before submission, rebuild the branch from current upstream and reapply only the v1 slice.

Target content:

1. ABI-safe POD declarations in `include/ocpn_plugin.h`;
2. exported host query/dispatch in the plugin host implementation;
3. native vector geometry extraction required by the generic host path;
4. no SCAMIN/detailed-chart/Chart-Inspector policy.

Provider changes such as o-charts are reviewed separately.

## Test matrix

| Source | Point | Line | Area | Attributes | Multipart |
|---|---|---|---|---|---|
| Native vector chart | required | required | required | required | required |
| o-charts/eSENC | required | required | required | required | required |
| Unsupported plugin chart | false | false | false | n/a | n/a |

For supported sources, compare candidate identity and raw attributes with OpenCPN's existing Object Query at the same geographic position.

## Suggested upstream PR title

`Add read-only vector chart object query API for plugins`

## Suggested PR summary

OpenCPN plugins currently have no provider-independent public API to identify the vector-chart feature at a geographic position and retrieve its geometry and attributes. This change exposes a bounded, callback-based read-only query through the chart abstraction. It does not alter chart portrayal or load charts. Chart Inspector is provided separately as a reference consumer.

## Community framing

Lead with the missing generic capability, not the plugin-specific request. Chart Inspector is the proof that the API enables a useful interaction:

- hover a chart feature;
- highlight the exact point, full line or full area boundary;
- show a concise navigation-oriented description.

Possible broader uses: chart inspection, context menus, route/object analysis, accessibility/navigation assistance and chart QA.

## Before uploading to OpenCPN

- Start from a clean, current OpenCPN upstream branch.
- Reapply only the minimal v1 API pieces.
- Remove `INCLUDE_NON_RENDERED` and detailed-chart fallback behaviour from the first proposal.
- Build OpenCPN Release.
- Verify exported host symbol.
- Test native vector charts with a minimal consumer and Chart Inspector.
- Record exact diffstat and changed files.
- Run formatting/lint/tests expected by OpenCPN.
- Prepare one concise screenshot/GIF as motivation.
- Submit o-charts provider support separately.
