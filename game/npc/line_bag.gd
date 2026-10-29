extends RefCounted
## «Мешок» реплик (TEXT-01): каждый пул выдаётся перемешанным кругом без повторов; на стыке кругов первая реплика
## нового круга не совпадает с последней прошлого — подряд одна и та же строка не звучит. Один мешок на всю улицу
## (Residents): соседи по голосу не повторяют друг друга. Детерминирован: свой RandomNumberGenerator с seed.

var _rng := RandomNumberGenerator.new()
var _bags := {}   # ключ → оставшиеся реплики круга (берутся с конца)
var _last := {}   # ключ → последняя выданная

func _init(seed_value := 0) -> void:
	_rng.seed = seed_value

## Следующая реплика пула lines под ключом key (обычно «голос/событие»); пустой пул — "".
func next(key: StringName, lines: Array) -> String:
	if lines.is_empty():
		return ""
	var bag: Array = _bags.get(key, [])
	if bag.is_empty():
		bag = lines.duplicate()
		for i in range(bag.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var t = bag[i]
			bag[i] = bag[j]
			bag[j] = t
		if bag.size() > 1 and bag.back() == _last.get(key, ""):
			var t = bag[0]
			bag[0] = bag.back()
			bag[bag.size() - 1] = t
	var text: String = bag.pop_back()
	_bags[key] = bag
	_last[key] = text
	return text

func reset() -> void:
	_bags.clear()
	_last.clear()
