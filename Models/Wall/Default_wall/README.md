# Default wall — Godot-ready asset

- `Wall_game_ready.glb` is the runtime version; it keeps the original geometry/material accents, applies `albedo.png` to the stone surfaces, and embeds the texture so it cannot go missing on import.
- The runtime export is joined from 75 source mesh objects / 118 primitives into 4 mesh objects / 4 primitives. It retains all 15,479 triangles and the original bounds (about 6.42 × 6.00 × 1.20 Godot units). The resulting GLB is about 1.51 MB, including the texture; the original GLB plus separate albedo is about 2.13 MB.
- `Wall.tscn` is a reusable `StaticBody3D` scene with the runtime visual, ground-level origin, and a single approximate box collider (6.42 × 6.00 × 0.75). The visual is shifted so the broad wall plane is centered around the root's Z=0 plane. The box is intentionally simple and efficient; replace it with a more specific collider if this wall later needs openings or walkable cutouts.
- `Wall.blend`, `Wall.fbx`, `Wall.glb`, `Wall_optimised.blend`, `Wall_optimised.fbx`, `Wall_other_optimised.blend`, and `albedo.png` are kept as editable/source exports. The source GLB and FBX were not overwritten.

`Wall.tscn` is now instanced in `main.tscn` at the existing test-map wall location. To reuse it elsewhere, instance `Wall.tscn` as a PackedScene. Godot will generate the import cache for `Wall_game_ready.glb` when the project is opened in the editor.
