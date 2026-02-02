(** Pure OCaml Python parsing via pyre-ast.

    Replaces tree-sitter + regex parsing with typed AST.
    Uses CPython under the hood for 100% parsing fidelity.
*)

type location = {
  start_line : int;
  start_col : int;
  end_line : int;
  end_col : int;
}

type import_alias = {
  name : string;
  asname : string option;
  loc : location;
}

type import_stmt =
  | Import of {
      names : import_alias list;
      loc : location;
    }
  | ImportFrom of {
      module_ : string option;
      names : import_alias list;
      level : int;
      loc : location;
    }

(** Convert pyre-ast location to our 0-indexed location.
    pyre-ast uses 1-indexed lines, 0-indexed columns. *)
let location_of_pyre (pyre_loc : PyreAst.Concrete.Location.t) : location =
  let open PyreAst.Concrete in
  let { Location.start; stop } = pyre_loc in
  {
    start_line = start.Position.line - 1;  (* 1-indexed to 0-indexed *)
    start_col = start.Position.column;     (* already 0-indexed *)
    end_line = stop.Position.line - 1;
    end_col = stop.Position.column;
  }

(** Convert pyre-ast import alias to our type *)
let import_alias_of_pyre (pyre_alias : PyreAst.Concrete.ImportAlias.t) : import_alias =
  let open PyreAst.Concrete in
  let { ImportAlias.location; name; asname } = pyre_alias in
  {
    name = Identifier.to_string name;
    asname = Option.map Identifier.to_string asname;
    loc = location_of_pyre location;
  }

(** Extract import statements from parsed module *)
let extract_from_module (mod_ : PyreAst.Concrete.Module.t) : import_stmt list =
  let open PyreAst.Concrete in
  let { Module.body; _ } = mod_ in
  List.filter_map (fun stmt ->
    match stmt with
    | Statement.Import { location; names } ->
      Some (Import {
        names = List.map import_alias_of_pyre names;
        loc = location_of_pyre location;
      })
    | Statement.ImportFrom { location; module_; names; level } ->
      Some (ImportFrom {
        module_ = Option.map Identifier.to_string module_;
        names = List.map import_alias_of_pyre names;
        level;
        loc = location_of_pyre location;
      })
    | _ -> None
  ) body

let extract_imports source : import_stmt list =
  PyreAst.Parser.with_context
    ~on_init_failure:(fun () -> [])
    (fun ctx ->
      let spec = PyreAst.Concrete.make_tagless_final () in
      match PyreAst.Parser.TaglessFinal.parse_module ~context:ctx ~spec source with
      | Ok module_ -> extract_from_module module_
      | Error _ -> [])

let extract_imports_with_error source : import_stmt list * string option =
  PyreAst.Parser.with_context
    ~on_init_failure:(fun () -> ([], Some "Failed to initialize Python parser"))
    (fun ctx ->
      let spec = PyreAst.Concrete.make_tagless_final () in
      match PyreAst.Parser.TaglessFinal.parse_module ~context:ctx ~spec source with
      | Ok module_ -> (extract_from_module module_, None)
      | Error err ->
        let msg = Printf.sprintf "Parse error at line %d col %d: %s"
          err.line err.column err.message in
        ([], Some msg))

(** Module-level constant: Assign, AnnAssign with simple Name target *)
type module_constant = {
  name : string;
  loc : location;
  source_text : string;
}

(** Logger binding: assignments like logger = logging.getLogger(__name__).
    These depend on __name__ and must be replicated per-file, not extracted to _constants.py. *)
type logger_binding = {
  var_name : string;
  loc : location;
  source_text : string;
}

(** Check if name is a dunder (double-underscore) name *)
let is_dunder name =
  String.length name >= 4 &&
  String.sub name 0 2 = "__" &&
  String.sub name (String.length name - 2) 2 = "__"

(** Check if an expression is a call to logging.getLogger(__name__).
    This pattern depends on __name__ and must not be extracted to _constants.py. *)
let is_logger_getname_call (expr : PyreAst.Concrete.Expression.t) : bool =
  let open PyreAst.Concrete in
  match expr with
  | Expression.Call { func; args; _ } ->
    (* Check if func is logging.getLogger or <alias>.getLogger *)
    let is_getlogger_func =
      match func with
      | Expression.Attribute { value = Expression.Name _; attr; _ } ->
        Identifier.to_string attr = "getLogger"
      | _ -> false
    in
    (* Check if any argument is __name__ *)
    let has_dunder_name_arg =
      List.exists (fun arg ->
        match arg with
        | Expression.Name { id; _ } -> Identifier.to_string id = "__name__"
        | _ -> false
      ) args
    in
    is_getlogger_func && has_dunder_name_arg
  | _ -> false

(** Extract source text from location.
    Lines are 0-indexed in our location type. *)
let extract_source_text source_lines loc =
  let { start_line; end_line; _ } = loc in
  let lines = Array.sub source_lines start_line (end_line - start_line + 1) in
  String.concat "" (Array.to_list lines)

(** Extract constant definitions from parsed module.
    Filters for: Assign with Name target, AnnAssign with Name target.
    Excludes: dunder names, augmented assignments, logger patterns. *)
let extract_constants_from_module source_lines (mod_ : PyreAst.Concrete.Module.t) : module_constant list =
  let open PyreAst.Concrete in
  let { Module.body; _ } = mod_ in
  List.filter_map (fun stmt ->
    match stmt with
    (* Simple assignment: NAME = value *)
    | Statement.Assign { location; targets; value; _ } ->
      (* Only handle single Name target *)
      (match targets with
       | [Expression.Name { id; _ }] ->
         let name = Identifier.to_string id in
         (* Exclude dunder names and logger patterns *)
         if is_dunder name || is_logger_getname_call value then None
         else
           let loc = location_of_pyre location in
           let source_text = extract_source_text source_lines loc in
           Some { name; loc; source_text }
       | _ -> None)
    (* Annotated assignment: NAME: type = value or NAME: type *)
    | Statement.AnnAssign { location; target; value; _ } ->
      (match target with
       | Expression.Name { id; _ } ->
         let name = Identifier.to_string id in
         (* Exclude dunder names and logger patterns (if value present) *)
         let is_logger = match value with
           | Some v -> is_logger_getname_call v
           | None -> false
         in
         if is_dunder name || is_logger then None
         else
           let loc = location_of_pyre location in
           let source_text = extract_source_text source_lines loc in
           Some { name; loc; source_text }
       | _ -> None)
    (* Type alias: type NAME = ... (Python 3.12+) *)
    | Statement.TypeAlias { location; name = Expression.Name { id; _ }; _ } ->
      let name = Identifier.to_string id in
      let loc = location_of_pyre location in
      let source_text = extract_source_text source_lines loc in
      Some { name; loc; source_text }
    | _ -> None
  ) body

(** Split source into lines, preserving newlines *)
let source_to_lines source =
  let parts = String.split_on_char '\n' source in
  let parts =
    if String.length source > 0 && source.[String.length source - 1] = '\n' then
      match List.rev parts with
      | "" :: rest -> List.rev rest
      | _ -> parts
    else parts
  in
  Array.of_list (List.map (fun s -> s ^ "\n") parts)

let extract_constants source : module_constant list =
  PyreAst.Parser.with_context
    ~on_init_failure:(fun () -> [])
    (fun ctx ->
      let spec = PyreAst.Concrete.make_tagless_final () in
      match PyreAst.Parser.TaglessFinal.parse_module ~context:ctx ~spec source with
      | Ok module_ ->
        let source_lines = source_to_lines source in
        extract_constants_from_module source_lines module_
      | Error _ -> [])

(** Extract logger bindings from parsed module.
    These are assignments like: logger = logging.getLogger(__name__)
    They depend on __name__ and must be replicated per-file. *)
let extract_logger_bindings_from_module source_lines (mod_ : PyreAst.Concrete.Module.t) : logger_binding list =
  let open PyreAst.Concrete in
  let { Module.body; _ } = mod_ in
  List.filter_map (fun stmt ->
    match stmt with
    | Statement.Assign { location; targets; value; _ } ->
      (match targets with
       | [Expression.Name { id; _ }] when is_logger_getname_call value ->
         let var_name = Identifier.to_string id in
         let loc = location_of_pyre location in
         let source_text = extract_source_text source_lines loc in
         Some { var_name; loc; source_text }
       | _ -> None)
    | Statement.AnnAssign { location; target; value = Some v; _ } when is_logger_getname_call v ->
      (match target with
       | Expression.Name { id; _ } ->
         let var_name = Identifier.to_string id in
         let loc = location_of_pyre location in
         let source_text = extract_source_text source_lines loc in
         Some { var_name; loc; source_text }
       | _ -> None)
    | _ -> None
  ) body

let extract_logger_bindings source : logger_binding list =
  PyreAst.Parser.with_context
    ~on_init_failure:(fun () -> [])
    (fun ctx ->
      let spec = PyreAst.Concrete.make_tagless_final () in
      match PyreAst.Parser.TaglessFinal.parse_module ~context:ctx ~spec source with
      | Ok module_ ->
        let source_lines = source_to_lines source in
        extract_logger_bindings_from_module source_lines module_
      | Error _ -> [])

(** A top-level definition extracted from source *)
type extracted_definition = {
  name : string;
  kind : Types.definition_kind;
  loc : location;
}

(** Get location from any Expression (needed for decorator ranges).
    All Expression variants have a location field. *)
let get_expression_location (expr : PyreAst.Concrete.Expression.t) : PyreAst.Concrete.Location.t =
  let open PyreAst.Concrete.Expression in
  match expr with
  | BoolOp { location; _ } | NamedExpr { location; _ } | BinOp { location; _ }
  | UnaryOp { location; _ } | Lambda { location; _ } | IfExp { location; _ }
  | Dict { location; _ } | Set { location; _ } | ListComp { location; _ }
  | SetComp { location; _ } | DictComp { location; _ } | GeneratorExp { location; _ }
  | Await { location; _ } | Yield { location; _ } | YieldFrom { location; _ }
  | Compare { location; _ } | Call { location; _ } | FormattedValue { location; _ }
  | JoinedStr { location; _ } | Constant { location; _ } | Attribute { location; _ }
  | Subscript { location; _ } | Starred { location; _ } | Name { location; _ }
  | List { location; _ } | Tuple { location; _ } | Slice { location; _ } -> location

(** Compute location including decorators.
    If decorators exist, start from first decorator's line.
    Column is preserved from base (for top-level check) since decorator
    expressions start after the @ symbol. *)
let decorated_location (base_loc : PyreAst.Concrete.Location.t) decorator_list =
  let base = location_of_pyre base_loc in
  match decorator_list with
  | [] -> base
  | first_dec :: _ ->
    let dec_loc = location_of_pyre (get_expression_location first_dec) in
    (* Use decorator's line but keep base column (decorator expr starts after @) *)
    { base with start_line = dec_loc.start_line }

(** Extract top-level definitions from parsed module *)
let extract_definitions_from_module (mod_ : PyreAst.Concrete.Module.t) : extracted_definition list =
  let open PyreAst.Concrete in
  let { Module.body; _ } = mod_ in
  List.filter_map (fun stmt ->
    match stmt with
    | Statement.FunctionDef { location; name; decorator_list; _ } ->
      let loc = decorated_location location decorator_list in
      if loc.start_col = 0 then
        Some { name = Identifier.to_string name; kind = Types.Function; loc }
      else None
    | Statement.AsyncFunctionDef { location; name; decorator_list; _ } ->
      let loc = decorated_location location decorator_list in
      if loc.start_col = 0 then
        Some { name = Identifier.to_string name; kind = Types.AsyncFunction; loc }
      else None
    | Statement.ClassDef { location; name; decorator_list; _ } ->
      let loc = decorated_location location decorator_list in
      if loc.start_col = 0 then
        Some { name = Identifier.to_string name; kind = Types.Class; loc }
      else None
    | _ -> None
  ) body

let extract_definitions source : extracted_definition list =
  PyreAst.Parser.with_context
    ~on_init_failure:(fun () -> [])
    (fun ctx ->
      let spec = PyreAst.Concrete.make_tagless_final () in
      match PyreAst.Parser.TaglessFinal.parse_module ~context:ctx ~spec source with
      | Ok module_ ->
        extract_definitions_from_module module_
        |> List.sort (fun a b -> compare a.loc.start_line b.loc.start_line)
      | Error _ -> [])
