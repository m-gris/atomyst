(** Source code extraction using tree-sitter. *)

open Types

(** Grammar filename varies by platform. *)
let grammar_file =
  let ic = Unix.open_process_in "uname -s" in
  let os = try input_line ic with End_of_file -> "Unknown" in
  let _ = Unix.close_process_in ic in
  if os = "Darwin" then "python.dylib" else "python.so"

(** Resource directory - detected at runtime.
    Search order:
    1. ATOMYST_HOME environment variable
    2. Directory containing the binary (installed bundle)
    3. Walk up from cwd (development) *)
let resource_dir =
  let has_grammar dir = Sys.file_exists (Filename.concat dir grammar_file) in
  match Sys.getenv_opt "ATOMYST_HOME" with
  | Some dir when has_grammar dir -> dir
  | _ ->
    let exe_dir = Filename.dirname Sys.executable_name in
    if has_grammar exe_dir then exe_dir
    else
      let rec find_root dir =
        if has_grammar dir then dir
        else
          let parent = Filename.dirname dir in
          if parent = dir then
            failwith (Printf.sprintf
              "Cannot find %s. Set ATOMYST_HOME or install properly." grammar_file)
          else find_root parent
      in
      find_root (Sys.getcwd ())

(** Run tree-sitter query on source and return raw output.
    Writes source to a temp file, runs tree-sitter query, returns stdout. *)
let run_tree_sitter_query source =
  (* Write source to temp file *)
  let tmp_file = Filename.temp_file "atomyst_" ".py" in
  let oc = open_out tmp_file in
  output_string oc source;
  close_out oc;
  (* Run tree-sitter query with absolute paths *)
  let dylib = Filename.concat resource_dir "python.dylib" in
  let query = Filename.concat resource_dir "queries/definitions.scm" in
  let cmd = Printf.sprintf
    "tree-sitter query --lib-path %s --lang-name python %s %s 2>&1"
    (Filename.quote dylib)
    (Filename.quote query)
    (Filename.quote tmp_file)
  in
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 4096 in
  (try
    while true do
      Buffer.add_channel buf ic 1
    done
  with End_of_file -> ());
  let _ = Unix.close_process_in ic in
  (* Clean up temp file *)
  Sys.remove tmp_file;
  Buffer.contents buf

(** Raw capture from tree-sitter output *)
type raw_capture = {
  name : string;
  kind : definition_kind;
  start_row : int;
  start_col : int;
  end_row : int;
}

(** Regex for parsing "capture: class.def, start: (0, 0), end: (1, 8)" *)
let re_def_capture = Re.Pcre.regexp
  {|capture: (class|func)\.def, start: \((\d+), (\d+)\), end: \((\d+), \d+\)|}

(** Regex for parsing "capture: 0 - class.name, ... text: `Foo`" *)
let re_name_capture = Re.Pcre.regexp
  {|capture: \d+ - (class|func)\.name, .* text: `([^`]+)`|}

(** Parse tree-sitter query output into raw captures.
    Each capture combines a def range with a name.
    Rows/cols are 0-indexed as tree-sitter reports them. *)
let parse_query_output output =
  let lines = String.split_on_char '\n' output in
  (* Parse in pairs: def line followed by name line *)
  let rec parse_patterns acc = function
    | [] -> List.rev acc
    | def_line :: name_line :: rest ->
      (match Re.exec_opt re_def_capture def_line, Re.exec_opt re_name_capture name_line with
       | Some def_match, Some name_match ->
         let kind_str = Re.Group.get def_match 1 in
         let kind = if kind_str = "class" then Class else Function in
         let start_row = int_of_string (Re.Group.get def_match 2) in
         let start_col = int_of_string (Re.Group.get def_match 3) in
         let end_row = int_of_string (Re.Group.get def_match 4) in
         let name = Re.Group.get name_match 2 in
         let capture = { name; kind; start_row; start_col; end_row } in
         parse_patterns (capture :: acc) rest
       | _ -> parse_patterns acc (name_line :: rest))  (* Skip unmatched lines *)
    | _ :: rest -> parse_patterns acc rest
  in
  parse_patterns [] lines

(** Filter to top-level definitions (start_col = 0) *)
let filter_top_level captures =
  List.filter (fun c -> c.start_col = 0) captures

(** Deduplicate by name, keeping earliest start_row for each name.
    This handles the case where decorated_definition and inner definition
    both match - we want the decorated one (earlier start). *)
let dedupe_by_name captures =
  (* Group by name, keeping earliest *)
  let tbl = Hashtbl.create 16 in
  List.iter (fun c ->
    match Hashtbl.find_opt tbl c.name with
    | None -> Hashtbl.add tbl c.name c
    | Some existing when c.start_row < existing.start_row ->
      Hashtbl.replace tbl c.name c
    | Some _ -> ()
  ) captures;
  (* Extract and sort by start_row *)
  Hashtbl.fold (fun _ c acc -> c :: acc) tbl []
  |> List.sort (fun a b -> compare a.start_row b.start_row)

(** Convert captures to definition records, converting to 1-indexed lines *)
let to_definitions captures : definition list =
  List.map (fun c ->
    { name = c.name;
      kind = c.kind;
      start_line = c.start_row + 1;  (* 0-indexed to 1-indexed *)
      end_line = c.end_row + 1;
    }
  ) captures

let extract_definitions source =
  source
  |> run_tree_sitter_query
  |> parse_query_output
  |> filter_top_level
  |> dedupe_by_name
  |> to_definitions

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
      (* If we're before imports, skip docstring content (module-level docstring) *)
      if not state.in_imports then
        { state with
          in_docstring = not closes_docstring;
          docstring_delim = if closes_docstring then None else state.docstring_delim }
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
        (* Skip module docstrings - just track if multi-line *)
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
  { lines = List.rev final_state.result;
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

(** Regex for "from X import Y" - captures module and name *)
let re_from_import = Re.Pcre.regexp
  {|^\s*from\s+([.\w]+)\s+import\s+(.+)$|}

(** Regex for "import X" *)
let re_import = Re.Pcre.regexp
  {|^\s*import\s+(.+)$|}

(** Strip trailing comment from a string *)
let strip_comment s =
  match String.index_opt s '#' with
  | Some idx -> String.sub s 0 idx
  | None -> s

(** Parse a single name from import list, handling "X as Y" *)
let parse_import_name s =
  let s = String.trim (strip_comment s) in
  (* Handle "X as Y" - return Y as the name *)
  match String.split_on_char ' ' s with
  | [name; "as"; alias] -> Some (String.trim name, String.trim alias)
  | [name] when String.length name > 0 -> Some (name, name)
  | _ -> None

(** Parse import names from a "from X import Y, Z" statement *)
let parse_from_import module_path names_str =
  let is_relative = String.length module_path > 0 && module_path.[0] = '.' in
  (* Split by comma, handling possible multi-line with parens *)
  let names_str =
    (* Remove parens if present *)
    let s = String.trim names_str in
    let s = if starts_with s "(" then String.sub s 1 (String.length s - 1) else s in
    let s = if ends_with s ")" then String.sub s 0 (String.length s - 1) else s in
    s
  in
  let parts = String.split_on_char ',' names_str in
  List.filter_map (fun part ->
    match parse_import_name part with
    | Some (_original, alias) ->
      Some { module_path; name = alias; is_relative }
    | None -> None
  ) parts

(** Join multi-line imports (parenthesized) into single lines.
    Tracks open parens and joins lines until closing paren. *)
let join_multiline_imports lines =
  let rec loop acc current_stmt in_parens = function
    | [] ->
      (* Flush any remaining statement *)
      if current_stmt <> "" then List.rev (current_stmt :: acc)
      else List.rev acc
    | line :: rest ->
      let trimmed = String.trim (strip_comment line) in
      if in_parens then begin
        (* Inside parentheses - append to current statement *)
        let new_stmt = current_stmt ^ " " ^ trimmed in
        if String.contains trimmed ')' then
          (* Closing paren - statement complete *)
          loop (new_stmt :: acc) "" false rest
        else
          loop acc new_stmt true rest
      end else if starts_with trimmed "from " && String.contains trimmed '(' && not (String.contains trimmed ')') then
        (* Opening paren without closing - start multi-line *)
        loop acc trimmed true rest
      else
        (* Regular single-line statement *)
        loop (trimmed :: acc) "" false rest
  in
  loop [] "" false lines

(** Extract imported names from import lines.
    Returns list of parsed imports with module path and name. *)
let parse_import_names (import_lines : string list) : parsed_import list =
  let full_text = String.concat "" import_lines in
  (* Normalize: remove line continuations and join lines *)
  let lines = String.split_on_char '\n' full_text in
  let lines = List.filter (fun s -> String.trim s <> "") lines in
  (* Join multi-line parenthesized imports into single lines *)
  let lines = join_multiline_imports lines in

  List.concat_map (fun line ->
    let line = String.trim line in
    (* Skip continuation lines starting with names (handled by parent) *)
    if not (starts_with line "from ") && not (starts_with line "import ") then []
    else match Re.exec_opt re_from_import line with
    | Some groups ->
      let module_path = Re.Group.get groups 1 in
      let names = Re.Group.get groups 2 in
      parse_from_import module_path names
    | None ->
      match Re.exec_opt re_import line with
      | Some groups ->
        let names = Re.Group.get groups 1 in
        let parts = String.split_on_char ',' names in
        List.filter_map (fun part ->
          match parse_import_name part with
          | Some (_original, alias) ->
            Some { module_path = alias; name = alias; is_relative = false }
          | None -> None
        ) parts
      | None -> []
  ) lines

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
