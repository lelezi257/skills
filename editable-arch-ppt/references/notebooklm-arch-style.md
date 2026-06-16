# NotebookLM-like editable architecture style

Use this as the default style guide for `editable-arch-ppt`.

## Visual tone

- Clean technical diagram, soft pastel layer boxes, clear module hierarchy.
- Enough whitespace for routing corridors; avoid dense spaghetti lines.
- One slide = one architectural claim.
- Title should be a conclusion, not just a noun.
- Use small callouts for caveats instead of long paragraphs.

## Layout heuristics

For runtime/deployment diagrams:

```text
[Client] -> [Ingress/App Layer] -> [Platform Control Plane]
                         \-> [Worker Node / Pod / Sandbox]
[right side: stores + K8s API + legend]
[bottom: boundary/takeaway callout]
```

Keep these corridors empty when possible:

- Left vertical corridor for client ingress.
- Middle horizontal corridor between control-plane and worker-node areas.
- Bottom return/streaming corridor.
- Right vertical corridor for storage/K8s API references.

## Connector clearance

Readable diagrams need line gutters, not just non-overlap.

- Minimum clearance from a module border: `0.18in`.
- Preferred clearance for major flows: `0.25-0.35in`.
- Endpoints may attach to a module border, but the connector body must not run along that border.
- Connect to component borders or external ports, not to the visual center of a labeled component.
- Never let a connector cross over component text.
- Do not route a horizontal segment on the same y as a module's top/bottom edge while overlapping the module width.
- Do not route a vertical segment on the same x as a module's left/right edge while overlapping the module height.
- Only the final source/target contact point may touch a module border.
- If a flow would need to hug a box, add an external port/pin or reroute through an outer corridor.
- If the slide is too dense, remove lower-value arrows or split the slide; do not sacrifice gutters first.

Bad:

```text
[Module]──────  line glued to bottom edge
```

Also bad:

```text
┌────────┐
│Module  │
└────────┘────────→   connector body continues on the same y as the box edge
```

Good:

```text
[Module]

─────────────  line in its own corridor
```

Even better for an exit route:

```text
┌────────┐
│Module  │
└───┬────┘
    │ short perpendicular stub
    └────────→ corridor separated from the box edge
```

## Flow semantics

- Data path: thick purple, solid, arrowed. It should not traverse controller/CRD/state boxes unless those boxes truly proxy data.
- Control path: blue, dashed, arrowed. It may go through API/controller/state components.
- Runtime path: orange, solid, short local arrows.
- Config/declaration: thin dashed blue/gray. Config resources describe what can run; they usually do not carry request data.

## Common mistakes to avoid

- Drawing every relationship as one connected chain.
- Letting request data pass through CRDs, templates, or controllers.
- Using a flat image as the slide.
- Using straight line segments for main paths when PowerPoint elbow connectors are expected.
- Leaving an arrow disconnected from source/target.
- Letting arrows visually stick to component borders; this is almost as unreadable as crossing the component.
- Creating a legend style that does not appear in the slide.
- Inventing acronyms or component names not present in evidence.

## Engineering-whiteboard profile

Use this profile for slides like `sandbox.pptx`:

- White canvas, not a colored poster.
- Thin gray component boxes; black/gray lines by default.
- One muted highlight color per concept area, not a full semantic palette.
- Right-side notes explain tradeoffs; the diagram stays sparse.
- Step numbers explain flows; arrows do not need to encode every semantic category.
- Draw key paths only. Leave implied containment and adjacency unconnected.
- Prefer large whitespace and simple rectangles over cards, pills, shadows, or heavy legends.
- Keep text readable: component labels should normally be 8.5-10pt, note text 8.5-10pt, section headers 10-12pt.
- For deployment/architecture pages, keep the real topology detail. Do not oversimplify into generic step cards when the value of the page is the component map.

### Lessons from AX sandbox-style v7

The best iteration followed these rules:

1. **Increase font before adding more boxes.** If a slide feels crowded at readable font sizes, shorten labels or split detail into note boxes.
2. **Reserve panel header space.** Section titles like "Before" / "After" need their own band; child components start lower, not immediately under the title.
3. **Connect via edges and buses.** For abstraction maps, arrange components in left/right columns and connect box edges to a vertical bus. The bus connects to the hub. This prevents lines from crossing neighboring components.
4. **Never run a line through another component just to reach the hub.** Move components or use a bus/orthogonal route.
5. **Deployment slides are allowed to be detailed.** Keep real component topology (router, resolver, control plane, worker pod, runtime helpers) but draw only the key request/control/runtime paths.
6. **Notes carry explanation.** Component boxes carry names; note boxes carry interpretation, risks, and boundaries.
