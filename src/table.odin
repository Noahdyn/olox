package olox

import "core:fmt"
import "core:mem"

TABLE_MAX_LOAD :: 0.75

Table :: struct {
	count:    int,
	capacity: int,
	entries:  []Entry,
}

Entry :: struct {
	key:   Value,
	value: Value,
}

free_table :: proc(table: ^Table) {
	delete(table.entries)
	table.count = 0
	table.capacity = 0
}

hash_value :: proc(val: Value) -> u32 {
	switch val.type {
	case .NIL:
		return 0
	case .BOOL:
		return u32(1) if as_bool(val) else u32(0)
	case .NUMBER:
		bits := transmute(u64)as_number(val)
		return u32(bits) ~ u32(bits >> 32)
	case .OBJ:
		obj := as_obj(val)
		switch obj.type {
		case .String:
			str_obj := cast(^ObjString)obj
			return str_obj.hash
		case .Closure, .Upvalue, .Function, .Native:
			error("cannot use functions as hash map keys.")
		}

	}
	return 0
}

find_entry :: proc(entries: []Entry, capacity: int, key: Value) -> ^Entry {
	idx := int(hash_value(key)) % capacity
	tombstone: ^Entry = nil

	for {
		entry := &entries[idx]

		if is_nil(entry.key) {
			if is_nil(entry.value) {
				// empty entry 
				return tombstone != nil ? tombstone : entry
			} else {
				// we found a tombstone 
				if tombstone == nil do tombstone = entry
			}
		} else if values_equal(entry.key, key) {
			return entry
		}
		idx = (idx + 1) % capacity
	}
}

table_set :: proc(table: ^Table, key: Value, value: Value) -> bool {
	if f64(table.count + 1) > f64(table.capacity) * TABLE_MAX_LOAD {
		capacity := grow_capacity(table.capacity)
		adjust_capacity(table, capacity)
	}

	entry := find_entry(table.entries, table.capacity, key)
	is_new_key := is_nil(entry.key)
	if is_new_key && is_nil(entry.value) do table.count += 1

	entry.key = key
	entry.value = value
	return is_new_key
}

table_delete :: proc(table: ^Table, key: Value) -> bool {
	if table.count == 0 do return false

	entry := find_entry(table.entries, table.capacity, key)
	if is_nil(entry.key) do return false

	entry.key = nil_val()
	entry.value = bool_val(true)
	return true
}

grow_capacity :: proc(capacity: int) -> int {
	return 8 if capacity < 8 else capacity * 2
}

adjust_capacity :: proc(table: ^Table, capacity: int) {
	entries := make([]Entry, capacity)
	for i in 0 ..< capacity {
		entries[i].key = nil_val()
		entries[i].value = nil_val()
	}

	table.count = 0

	for i in 0 ..< table.capacity {
		entry := table.entries[i]
		if is_nil(entry.key) do continue

		dest := find_entry(entries, capacity, entry.key)
		dest.key = entry.key
		dest.value = entry.value
		table.count += 1
	}

	delete(table.entries)
	table.entries = entries
	table.capacity = capacity
}

table_add_all :: proc(from, to: ^Table) {

	for i in 0 ..< from.capacity {

		entry := from.entries[i]
		if !is_nil(entry.key) do table_set(to, entry.key, entry.value)
	}
}

table_find_string :: proc(table: ^Table, str: string, hash: u32) -> ^ObjString {
	if table.count == 0 do return nil
	idx := hash % u32(table.capacity)
	for {
		entry := table.entries[idx]
		if is_nil(entry.key) {
			if is_nil(entry.value) do return nil
		} else if is_string(entry.key) {
			str_obj := cast(^ObjString)as_obj(entry.key)
			if len(str_obj.str) == len(str) &&
			   str_obj.hash == hash &&
			   mem.compare(transmute([]u8)str_obj.str, transmute([]u8)str) == 0 {
				return str_obj
			}
		}
		idx = (idx + 1) % u32(table.capacity)
	}
}

table_get :: proc(table: ^Table, key: Value) -> (Value, bool) {
	if table.count == 0 do return nil_val(), false

	entry := find_entry(table.entries, table.capacity, key)
	if is_nil(entry.key) do return nil_val(), false

	value := entry.value
	return value, true
}
