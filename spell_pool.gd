class_name SpellPool
extends Node

## Пул снарядов: вместо `SpellProjectile.new()` + `queue_free()` на каждый каст
## держим по одному готовому снаряду на школу и переиспользуем его.
##
## Что это даёт:
## - в момент каста нет ни аллокации узлов, ни сборки мешей, ни создания
##   материалов — только `acquire()`, позиция и `launch()`;
## - GPU-частицы (след, дым) не пересоздаются, а перезапускаются, поэтому нет
##   кадра, где след «моргает»;
## - при попадании снаряд не удаляется, эффект удара живёт в сцене отдельно.
##
## Снаряд возвращается в пул в конце `_recycle()` через `release()`.

const GROUP := "spell_pool"
## Сколько «спящих» снарядов держать на школу. Бой идёт очередями, поэтому
## двух хватает даже при быстрой смене школы в режиме просмотра (F3).
const FREE_PER_SCHOOL := 3

## Все живые снаряды пула, включая спящие.
var _all: Array[SpellProjectile] = []
## Свободные снаряды: ключ — материал тела (школа).
var _free: Dictionary = {}
var _in_use: Dictionary = {}

static func get_or_create(tree: SceneTree) -> SpellPool:
	var pool := tree.get_first_node_in_group(GROUP) as SpellPool
	if pool != null:
		return pool
	pool = SpellPool.new()
	pool.name = "SpellPool"
	pool.add_to_group(GROUP, true)
	# Пул — служебный узел сцены: физика ему не нужна.
	pool.process_mode = Node.PROCESS_MODE_ALWAYS
	return pool

## Взять снаряд. Свободные снаряды хранятся «по школам», но если нужной
## школы под рукой нет, дешевле пересобрать тело уже собранного снаряда
## (один раз), чем аллоцировать узел, меши и материалы заново.
func acquire(visual: String) -> SpellProjectile:
	var key := SpellProjectile.body_key(visual)
	var bucket: Array = _free.get(key, [])
	while not bucket.is_empty():
		var candidate: SpellProjectile = bucket.pop_back()
		# Страховка: узел мог быть удалён вместе со сценой.
		if is_instance_valid(candidate) and candidate.get_parent() == self:
			_in_use[key] = int(_in_use.get(key, 0)) + 1
			return candidate
	var spare := _take_any_free()
	if spare != null:
		spare.apply_tint(spare.tint, visual)
		_in_use[spare.body_cache_key] = int(_in_use.get(spare.body_cache_key, 0)) + 1
		return spare
	var proj := SpellProjectile.new()
	proj.visual = visual
	proj.configure()
	proj.mark_pooled(true)
	add_child(proj)
	_all.append(proj)
	_in_use[key] = int(_in_use.get(key, 0)) + 1
	return proj

## Любой свободный снаряд: используется как заготовка под другую школу.
## Ключ забираем и «схлопываем» пустой бакет, иначе в _free копятся пустые
## массивы, и release() с acquire() перестают сходиться.
func _take_any_free() -> SpellProjectile:
	for key in _free.keys():
		var bucket: Array = _free[key]
		while not bucket.is_empty():
			var candidate: SpellProjectile = bucket.pop_back()
			if is_instance_valid(candidate) and candidate.get_parent() == self:
				if bucket.is_empty():
					_free.erase(key)
				return candidate
		_free.erase(key)
	return null

## Вернуть снаряд. Вызывается самим снарядом в `_recycle()`.
func release(proj: SpellProjectile) -> void:
	if proj == null or not is_instance_valid(proj):
		return
	var key := proj.body_cache_key
	_in_use[key] = maxi(int(_in_use.get(key, 0)) - 1, 0)
	var bucket: Array = _free.get(key, [])
	# Лишние экземпляры не копим: пул должен оставаться маленьким.
	if bucket.size() >= FREE_PER_SCHOOL:
		_all.erase(proj)
		proj.queue_free()
		return
	bucket.append(proj)
	_free[key] = bucket

## Диагностика для HUD в режиме просмотра: сколько снарядов собрано суммарно.
func stats() -> Dictionary:
	return {"total": _all.size(), "in_use": _in_use.duplicate(), "free": _free.duplicate()}
