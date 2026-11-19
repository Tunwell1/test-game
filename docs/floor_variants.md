# Floor comparisons

Run `main.tscn`, then press **F1–F7** to compare the seven warm-wood floor layouts in place. Only the selected floor is loaded at a time. Each pattern is generated in one quadrant and mirrored into all four quadrants, so the room stays symmetric while the board sizes, cuts, and grain directions vary in a controlled way.

The default is F1. The oak perimeter band and collision-safe underlay are shared across all candidates.

## Статус в основной ветке

Семь вариантов — это сравнение макетов пола с ветки `e4ac0e56`. В основной
ветке выбран другой пол: 16 модульных шашек (`Models/Floor/Wood_Floor_Module_*`)
плюс сгенерированные `Wood_Floor.glb` / `_Corner` / `_Edge`, и они согласованы
с `main.tscn` и `tests/test_wood_floor.py`.

`floor_variant_selector.gd` и `Models/Floor/Wood_Floor_Variant_*.glb` оставлены
в репозитории как готовые кандидаты, но **не подключены** к сцене:

- F1–F7 конфликтуют с управлением: `F3` в `hud.gd` включает режим отладки
  (время/магия), поэтому вешать на него выбор пола нельзя;
- подмена пола на ходу требовала бы убирать `WoodFloor` с модульными шашками.

Чтобы посмотреть варианты, добавьте в `main.tscn` узел с этим скриптом
вручную; сначала переназначьте хоткеи на свободные клавиши.
