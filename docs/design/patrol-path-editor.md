# Design note: authoring sentry patrol paths in the editor

Issue: #9. Status: implemented.

## Problem

A sentry finds its path through a group name. `sentry.gd` calls
`get_tree().get_first_node_in_group(path_group_name)` and walks that node's
children, which are `Marker2D`s carrying `Waypoint2D.gd`. To author a path you
type a group name on the sentry, put the same group on a `Node2D`, add markers
by hand, and type coordinates. Nothing draws the route, so you can't see it
until you run the game. The link between a sentry and its path is a string
that nothing checks.

## Decision

Make one node, **`PatrolPath2D`**, the patrol path. Its children are the
waypoints, and a small editor plugin edits it in the 2D viewport.

```
Level
├── Paths
│   └── Paths_1  (PatrolPath2D, mode = LOOP)
│       ├── Point1  (Waypoint2D: action, wait_time, facing_direction)
│       └── Point2  (Waypoint2D)
└── Sentry  (patrol_path → ../Paths/Paths_1)
```

### Runtime: `assets/scripts/patrol_path_2d.gd`

The runtime class lives in `assets/scripts`, not in the addon, so the game
works even with the editor plugin turned off. Its interface is small:

- `mode`: `LOOP` (0 → n−1 → 0, as sentries walk today) or `PING_PONG`
  (0 → n−1 → 0 by retracing, without visiting an end point twice).
- `get_waypoints() -> Array[Waypoint2D]`: the waypoints in child order.
- `next(index, step) -> Vector2i`: the waypoint after `index` when moving in
  direction `step` (±1), returned as `(next_index, next_step)`. All the
  loop and ping-pong rules sit behind this one call, so a sentry keeps two
  integers and knows nothing about modes.

The sentry gets `@export var patrol_path: PatrolPath2D`, which replaces
`path_group_name`. The link is now a NodePath that the inspector shows and
lets you pick, and Godot keeps it valid when nodes are renamed or moved.

`Waypoint2D` stays the per-waypoint data holder (`action`, `wait_time`,
`facing_direction`), which you edit in the inspector. It becomes `@tool`
and gets a `class_name` so that it can tell its path to redraw whenever it
moves.

### Editor: `addons/patrol_path_editor/`

`PatrolPath2D` is `@tool`. In the editor only, it draws its route: segments,
direction arrows, the closing segment for `LOOP`, and a ring on every
waypoint that waits. This preview is always visible in the edited scene,
selected or not, so you can see every sentry's route together.

The plugin runs when a `PatrolPath2D`, or one of its waypoints, is selected:

| Input | Effect |
|---|---|
| Drag a handle | Moves the waypoint, snapped to the path's grid |
| Ctrl + click | Adds a waypoint. Near a segment it is inserted there, otherwise it is appended at the end |
| Right-click a handle | Removes the waypoint |

Every change goes through `EditorUndoRedoManager`. Handles are numbered in
patrol order and drawn in screen space, so they stay the same size at any zoom.

Snapping uses `snap_step` on the path, `Vector2(8, 8)` by default, in global
coordinates. The castle tiles are 16 px, so an 8 px step reaches both tile
corners and tile centres, which matches every coordinate already in the
levels. Snapping only applies while you drag or add a waypoint. Loading a
scene never moves an existing waypoint. Set `snap_step` to `(0, 0)` to turn
snapping off.

## Rejected alternatives

- **Built-in `Path2D` / `Curve2D`.** Its point editor already exists, but a
  curve point can't carry `action` / `wait_time` / `facing_direction`. Keeping
  that data in parallel arrays would break as soon as a point is inserted.
  Child nodes keep each waypoint's data next to its position.
- **A dock panel or table of coordinates.** Still edits numbers rather than
  positions on the map.
- **NavigationAgent pathing between waypoints.** That changes behaviour.
  Sentries move in straight lines today, and #9 requires behaviour to stay
  the same.

## Migration

Every level (`main.tscn`, `level_2.tscn`, `level_3.tscn`) is converted the
same way:

1. Attach `patrol_path_2d.gd` to each `Paths_N` node, with `mode = LOOP`.
2. Remove the `SentryN` group from those nodes, and set each sentry's
   `patrol_path` to its path. In a hand-edited `.tscn`, the sentry's node
   header also needs `node_paths=PackedStringArray("patrol_path")`. Without
   it, the NodePath is never resolved to the node and `patrol_path` stays
   null at runtime. The inspector adds it for you.
3. Leave every waypoint where it is: same names, same positions, same data.

`LOOP` with unchanged waypoints walks exactly the index sequence that the old
`(i + 1) % size` did, so behaviour is unchanged. The `Sentry1` / `Sentry2`
global groups are dropped from `project.godot`, since no sentry looks them up
any more. `priest.gd` still uses its own group lookup. No level uses a priest,
so it is out of scope here.
