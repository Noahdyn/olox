package olox

ObjType :: enum {
	Bound_Method,
	Class,
	Closure,
	Function,
	Instance,
	Native,
	String,
	Upvalue,
}

Obj :: struct {
	type:      ObjType,
	is_marked: bool,
	next:      ^Obj,
}

ObjString :: struct {
	obj:    Obj,
	string: string,
}
