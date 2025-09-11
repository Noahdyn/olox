package olox

import "core:fmt"

DEBUG_STRESS_GC :: false
DEBUG_LOG_GC :: true
GC_HEAP_GROW_FACTOR :: 2

free_objects :: proc() {
	object := vm.objects
	for object != nil {
		next := object.next
		free_object(object)
		object = next
	}
	delete(vm.gray_stack)
}


free_object :: proc(object: ^Obj) {

	if DEBUG_LOG_GC {
		fmt.println("%p free type %v", object, object.type)
	}
	switch object.type {
	case .String:
		o := cast(^ObjString)object
		vm.bytes_allocated -= size_of(o)
		delete(o.str)
		free(o)
	case .Function:
		function := cast(^ObjFunction)object
		vm.bytes_allocated -= size_of(function)
		vm.bytes_allocated -= size_of(function.chunk)
		free_chunk(&function.chunk)
		free(function)
	case .Native:
		o := cast(^ObjNative)object
		vm.bytes_allocated -= size_of(o)
		free(o)
	case .Closure:
		o := cast(^ObjClosure)object
		vm.bytes_allocated -= size_of(o)
		vm.bytes_allocated -= size_of(o.upvalues)
		delete(o.upvalues)
		free(o)
	case .Upvalue:
		o := cast(^Upvalue)object
		vm.bytes_allocated -= size_of(o)
		free(o)

	}
}

collect_garbage :: proc() {
	before: int
	if DEBUG_LOG_GC {
		fmt.println("-- gc begin")
		before := vm.bytes_allocated
	}

	mark_roots()
	trace_references()
	table_remove_white(&vm.strings)
	sweep()

	vm.next_gc = vm.bytes_allocated * GC_HEAP_GROW_FACTOR

	if DEBUG_LOG_GC {
		fmt.println("--gc end")
		fmt.printf(
			"   collected %v bytes (from %v to %v) next at %v\n",
			before - vm.bytes_allocated,
			before,
			vm.bytes_allocated,
			vm.next_gc,
		)
	}

}

trace_references :: proc() {
	for vm.gray_count > 0 {
		vm.gray_count -= 1
		object := vm.gray_stack[vm.gray_count]
		blacken_object(object)
	}
}

blacken_object :: proc(object: ^Obj) {
	if DEBUG_LOG_GC {
		fmt.printf("%p blacken ", object)
		print_value(obj_val(object))
		fmt.println()
	}
	switch object.type {
	case .Native, .String:
	case .Upvalue:
		mark_value((cast(^ObjUpvalue)(object)).closed)
	case .Function:
		function := cast(^ObjFunction)(object)
		mark_object(function.name)
		mark_array(&function.chunk.constants)
	case .Closure:
		closure := cast(^ObjClosure)(object)
		mark_object(closure.function)
		for i in 0 ..< len(closure.upvalues) {
			mark_object(closure.upvalues[i])
		}
	}
}

sweep :: proc() {
	prev: ^Obj = nil
	object := vm.objects

	for object != nil {
		if object.is_marked {
			object.is_marked = false
			prev = object
			object = object.next
		} else {
			unreached := object
			object = object.next
			if prev != nil {
				prev.next = object
			} else {
				vm.objects = object
			}

			free_object(unreached)
		}
	}
}

mark_array :: proc(array: ^[dynamic]Value) {
	for value in array {
		mark_value(value)
	}
}


mark_roots :: proc() {
	for i in 0 ..< vm.stack_top {
		mark_value(vm.stack[i])
	}

	for i in 0 ..< vm.frame_count {
		mark_object(vm.frames[i].closure)
	}

	for upvalue := vm.open_upvalues; upvalue != nil; upvalue = upvalue.next_upvalue {
		mark_object(upvalue)
	}

	mark_table(&vm.globals)
}

mark_value :: proc(val: Value) {
	if is_obj(val) do mark_object(as_obj(val))
}

mark_object :: proc(object: ^Obj) {
	if object == nil do return
	if object.is_marked do return

	if DEBUG_LOG_GC {
		fmt.print("%p mark ", object)
		print_value(obj_val(object))
		fmt.println()
	}
	object.is_marked = true

	append(&vm.gray_stack, object)
	vm.gray_count += 1

}

mark_table :: proc(table: ^Table) {
	for i in 0 ..< table.capacity {
		entry := table.entries[i]
		mark_object(as_obj(entry.key))
		mark_value(entry.value)
	}
}

table_remove_white :: proc(table: ^Table) {
	for i in 0 ..< table.capacity {
		entry := table.entries[i]
		if !is_nil(entry.key) && !as_obj(entry.key).is_marked {
			table_delete(table, entry.key)
		}
	}
}

mark_compiler_roots :: proc() {
	compiler := current
	for compiler != nil {
		mark_object(compiler.function)
		compiler = compiler.enclosing
	}


}
