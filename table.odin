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
	key:   ^ObjString,
	value: Value,
}

free_table :: proc(table: ^Table) {
	delete(table.entries)
	table.count = 0
	table.capacity = 0
}

find_entry :: proc(entries: []Entry, capacity: int, key: ^ObjString) -> ^Entry {
	idx := int(key.hash) % capacity
	tombstone: ^Entry = nil

	for {
		entry := &entries[idx]

		if entry.key == nil {
			if is_nil(entry.value) {
				// empty entry 
				return tombstone != nil ? tombstone : entry
			} else {
				// we found a tombstone 
				if tombstone == nil do tombstone = entry
			}
		} else if entry.key == key {
			return entry
		}
		idx = (idx + 1) % capacity
	}
}

table_set :: proc(table: ^Table, key: ^ObjString, value: Value) -> bool {
	if f64(table.count + 1) > f64(table.capacity) * TABLE_MAX_LOAD {
		capacity := grow_capacity(table.capacity)
		adjust_capacity(table, capacity)
	}

	entry := find_entry(table.entries, table.capacity, key)
	is_new_key := entry.key == nil
	if is_new_key && is_nil(entry.value) do table.count += 1

	entry.key = key
	entry.value = value
	return is_new_key
}

table_delete :: proc(table: ^Table, key: ^ObjString) -> bool {
	if table.count == 0 do return false

	entry := find_entry(table.entries, table.capacity, key)
	if entry.key == nil do return false

	entry.key = nil
	entry.value = bool_val(true)
	return true
}

grow_capacity :: proc(capacity: int) -> int {
	return 8 if capacity < 8 else capacity * 2
}

adjust_capacity :: proc(table: ^Table, capacity: int) {
	entries := make([]Entry, capacity)
	for i in 0 ..< capacity {
		entries[i].key = nil
		entries[i].value = nil_val()
	}

	table.count = 0

	for i := 0; i < table.capacity; i += 1 {
		entry := table.entries[i]
		if entry.key == nil do continue

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

	for i := 0; i < from.capacity; i += 1 {

		entry := from.entries[i]
		if entry.key != nil do table_set(to, entry.key, entry.value)
	}
}

table_find_string :: proc(table: ^Table, str: string, hash: u32) -> ^ObjString {
	if table.count == 0 do return nil
	idx := hash % u32(table.capacity)
	for {
		entry := table.entries[idx]
		if entry.key == nil {
			if is_nil(entry.value) do return nil
		} else if len(entry.key.str) == len(str) &&
		   entry.key.hash == hash &&
		   mem.compare(transmute([]u8)entry.key.str, transmute([]u8)str) == 0 {
			return entry.key
		}
		idx = (idx + 1) % u32(table.capacity)
	}
}

table_get :: proc(table: ^Table, key: ^ObjString) -> (Value, bool) {
	if table.count == 0 do return nil_val(), false

	entry := find_entry(table.entries, table.capacity, key)
	if entry.key == nil do return nil_val(), false

	value := entry.value
	return value, true
}
