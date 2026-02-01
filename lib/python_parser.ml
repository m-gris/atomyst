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

(** Convert pyre-ast location to our 0-indexed location *)
let location_of_pyre (pyre_loc : PyreAst.Concrete.Location.t) : location =
  let open PyreAst.Concrete in
  (* Private record - access fields directly *)
  let { Location.start; stop } = pyre_loc in
  {
    start_line = start.Position.line - 1;  (* 1-indexed to 0-indexed *)
    start_col = start.Position.column;
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

(** Check if name is a dunder (double-underscore) name *)
let is_dunder name =
  String.length name >= 4 &&
  String.sub name 0 2 = "__" &&
  String.sub name (String.length name - 2) 2 = "__"

(** Extract source text from location.
    Lines are 0-indexed in our location type. *)
let extract_source_text source_lines loc =
  let { start_line; end_line; _ } = loc in
  let lines = Array.sub source_lines start_line (end_line - start_line + 1) in
  String.concat "" (Array.to_list lines)

(** Extract constant definitions from parsed module.
    Filters for: Assign with Name target, AnnAssign with Name target.
    Excludes: dunder names, augmented assignments. *)
let extract_constants_from_module source_lines (mod_ : PyreAst.Concrete.Module.t) : module_constant list =
  let open PyreAst.Concrete in
  let { Module.body; _ } = mod_ in
  List.filter_map (fun stmt ->
    match stmt with
    (* Simple assignment: NAME = value *)
    | Statement.Assign { location; targets; _ } ->
      (* Only handle single Name target *)
      (match targets with
       | [Expression.Name { id; _ }] ->
         let name = Identifier.to_string id in
         if is_dunder name then None
         else
           let loc = location_of_pyre location in
           let source_text = extract_source_text source_lines loc in
           Some { name; loc; source_text }
       | _ -> None)
    (* Annotated assignment: NAME: type = value or NAME: type *)
    | Statement.AnnAssign { location; target; _ } ->
      (match target with
       | Expression.Name { id; _ } ->
         let name = Identifier.to_string id in
         if is_dunder name then None
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
