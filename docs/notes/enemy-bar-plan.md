# Полоски здоровья врагов на базе StatBar — дизайн-заметка

> Рабочая заметка для реализации (после — удалить). Составлена 2026-11-14 по текущему
> состоянию `master`. Правки игровых скриптов в рамках самой заметки не делались.
> Параллельный рефакторинг паузы трогает `hud.gd`, `pause_menu.gd`, `player.gd`
> и создаёт `pause_controller.gd` — эти файлы в плане не редактируются (только читаются).

## 1. Резюме

Выбран **вариант (a): экранный оверлей** — новый узел `EnemyHealthOverlay` (CanvasLayer),
который каждый кадр проецирует точку над головой врага через `Camera3D.unproject_position`
и показывает над ней готовый `StatBar`. В `enemy.gd` добавляется один сигнал
`health_changed` (по образцу `player.gd:8`), `StatBar` остаётся без обязательных правок.
Вариант (b) — SubViewport-биллборд на каждого врага — отвергнут из-за цены кадра
(N рендер-таргетов) и деградации читаемости с расстоянием.

## 2. Факты (проверяемые)

### 2.1. enemy.gd — здоровье, урон, смерть

Файл: `enemy.gd`, `class_name Enemy extends CharacterBody3D` (строки 1–2).

| Что | Имя | Где | Комментарий |
|---|---|---|---|
| Сигнал смерти | `died` | `enemy.gd:8` | единственный сигнал о судьбе врага |
| Сигнал смены состояния | `state_changed(state: State)` | `enemy.gd:9` | ИИ-состояния, не HP |
| Перечисление состояний | `enum State { PATROL, SUSPICIOUS, CHASE, SEARCH, DEAD }` | `enemy.gd:11` | `DEAD` — терминальное |
| Максимум HP | `@export var health_max: float = 60.0` | `enemy.gd:14` | |
| Текущее HP | `var health: float = 0.0` | `enemy.gd:41` | в `_ready()` присваивается `health = health_max` (`enemy.gd:58`) |
| Урон | `func take_damage(amount: float)` | `enemy.gd:257` | см. ниже |
| Смерть | `func _die()` | `enemy.gd:293` | приватный, вызывается из `take_damage` |
| Горение | `func _tick_burn(delta)` | `enemy.gd:281` | `take_damage(6.0 * delta)` каждый кадр (`enemy.gd:284`) |

Тело `take_damage` (`enemy.gd:257–269`):

```gdscript
func take_damage(amount: float) -> void:
	if state == State.DEAD:
		return
	health -= amount                # enemy.gd:260
	awareness = 1.0                 # мгновенная агрессия
	...
	if health <= 0.0:
		_die()                      # enemy.gd:268-269
```

Тело `_die()` (`enemy.gd:293–301`):

```gdscript
func _die() -> void:
	state = State.DEAD              # enemy.gd:294
	died.emit()                     # enemy.gd:295
	_indicator.text = ""            # enemy.gd:296
	collision_layer = 0             # enemy.gd:297
	var tw := create_tween()
	tw.tween_property(self, "rotation:x", deg_to_rad(-90), 0.4)  # падение
	tw.tween_interval(3.0)          # тело лежит ~3 с
	tw.tween_callback(queue_free)   # enemy.gd:301
```

Ключевые следствия:

- **Сигнала `health_changed`/`damaged` у врага НЕТ** — изменение HP сегодня никому не
  сообщается; наблюдателю остаётся поллить `health` или добавить сигнал (что и делаем).
- **Публичного `die()` нет** — есть приватный `_die()`; для оверлея достаточно
  существующего сигнала `died` (`enemy.gd:8`, эмит в `enemy.gd:295`).
- Урон от горения идёт через тот же `take_damage` (`enemy.gd:284`) → один новый сигнал
  в `take_damage` автоматически покроет и снаряды, и DoT.
- После смерти враг **живёт в дереве ещё ~3,4 с** (твин 0,4 с + интервал 3,0 с,
  `enemy.gd:299–301`), при этом `rotation.x` уходит в −90° — точка «над головой»
  съезжает. Оверлей не должен трекать падающее тело.
- `_physics_process` при `DEAD` выходит сразу (`enemy.gd:101–102`) — враг замирает.

### 2.2. spell_projectile.gd — как снаряд находит и бьёт врагов

Файл: `spell_projectile.gd`, `class_name SpellProjectile extends Area3D` (строки 1–2),
создаётся кодом в `SpellCaster.cast()` и добавляется в корень сцены
(`spell_caster.gd:100–131`).

- Снаряд — Area3D; в `_ready()` выставляется `collision_mask = 1 | 4 | 8`
  (`spell_projectile.gd:17`; комментарий там же: «Мир (1), интерактивные объекты (4),
  враги (8)») и `body_entered.connect(_on_body_entered)` (`spell_projectile.gd:18`).
- Враг попадает под бит 8, потому что `enemy.gd` ставит себе `collision_layer = 8`
  в `_ready()` (`enemy.gd:59`) и входит в группу `"enemies"` (`enemy.gd:61`).
- Попадание обрабатывается утиной типизацией, без списков врагов
  (`spell_projectile.gd:26–39`):

```gdscript
if damage > 0.0 and body.has_method("take_damage"):
	body.call("take_damage", damage)          # spell_projectile.gd:29-30
...
if effect != "" and body.has_method("on_spell_effect"):
	body.call("on_spell_effect", effect)      # spell_projectile.gd:36-37
```

То есть урон приходит в `enemy.take_damage` через физику Area3D; отдельного
«реестра врагов» в проекте нет — есть только группа `"enemies"`.

### 2.3. Точка над головой для анкора

Отдельного `Marker3DD`/анкора у врага **нет**. Есть конвенция «над головой»:

- Капсула тела: радиус 0,35, высота 1,8, коллизия поднята на `y = 0.9`
  (`enemy.gd:63–68`) → макушка на `y ≈ 1.8` от origin.
- Глаза/«нос» смотрят с `y = 1.55` (`enemy.gd:87`), `_eye_pos()` = `global_position
  + Vector3(0, 1.6, 0)` (`enemy.gd:120–121`).
- **Индикатор состояния `?`/`!` — `Label3D` на `y = 2.2`** (`enemy.gd:90–95`:
  `position.y = 2.2`, `billboard = BILLBOARD_ENABLED`, `no_depth_test = true`).
  Этот же индикатор чистится при смерти (`enemy.gd:296`).

Вывод: анкор полоски = `global_position + Vector3(0, ~2.5, 0)` — выше индикатора
`?`/`!`, чтобы не накладываться на него (индикатор занимает примерно ±0,2 м вокруг
2,2). Точное значение — визуальная настройка.

### 2.4. Сколько врагов в main.tscn

Ровно **два**: `EnemyA` (`main.tscn:59–62`, позиция `(-8, 0.1, 6)`, 2 точки патруля)
и `EnemyB` (`main.tscn:64–67`, позиция `(8, 0.1, -8)`, 3 точки патруля). Оба —
`CharacterBody3D` со скриптом `enemy.gd` (`main.tscn:61`, `main.tscn:66`).
Арена — пол 30×30 (`main.tscn` sub_resource `BoxMesh_floor`, size `(30, 1, 30)`).
Планировать стоит на «сейчас 2, в перспективе — пара десятков».

### 2.5. stat_bar.gd — что умеет и чего не хватает

Файл: `stat_bar.gd`, `class_name StatBar extends Control` (строки 1–2).
**В проекте больше нигде не инстанцируется** (поиск по `*.gd` и `*.tscn` даёт только
определение класса) — это подготовленный, но пока не подключённый переиспользуемый
компонент «для второстепенных панелей» (комментарий `stat_bar.gd:4–5`). Полосы HUD
рисуются напрямую в `hud.gd:154–169`, минуя StatBar.

Умеет:

- Публичные поля: `value`, `max_value` (`stat_bar.gd:7–8`), `color` (`:9`),
  `show_text` (`:10`), `pulse_when_low` (`:11`), `thickness` — толщина в пикселях,
  по умолчанию 3.0 (`:13`).
- `set_values(v, m)` (`stat_bar.gd:25–27`) — задать значение/максимум с клампом.
- `snap()` (`stat_bar.gd:29–32`) — мгновенно выставить `_shown = _trail = _prev =
  value`, без анимации (годится при создании полоски).
- Анимация в `_process` (`stat_bar.gd:39–51`): `_shown` экспоненциально догоняет
  `value` (rate 14, `:44`); при падении значения включается «след» с задержкой
  0,45 c (`:41–42`), затем `_trail` сползает со скоростью 35% от max в секунду
  (`:48–50`). Анимация сходится сама — останавливать не нужно.
- Отрисовка `_draw` (`stat_bar.gd:53–80`): тёмная дорожка (`:56–58`), блик сверху
  (`:57`), белый «след» (`:59–60`), градиентная заливка через
  `UiTheme.vertical_gradient` (`:34–37`, `:64–66`), световая нить по кромке
  (`:67–68`), ромбовидный наконечник `UiTheme.draw_diamond` (`:69–70`), текст справа
  `UiTheme.draw_text_right` — только при `show_text and size.y >= 18.0` (`:75`).
- `pulse_when_low` пульсирует белым при `value / max_value < 0.25` (`:62–63`) —
  для врага включается «бесплатно», без правок.
- `mouse_filter = MOUSE_FILTER_IGNORE` в `_init` (`stat_bar.gd:22–23`) — не мешает вводу.

Не хватает (для задачи полосок врага):

1. **Скрытия при полном HP и затухания** — флага нет; решается снаружи через
   `visible`/`modulate.a` у Control (обязательных правок StatBar нет).
2. **Раннего выхода в `_process`** — полоска вызывает `queue_redraw()` каждый кадр,
   даже когда `value == _shown == _trail` и она невидима (`stat_bar.gd:51`). При
   десятках полосок это холостая работа (микро-, но легко убирается — см. шаг 2).
3. **Текста на маленьких полосках** — при высоте < 18 px текст отключается сам
   (`stat_bar.gd:75`); для врага это желаемое поведение, но числовое HP тогда не
   показать вовсе (не требуется).
4. Вертикального оффсета анкора нет — не нужно: позиционирует оверлей.

### 2.6. Контекст: hud.gd, UiTheme, пауза (только чтение)

- HUD — `CanvasLayer`, ребёнок узла Player (`player.tscn:41–42`; `hud.gd:8`
  `get_parent() as Player`), `layer = 5` (`hud.gd:41`), `process_mode =
  PROCESS_MODE_ALWAYS` (`hud.gd:40`).
- Весь HUD рисуется кодом: `hud_canvas.draw.connect(_draw_hud)` (`hud.gd:45`),
  полосы ресурсов — прямо в `_draw_hud` (`hud.gd:154–169`), перерисовка каждый кадр
  (`hud.gd:478`). UiTheme — статические хелперы: шрифты (`ui_theme.gd:40–66`), текст
  (`:79–110`), `draw_diamond` (`:120–127`), `vertical_gradient` и палитра
  `HEALTH = BLOOD` (`:14–27`).
- HUD прячет отрисовку при смерти игрока и на экране выбора школы
  (`hud.gd:79–80`).
- Пауза: ESC-меню ставит `get_tree().paused = value` (`pause_menu.gd:344`, слой 10 —
  `pause_menu.gd:26`); выбор школы тоже ставит `get_tree().paused` (`hud.gd:446`).
  Узлы с `PROCESS_MODE_INHERIT` (по умолчанию) при этом замирают.
- Камера: `player.camera: Camera3D = $Head/CameraBoom/Camera3D` (`player.gd:79`),
  `current = true` (`player.tscn:36–37`); игрок в группе `"player"`
  (`player.gd:131`). Значит оверлею доступны `camera.unproject_position()` и
  `camera.is_position_behind()`; CanvasLayer живёт в том же viewport, координаты
  unproject совпадают с координатами Control.
- Образец сигнала: `signal health_changed(current: float, maximum: float)`
  (`player.gd:8`), эмитится из `take_damage` после изменения (`player.gd:228`).
- Урон заклинаний по врагу (для проверки): `fire_bolt` 20 (`spell_caster.gd:13`),
  `wind_gust` 2 (`:14`), `water_jet` 8 (`:15`), `stone_shard` 25 (`:17`); горение
  6/с на 3 с = до 18 (`enemy.gd:284` + `:275–277`). Враг: 60 HP → 3 `fire_bolt`,
  либо `stone_shard` + `fire_bolt`, либо поджечь и подождать ~10 с.

## 3. Выбор способа интеграции

Сравнение по заявленным критериям:

| Критерий | (a) оверлей в HUD-слое | (b) SubViewport + QuadMesh/Sprite3D | (c) прочее |
|---|---|---|---|
| Единый рисованный стиль | идеальный: StatBar — Control, рисуется тем же UiTheme-конвейером (`stat_bar.gd:64–70`) | тот же StatBar, но через текстуру вьюпорта: лишнее растрирование, края/гамма, возня с прозрачностью QuadMesh | рисование в `_draw_hud` без StatBar = дублирование кода + правки `hud.gd` (запрещено) |
| Цена кадра при N врагах | N × (`is_position_behind` + `unproject_position`) + N отрисовок полоски — чистая математика, при N ≤ 20 копейки | N живых SubViewport-таргетов, каждый перерисовывается каждый кадр (`stat_bar.gd:51` зовёт `queue_redraw` безусловно) + N QuadMesh в сцене | Label3D-полоска из сегментов: дёшево, но не «на базе StatBar» |
| Объём кода | ~1 новый скрипт (~120 строк) + 1 сигнал в `enemy.gd`; StatBar — 0 обязательных правок | фабрика вьюпортов на врага, материал, синхронизация размеров, пул | сопоставимо с (a), но теряется переиспользование |
| Скрытие при полном HP | `visible = false` (можно вообще не создавать полоску до первого урона) | `visible = false` у меша — тоже просто | — |
| Читаемость вдаль | константный пиксельный размер, масштаб регулируем кодом | биллборд сжимается пропорционально расстоянию — вдаль нечитаем | — |
| Пауза | `PROCESS_MODE_INHERIT` — замирает сам | аналогично | — |
| Видимость сквозь стены | показывает сквозь стены (нужен луч — опция, шаг 6) | закрывается стенами «бесплатно» (depth test) | — |

**Обоснование выбора (a).** Весь интерфейс проекта — рукописный код на CanvasLayer
через UiTheme (`hud.gd:44–45`, `pause_menu.gd` рисует так же), а StatBar — обычный
Control (`stat_bar.gd:2`), чья естественная среда — 2D-канва, поэтому вариант (a)
не только самый дешёвый, но и единственный, где переиспользование StatBar происходит
напрямую, без прослоек. Вариант (b) требует SubViewport на каждого врага (Control
иначе в 3D не показать), и поскольку `stat_bar.gd:51` безусловно зовёт `queue_redraw`
каждый кадр, N врагов превращаются в N постоянно перерисовывающихся рендер-таргетов —
заметная цена при десятках врагов, плюс QuadMesh добавляет проблемы сортировки
прозрачности, а мировая полоска сжимается с расстоянием и теряет читаемость.
Вариант (a) тратит на врага одно скалярное произведение (`is_position_behind`),
одно умножение на матрицу (`unproject_position`) и уже существующие draw-вызовы
полоски; скрытие при полном HP — это `visible = false`, а пиксельный размер не
зависит от дистанции. Единственное реальное преимущество (b) — автоматическое
закрытие стенами — для нашей задачи не критично (индикатор `?`/`!` и так рисуется
сквозь стены: `no_depth_test = true`, `enemy.gd:93`), а при необходимости тот же
эффект в (a) даёт один троттлированный луч (шаг 6).

## 4. Пошаговый план изменений

Порядок шагов подобран так, чтобы каждый давал проверяемый результат и не пересекался
с параллельным рефакторингом паузы (`hud.gd`, `pause_menu.gd`, `player.gd`,
`pause_controller.gd` не трогаем вовсе).

### Шаг 1. enemy.gd — сигнал health_changed

Добавить сигнал по образцу игрока (`player.gd:8`) и эмит в `take_damage`.
Метод `_die()` и сигнал `died` уже есть — не трогаем.

```gdscript
# рядом с died (enemy.gd:8):
signal died
signal state_changed(state: State)
signal health_changed(current: float, maximum: float)  # НОВОЕ: как player.gd:8

func take_damage(amount: float) -> void:
	if state == State.DEAD:
		return
	health -= amount
	health_changed.emit(health, health_max)  # НОВОЕ: после изменения, до проверки смерти
	awareness = 1.0
	...
```

Замечания:

- Эмит **до** проверки `health <= 0.0` — оверлей должен успеть получить последнее
  значение до прихода `died`.
- Горение (`enemy.gd:284`) и снаряды (`spell_projectile.gd:30`) проходят через
  `take_damage` → сигнал покрывает все источники урона без отдельных правок.
- Сигнал `damaged` не нужен: `health_changed` несёт то же самое и совпадает с
  конвенцией игрока.

### Шаг 2. stat_bar.gd — без обязательных правок

Оверлей использует готовое API: `set_values()`, `snap()`, `color`, `show_text`,
`pulse_when_low`, `thickness` (`stat_bar.gd:7–32`). Обязательных доработок нет.

Одна **опциональная** микрооптимизация — ранний выход из `_process` в покое,
чтобы скрытые/неизменяющиеся полоски не перерисовывались (`stat_bar.gd:39–51`):

```gdscript
func _process(delta: float) -> void:
	_t += delta
	# НОВОЕ: в покое (без анимации, следа и пульса) перерисовка не нужна
	if absf(value - _shown) < 0.01 and absf(_trail - value) < 0.01 \
			and not (pulse_when_low and value / max_value < 0.25):
		return
	...
```

Опционально потому, что при текущих 2 врагах экономия неотличима от нуля; включить
одновременно с ростом числа врагов. Проверить, что `snap()` (`stat_bar.gd:29–32`) по-прежнему
корректно гасит анимацию (после раннего выхода `_prev` не обновляется — безопасно,
т.к. `value == _shown`).

### Шаг 3. Новый файл enemy_health_overlay.gd

Новый скрипт `enemy_health_overlay.gd` (`extends CanvasLayer`), узел добавляется в
`main.tscn` (шаг 4). Скелет:

```gdscript
class_name EnemyHealthOverlay
extends CanvasLayer

## Экранные полоски здоровья врагов: StatBar над головой, позиция через
## Camera3D.unproject_position. Скрытие при полном HP, затухание после урона.

const ANCHOR_OFFSET := Vector3(0.0, 2.5, 0)  # над индикатором ?/! (enemy.gd:91 — y=2.2)
const BAR_SIZE := Vector2(46.0, 8.0)          # базовый размер, толщину задаёт StatBar.thickness
const LINGER_TIME := 4.0                      # сколько держать полоску после последнего удара
const FADE_SPEED := 2.0                       # скорость затухания альфы (1/с)
const DEATH_FADE_TIME := 0.3                  # быстрое скрытие после смерти врага
const MAX_DISTANCE := 28.0                    # дальше полоску не показываем
const NEAR_DIST := 6.0                        # дистанции для масштабирования ширины
const FAR_DIST := 20.0
const SCREEN_MARGIN := 60.0                   # запас за краем экрана, где ещё скрываем

var _root: Control            # full-rect, MOUSE_FILTER_IGNORE — как hud.gd _make_layer()
var _camera: Camera3D
var _player: Player
## enemy -> { bar: StatBar, alpha: float, linger: float, dying: bool, last_pos: Vector2 }
var _entries: Dictionary = {}

func _ready() -> void:
	layer = 4                    # ПОД HUD (5) и меню паузы (10): скрин-слои HUD
	                             # автоматически перекрывают полоски, отдельных
	                             # проверок не нужно
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# игрок/камера — лениво, как в enemy.gd:103-116
	_player = get_tree().get_first_node_in_group("player")
	_camera = _player.camera if _player else null

func _process(delta: float) -> void:
	# Пауза не кодируется: PROCESS_MODE_INHERIT (по умолчанию) замирает при
	# get_tree().paused (pause_menu.gd:344, hud.gd:446) — полоски и таймеры
	# встают вместе с миром.
	if _camera == null or not is_instance_valid(_camera):
		_resolve_player()
		if _camera == null:
			return
	var used := {}
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or not is_instance_valid(enemy):
			continue
		var e: Dictionary = _get_or_create_entry(enemy)
		_update_entry(enemy, e, delta)
		used[enemy] = true
	_forget_unused(used)

func _get_or_create_entry(enemy: Enemy) -> Dictionary:
	if _entries.has(enemy):
		return _entries[enemy]
	var e := {
		"bar": _make_bar(),
		"alpha": 0.0,
		"linger": 0.0,
		"dying": false,
		"last_pos": Vector2.ZERO,
	}
	# урон: показать полоску и перезапустить таймер удержания
	enemy.health_changed.connect(func(_c: float, _m: float) -> void:
		e["linger"] = LINGER_TIME
		e["alpha"] = 1.0)
	# смерть: быстрое затухание, позицию больше не трогаем
	enemy.died.connect(func() -> void: e["dying"] = true)
	_entries[enemy] = e
	return e

func _make_bar() -> StatBar:
	var bar := StatBar.new()
	bar.color = UiTheme.HEALTH            # BLOOD, ui_theme.gd:21-23
	bar.thickness = 4.0
	bar.show_text = false                 # текст всё равно отключится: stat_bar.gd:75
	bar.pulse_when_low = true             # пульс при HP < 25%
	bar.snap()
	_root.add_child(bar)
	return bar

func _update_entry(enemy: Enemy, e: Dictionary, delta: float) -> void:
	var bar: StatBar = e["bar"]
	# 1) Мёртв: не трекаем падающее тело (rotation.x -> -90, enemy.gd:299),
	#    гасим на последней экранной позиции.
	if e["dying"] or enemy.state == Enemy.State.DEAD:
		e["alpha"] = move_toward(e["alpha"], 0.0, delta / DEATH_FADE_TIME)
		bar.visible = e["alpha"] > 0.01
		bar.modulate.a = e["alpha"]
		return
	# 2) Полное HP и урона давно не было: полоска скрыта.
	e["linger"] = maxf(e["linger"] - delta, 0.0)
	if e["linger"] <= 0.0:
		e["alpha"] = move_toward(e["alpha"], 0.0, FADE_SPEED * delta)
	if e["alpha"] <= 0.01:
		bar.visible = false
		return
	# 3) Проекция анкора.
	var anchor := enemy.global_position + ANCHOR_OFFSET
	if _camera.is_position_behind(anchor):
		bar.visible = false            # за спиной камеры unproject врёт — не рисуем
		return
	var screen := _camera.unproject_position(anchor)
	if screen.x < -SCREEN_MARGIN or screen.y < -SCREEN_MARGIN \
			or screen.x > _root.size.x + SCREEN_MARGIN \
			or screen.y > _root.size.y + SCREEN_MARGIN:
		bar.visible = false            # далеко за краем экрана — не рисуем
		return
	# 4) Дистанция: масштаб ширины и отсечка.
	var dist := _camera.global_position.distance_to(anchor)
	if dist > MAX_DISTANCE:
		bar.visible = false
		return
	var width_k := clampf(remap(dist, NEAR_DIST, FAR_DIST, 1.0, 0.55), 0.55, 1.0)
	# 5) Значение и позиция.
	bar.set_values(enemy.health, enemy.health_max)
	bar.size = Vector2(BAR_SIZE.x * width_k, BAR_SIZE.y)
	bar.position = screen - bar.size * 0.5
	bar.visible = true
	bar.modulate.a = e["alpha"]

func _forget_unused(used: Dictionary) -> void:
	for enemy in _entries.keys():
		if used.has(enemy):
			continue
		# враг удалён из группы (queue_free после смерти, enemy.gd:301) —
		# соединения умерли вместе с эмиттером, остаётся убрать полоску
		var e: Dictionary = _entries[enemy]
		(e["bar"] as StatBar).queue_free()
		_entries.erase(enemy)

func _resolve_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null:
		_player = get_tree().current_scene.find_child("Player", true, false) as Player
	_camera = _player.camera if _player != null else null
```

Связка сигналов: `enemy.health_changed` → показать/удержать полоску;
`enemy.died` → быстрое затухание без трекинга; позиция и значения — опрос в
`_process` (дёшево, и переживает respawn через перезагрузку сцены —
`player.gd:241–242`).

### Шаг 4. main.tscn — подключение узла

Добавить в корень `main.tscn` (а НЕ в `player.tscn` — последний, вероятно, трогает
параллельный агент, добавляя `pause_controller.gd`; в `main.tscn` конфликтов нет):

```diff
+[ext_resource type="Script" path="res://enemy_health_overlay.gd" id="5_overlay"]

 [node name="Main" type="Node3D"]
+[node name="EnemyHealthOverlay" type="CanvasLayer" parent="."]
+script = ExtResource("5_overlay")
```

CanvasLayer глобален для viewport — быть ребёнком `Main` достаточно, чтобы видеть
и камеру игрока, и группу `"enemies"`.

### Шаг 5. Проверка (ручная)

1. Запуск `C:/Godot/Godot_v4.7.2-stable_win64.exe --path .` → враги с полным HP,
   полосок нет.
2. `fire_bolt` (20 урона) по EnemyA → полоска появилась на 40/60, «след» тянется,
   через ~4 с без урона плавно ушла.
3. Поджечь (`fire_bolt` = ignite): полоска видима всё время горения (DoT каждые
   кадр перезапускает `linger`), HP тает на 6/с.
4. Добить: `stone_shard` (25) + `fire_bolt` (20) + `fire_bolt` (20) = 65 ≥ 60 →
   полоска мигнула и погасла за ~0,3 с, враг упал, через ~3,4 с удалился без ошибок.
   (Вариант: поджечь и ждать — 20 + 3 с горения ≈ 38, затем добить.)
5. Повернуться к раненому врагу спиной → полоска исчезла; развернуться → вернулась.
6. ESC (пауза) → полоски замерли под скрином меню (слой 10 поверх слоя 4);
   продолжить → анимация пошла дальше.
7. Смерть игрока → экран смерти HUD (слой 5) перекрывает полоски (слой 4).

### Шаг 6 (опционально). Отсечение врагов за стенами

Полоски видны сквозь стены (как и индикатор `?`/`!` — `enemy.gd:93`). Если для
стелса это нежелательно — троттлированный луч, по образцу `enemy.gd:138`:

```gdscript
const OCCLUSION_EVERY := 0.15   # проверять 6-7 раз в секунду, не каждый кадр
var _occlusion_t := 0.0

# в _process перед циклом: считать кадр проверки и кэшировать результат
# в записи врага ("occluded": bool):
# var q := PhysicsRayQueryParameters3D.create(
# 	_camera.global_position, anchor, 1)   # слой 1 — мир (spell_projectile.gd:17)
# e["occluded"] = not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
```

Луч только по врагам с видимой полоской; результат кэшируется до следующей проверки.

## 5. Крайние случаи

| Случай | Поведение | Где в плане |
|---|---|---|
| Враг мёртв | `died` → `dying = true`: позиция замирает на последней экранной точке (тело падает `rotation:x → −90°`, `enemy.gd:299`, анкер бы съехал), альфа гаснет за `DEATH_FADE_TIME` 0,3 с | шаг 3, `_update_entry` |
| Враг удаляется (`queue_free` через ~3,4 с после смерти, `enemy.gd:301`) | враг выпадает из группы `"enemies"` → `_forget_unused` освобождает полоску; соединения сигналов умирают вместе с эмиттером; `is_instance_valid` страхует от гонки в том же кадре | шаг 3, `_forget_unused` |
| Враг за камерой | `camera.is_position_behind(anchor)` → скрыть; `unproject_position` для точек за камерой даёт бессмысленные координаты, поэтому проверка обязательна до проекции | шаг 3 |
| Враг за краем экрана | прямоугольник экрана ± `SCREEN_MARGIN` → скрыть. Альтернатива «указатель на краю экрана» — отдельная фича, не входит | шаг 3 |
| Перекрытие нескольких полосок | базово — ничего (полоски просвечивают, alpha < 1); при необходимости — жадное расталкивание по вертикали после сбора видимых: сортировка по `screen.y`, при пересечении Rect2 сдвигать нижнюю полоску на `высота + 4 px`. С 2 врагами на арене 30×30 практически не встречается | резерв, не в скелете |
| Враг далеко | ширина полоски масштабируется `remap(dist, 6, 20, 1.0, 0.55)`, высота и толщина постоянны; дальше `MAX_DISTANCE` 28 м — скрыть. Пиксельный размер не зависит от FOV-скачков при беге (`player.gd:339-341`) | шаг 3 |
| Пауза (ESC / выбор школы) | оверлей в `PROCESS_MODE_INHERIT` → `_process` замирает вместе с миром; полоски и таймеры `linger`/альфа стоят, после снятия паузы продолжаются. Меню (слой 10) и скрин школы/смерти (слой 5 HUD) перекрывают слой 4 | шаг 3, шаг 4 |
| Смерть игрока / respawn | экран смерти HUD (слой 5) перекрывает полоски (слой 4); respawn = `reload_current_scene()` (`player.gd`) — оверлей и записи пересоздаются сценой, утечек нет | шаг 4–5 |
| Полное HP | полоска не создаётся до первого `health_changed`; после возврата к... у врагов нет лечения, значит «полное HP» = «не бит», таймер `linger` 4 с держит показ после последнего удара, затем `FADE_SPEED` гасит | шаг 3 |
| Врагов нет / пустая группа | цикл по группе просто не выполняется; `_root` не перерисовывается | шаг 3 |

## 6. Риски и координация

1. **Столкновение с параллельным рефакторингом паузы.** Файлы `hud.gd`,
   `pause_menu.gd`, `player.gd`, `pause_controller.gd` не редактируются планом;
   узел оверлея вешается на `main.tscn`, а не на `player.tscn`. Остаются два общих
   файла: `enemy.gd` (пауза его не трогает) и `stat_bar.gd` (не трогает). Риск
   конфликтов близок к нулю; при merge первым применить ветку паузы.
2. **StatBar до этого нигде не использовался** (`grep` по `*.gd`/`*.tscn`) —
   внедрение будет первым пользователем; поведение «текст при `size.y >= 18`»
   (`stat_bar.gd:75`) и анимация `_trail` проверяются вручную (шаг 5).
3. **Полоски видны сквозь стены** — для стелс-механики это может раскрыть позицию
   раненого врага. Существующий индикатор `?`/`!` ведёт себя так же
   (`enemy.gd:93`), так что поведение согласовано; при желании — шаг 6.
4. **Наложение на индикатор `?`/`!`**: оба живут у `y ≈ 2.2`. Анкор полоски вынесен
   на `y = 2.5` (`ANCHOR_OFFSET`); точное значение — визуальная настройка при
   сверке в игре (шаг 5).
5. **Гонка «сигнал после freeing»**: `health_changed` эмитится до `_die()`
   (шаг 1), `died` — в `_die()`; оба приходят до `queue_free` (который ещё и
   отложен на 3,4 с, `enemy.gd:299–301`), так что лямбды оверлея никогда не
   срабатывают на освобождённом объекте.
6. **Рост N**: при десятках врагов включить ранний выход в `StatBar._process`
   (шаг 2) и, если понадобится, пулить полоски вместо `queue_free`/`new`.
