class_name MagicBook
extends Node

## Книга магии игрока: школы, выбор стартового направления и изучение новых.
## Магия безмолвная: слов и жестов нет, заклинание творится намерением.

signal school_learned(school: School)
signal primary_school_chosen(school: School)

enum School {
	# Базовые стихии
	FIRE, WIND, WATER, EARTH,
	# Производные (открываются через базовую стихию)
	ICE, STEAM, LIGHTNING, DUST, LAVA, NATURE,
	# Нестандартные
	LIGHT, TELEPORT,
}

const BASE_SCHOOLS: Array[School] = [School.FIRE, School.WIND, School.WATER, School.EARTH]

## Для каждой школы: названия и от каких школ она зависит (достаточно любой из списка).
## Пустой список requires = доступна без условий (базовые) или открывается особым способом.
const SCHOOL_DATA: Dictionary = {
	School.FIRE: {"name": "Огонь", "requires": []},
	School.WIND: {"name": "Ветер", "requires": []},
	School.WATER: {"name": "Вода", "requires": []},
	School.EARTH: {"name": "Земля", "requires": []},
	School.ICE: {"name": "Лёд", "requires": [School.WATER, School.WIND]},
	School.STEAM: {"name": "Пар", "requires": [School.WATER, School.FIRE]},
	School.LIGHTNING: {"name": "Молния", "requires": [School.WIND, School.FIRE]},
	School.DUST: {"name": "Пыль", "requires": [School.EARTH, School.WIND]},
	School.LAVA: {"name": "Лава", "requires": [School.EARTH, School.FIRE]},
	School.NATURE: {"name": "Природа", "requires": [School.EARTH, School.WATER]},
	# Нестандартные: не зависят от стихий, но открываются отдельно (находки, квесты)
	School.LIGHT: {"name": "Свет", "requires": [], "special": true},
	School.TELEPORT: {"name": "Телепортация", "requires": [], "special": true},
}

## Стоимость изучения: пока заглушка, цена будет решена позже (очки, компромиссы и т. д.).
## Сюда можно добавить штрафы для чужих стихий.
var learned: Array[School] = []
var primary_school: int = -1

func has_school(school: School) -> bool:
	return learned.has(school)

func school_name(school: School) -> String:
	return SCHOOL_DATA[school]["name"]

func is_special(school: School) -> bool:
	return SCHOOL_DATA[school].get("special", false)

## Выбор стартового направления: только базовая стихия, один раз.
func choose_primary(school: School) -> bool:
	if primary_school != -1 or not BASE_SCHOOLS.has(school):
		return false
	primary_school = school
	learned.append(school)
	primary_school_chosen.emit(school)
	school_learned.emit(school)
	return true

## Можно ли изучить школу (без учёта цены).
## Базовые стихии доступны всегда после выбора стартовой; производные — при знании
## любой из родительских; особые открываются только принудительно (force).
func can_learn(school: School, force: bool = false) -> bool:
	if primary_school == -1 or has_school(school):
		return false
	if BASE_SCHOOLS.has(school):
		return true
	if is_special(school):
		return force
	for parent in SCHOOL_DATA[school]["requires"]:
		if has_school(parent):
			return true
	return false

func learn(school: School, force: bool = false) -> bool:
	if not can_learn(school, force):
		return false
	learned.append(school)
	school_learned.emit(school)
	return true

## Какие школы можно изучить прямо сейчас.
func learnable() -> Array[School]:
	var result: Array[School] = []
	for school in SCHOOL_DATA:
		if can_learn(school):
			result.append(school)
	return result
