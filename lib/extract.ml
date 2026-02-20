(** Source code extraction and import handling. *)

open Types

let extract_definitions source =
  Python_parser.extract_definitions source
  |> List.map (fun (d : Python_parser.extracted_definition) ->
    { name = d.name;
      kind = d.kind;
      start_line = d.loc.start_line + 1;  (* 0-indexed to 1-indexed *)
      end_line = d.loc.end_line + 1;
    })

(** Regex for matching relative imports: from .xxx or from . import
    Captures: (1) prefix "from ", (2) dots, (3) rest of line including newline
    Note: [\s\S]* matches everything including newlines, unlike dot-star *)
let re_relative_import = Re.Pcre.regexp {|^(\s*from\s+)(\.+)([\s\S]*)|}

(** Adjust relative import depth by adding extra dots.
    For example, with depth_delta=1:
    - "from .foo import X" becomes "from ..foo import X"
    - "from . import X" becomes "from .. import X"
    - "from ..bar import Y" becomes "from ...bar import Y"
    - "import foo" is unchanged (not relative) *)
let adjust_relative_import ~depth_delta line =
  if depth_delta <= 0 then line
  else
    match Re.exec_opt re_relative_import line with
    | None -> line
    | Some groups ->
      let prefix = Re.Group.get groups 1 in  (* "from " with any leading whitespace *)
      let dots = Re.Group.get groups 2 in    (* existing dots *)
      let rest = Re.Group.get groups 3 in    (* rest of line after dots *)
      let new_dots = dots ^ String.make depth_delta '.' in
      prefix ^ new_dots ^ rest

(** Adjust all relative imports in a list of lines *)
let adjust_relative_imports ~depth_delta lines =
  if depth_delta <= 0 then lines
  else List.map (adjust_relative_import ~depth_delta) lines

(** Result of import extraction with metadata *)
type import_result = {
  lines : string list;
  docstring : string option;
  skipped_docstring : bool;
  skipped_pragmas : bool;
}

(** State for import extraction - immutable, threaded through fold *)
type import_state = {
  result : string list;       (** Accumulated lines (reversed) *)
  in_imports : bool;          (** Have we seen any imports yet? *)
  paren_depth : int;          (** Depth of parentheses for multi-line imports *)
  in_type_checking : bool;    (** Inside TYPE_CHECKING block? *)
  type_checking_indent : int; (** Indentation level of TYPE_CHECKING *)
  in_docstring : bool;        (** Inside multi-line docstring? *)
  docstring_delim : string option; (** Delimiter for current docstring *)
  docstring_lines : string list;   (** Accumulated docstring lines (reversed) *)
  done_extracting : bool;     (** Stop processing further lines *)
  saw_docstring : bool;       (** Did we see a module-level docstring? *)
  saw_pragmas : bool;         (** Did we see pragma comments? *)
  keep_pragmas : bool;        (** Should we keep pragma comments? *)
}

let make_initial_state ~keep_pragmas = {
  result = [];
  in_imports = false;
  paren_depth = 0;
  in_type_checking = false;
  type_checking_indent = 0;
  in_docstring = false;
  docstring_delim = None;
  docstring_lines = [];
  done_extracting = false;
  saw_docstring = false;
  saw_pragmas = false;
  keep_pragmas;
}

(** Helper: check if string starts with prefix *)
let starts_with s prefix =
  String.length s >= String.length prefix &&
  String.sub s 0 (String.length prefix) = prefix

(** Helper: check if string ends with suffix *)
let ends_with s suffix =
  String.length s >= String.length suffix &&
  String.sub s (String.length s - String.length suffix) (String.length suffix) = suffix

(** Helper: count occurrences of char in string *)
let count_char s c =
  String.fold_left (fun acc ch -> if ch = c then acc + 1 else acc) 0 s

(** Helper: get indentation (number of leading spaces/tabs) *)
let get_indent line =
  let len = String.length line in
  let rec count i =
    if i >= len then i
    else match line.[i] with
      | ' ' | '\t' -> count (i + 1)
      | _ -> i
  in
  count 0

(** Helper: check if a comment line is a pragma directive *)
let is_pragma stripped =
  starts_with stripped "# mypy:" ||
  starts_with stripped "# type:" ||
  starts_with stripped "# noqa" ||
  starts_with stripped "# pylint:" ||
  starts_with stripped "# ruff:" ||
  starts_with stripped "#mypy:" ||
  starts_with stripped "#type:" ||
  starts_with stripped "#noqa" ||
  starts_with stripped "#pylint:" ||
  starts_with stripped "#ruff:"

(** Process one line, returning new state *)
let process_line state line =
  if state.done_extracting then state
  else
    let stripped = String.trim line in
    let add_line s = { s with result = line :: s.result } in

    (* Handle multi-line docstring continuation *)
    if state.in_docstring then
      let closes_docstring = match state.docstring_delim with
        | Some delim -> ends_with stripped delim
        | None -> false
      in
      (* If we're before imports, capture docstring content (module-level docstring) *)
      if not state.in_imports then
        { state with
          in_docstring = not closes_docstring;
          docstring_delim = if closes_docstring then None else state.docstring_delim;
          docstring_lines = line :: state.docstring_lines }
      else if closes_docstring then
        add_line { state with in_docstring = false; docstring_delim = None }
      else
        add_line state

    (* Handle TYPE_CHECKING block *)
    else if state.in_type_checking then
      if stripped = "" then
        add_line state
      else
        let current_indent = get_indent line in
        if current_indent > state.type_checking_indent then
          add_line state
        else
          { state with in_type_checking = false; done_extracting = true }

    (* Detect start of TYPE_CHECKING block *)
    else if starts_with stripped "if TYPE_CHECKING" then
      add_line { state with
        in_type_checking = true;
        type_checking_indent = get_indent line;
        in_imports = true }

    (* Shebang, module docstring, or comment at start (before any imports) *)
    else if not state.in_imports && (
      starts_with stripped "#" ||
      starts_with stripped {|"""|} ||
      starts_with stripped "'''"
    ) then
      (* Shebang lines (#!/...) should be kept *)
      if starts_with stripped "#!" then
        add_line state
      else if starts_with stripped {|"""|} || starts_with stripped "'''" then
        (* Capture module docstrings - track if multi-line *)
        let is_multiline_open delim =
          starts_with stripped delim &&
          count_char stripped delim.[0] = 3 &&
          not (String.length stripped > 3 && ends_with stripped delim)
        in
        let docstring_delim =
          if is_multiline_open {|"""|} then Some {|"""|}
          else if is_multiline_open "'''" then Some "'''"
          else None
        in
        { state with
          in_docstring = Option.is_some docstring_delim;
          docstring_delim;
          docstring_lines = line :: state.docstring_lines;
          saw_docstring = true }
      else if is_pragma stripped then
        (* Pragma comment - keep or skip based on flag *)
        if state.keep_pragmas then
          add_line { state with saw_pragmas = true }
        else
          { state with saw_pragmas = true }
      else
        (* Skip other comments before imports *)
        state

    (* Import statement *)
    else if starts_with stripped "import " || starts_with stripped "from " then
      let new_depth = state.paren_depth + count_char line '(' - count_char line ')' in
      add_line { state with in_imports = true; paren_depth = new_depth }

    (* Continuation of multi-line import *)
    else if state.paren_depth > 0 then
      let new_depth = state.paren_depth + count_char line '(' - count_char line ')' in
      add_line { state with paren_depth = new_depth }

    (* Empty line after imports started - include it *)
    else if state.in_imports && stripped = "" then
      add_line state

    (* Non-import, non-empty line after imports started - we're done *)
    else if state.in_imports then
      { state with done_extracting = true }

    (* Empty line or other line before imports - skip *)
    else
      state

(** Extract import block from beginning of file.
    Handles docstrings, shebangs, imports, multi-line imports, TYPE_CHECKING blocks.
    Returns lines and metadata about what was skipped.
    Pure: string list -> keep_pragmas:bool -> import_result *)
let extract_imports_full ?(keep_pragmas=false) (lines : string list) : import_result =
  let initial = make_initial_state ~keep_pragmas in
  let final_state = List.fold_left process_line initial lines in
  let docstring =
    if final_state.docstring_lines = [] then None
    else Some (String.concat "" (List.rev final_state.docstring_lines))
  in
  { lines = List.rev final_state.result;
    docstring;
    skipped_docstring = final_state.saw_docstring;
    skipped_pragmas = final_state.saw_pragmas && not keep_pragmas }

(** Simple version for backwards compatibility - just returns lines *)
let extract_imports (lines : string list) : string list =
  (extract_imports_full lines).lines

(** Represents a parsed import *)
type parsed_import = {
  module_path : string;  (** The module being imported from *)
  name : string;         (** The name being imported (or alias) *)
  is_relative : bool;    (** True if relative import (starts with .) *)
}

(** Convert Python_parser import to parsed_import list.
    Uses pyre-ast for typed Python parsing. *)
let parsed_imports_of_stmt (stmt : Python_parser.import_stmt) : parsed_import list =
  match stmt with
  | Python_parser.Import { names; _ } ->
    (* "import X" - module_path is the full name *)
    List.map (fun (a : Python_parser.import_alias) ->
      let name = Option.value ~default:a.name a.asname in
      { module_path = name; name; is_relative = false }
    ) names
  | Python_parser.ImportFrom { module_; names; level; _ } ->
    (* "from X import Y" - build module_path with dots *)
    let dots = String.make level '.' in
    let module_path = match module_ with
      | Some m -> dots ^ m
      | None -> dots
    in
    let is_relative = level > 0 in
    List.map (fun (a : Python_parser.import_alias) ->
      let name = Option.value ~default:a.name a.asname in
      { module_path; name; is_relative }
    ) names

(** Extract imported names from import lines.
    Returns list of parsed imports with module path and name.
    Uses pyre-ast for typed Python parsing. *)
let parse_import_names (import_lines : string list) : parsed_import list =
  let source = String.concat "\n" import_lines in
  let stmts = Python_parser.extract_imports source in
  List.concat_map parsed_imports_of_stmt stmts

(** Find sibling definitions referenced in a definition's content.
    Uses word boundary matching to find references to other definitions.
    Returns list of definition names that are referenced. *)
let find_sibling_references ~(all_defns : definition list) ~(target_defn : definition) ~defn_content =
  (* Build list of other definition names (excluding self) *)
  let sibling_names = List.filter_map (fun (d : definition) ->
    if d.name = target_defn.name then None else Some d.name
  ) all_defns in
  (* Check which siblings appear as word in the content *)
  List.filter (fun name ->
    let pattern = Re.Pcre.regexp (Printf.sprintf {|\b%s\b|} (Re.Pcre.quote name)) in
    Re.execp pattern defn_content
  ) sibling_names

(** Find which constant names are referenced in content.
    Pure function: list filtering via word-boundary regex. *)
let find_constant_references ~constant_names ~defn_content =
  List.filter (fun name ->
    let pattern = Re.Pcre.regexp (Printf.sprintf {|\b%s\b|} (Re.Pcre.quote name)) in
    Re.execp pattern defn_content
  ) constant_names

(** Generate import lines for sibling references.
    Returns lines like "from .sibling_module import SiblingClass\n" *)
let generate_sibling_imports sibling_names =
  List.map (fun name ->
    let module_name = Snake_case.to_snake_case name in
    Printf.sprintf "from .%s import %s\n" module_name name
  ) sibling_names

(** Find where comments immediately preceding a definition begin.
    Looks backwards from start_line to find contiguous comment lines.
    Returns the adjusted start line (1-indexed). *)
let find_comment_start lines start_line =
  let arr = Array.of_list lines in
  let rec scan idx =
    if idx < 0 then idx + 2
    else
      let stripped = String.trim arr.(idx) in
      if starts_with stripped "#" then scan (idx - 1)
      else if stripped = "" then idx + 2
      else idx + 2
  in
  scan (start_line - 2)

(** Build an output file for a single definition.
    Includes import block, sibling imports, and any preceding comments. *)
let build_definition_file ~(all_defns : definition list) (defn : definition) lines import_block =
  let actual_start = find_comment_start lines defn.start_line in
  let arr = Array.of_list lines in
  let defn_lines =
    Array.sub arr (actual_start - 1) (defn.end_line - actual_start + 1)
    |> Array.to_list
  in
  let defn_content = String.concat "" defn_lines in
  (* Find and generate sibling imports *)
  let sibling_names = find_sibling_references ~all_defns ~target_defn:defn ~defn_content in
  let sibling_import_lines = generate_sibling_imports sibling_names in
  let sibling_imports = String.concat "" sibling_import_lines in
  (* Trim leading newlines from definition, then add proper spacing *)
  let trimmed_content =
    let s = defn_content in
    let len = String.length s in
    let rec find_start i =
      if i >= len then len
      else if s.[i] = '\n' then find_start (i + 1)
      else i
    in
    String.sub s (find_start 0) (len - find_start 0)
  in
  (* Combine: original imports + sibling imports + definition *)
  let imports_section =
    if sibling_imports = "" then import_block
    else import_block ^ sibling_imports
  in
  let file_content = imports_section ^ "\n\n" ^ trimmed_content in
  let filename = Snake_case.to_snake_case defn.name ^ ".py" in
  { relative_path = filename; content = file_content }

(** Extract a single definition by name from source.
    Returns None if the definition is not found.
    Pure: (string, string, ?depth_delta:int) -> extraction_result option *)
let extract_one ?(depth_delta=0) source name =
  (* Split source into lines, preserving original newline structure *)
  let lines =
    let parts = String.split_on_char '\n' source in
    (* split_on_char "a\nb\n" gives ["a"; "b"; ""] - drop the trailing empty *)
    let parts =
      if String.length source > 0 && source.[String.length source - 1] = '\n' then
        match List.rev parts with
        | "" :: rest -> List.rev rest
        | _ -> parts
      else parts
    in
    List.map (fun s -> s ^ "\n") parts
  in
  let definitions : definition list = extract_definitions source in
  let import_lines = extract_imports lines in
  let adjusted_lines = adjust_relative_imports ~depth_delta import_lines in
  let import_block = String.concat "" adjusted_lines in

  (* Find the target definition *)
  match List.find_opt (fun (d : definition) -> d.name = name) definitions with
  | None -> None
  | Some target ->
    (* Build the extracted file *)
    let extracted = build_definition_file ~all_defns:definitions target lines import_block in

    (* Build the remainder (source with definition removed) *)
    let actual_start = find_comment_start lines target.start_line in
    let arr = Array.of_list lines in
    let before = Array.sub arr 0 (actual_start - 1) |> Array.to_list in
    let after =
      if target.end_line < Array.length arr then
        Array.sub arr target.end_line (Array.length arr - target.end_line)
        |> Array.to_list
      else []
    in
    let remainder = String.concat "" (before @ after) in

    Some { extracted; remainder }
