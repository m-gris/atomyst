(** Source code extraction using tree-sitter. *)

open Types

(** Project root directory - detected at runtime.
    When running from source, it's the current directory.
    When running from _build, we go up to find python.dylib. *)
let project_root =
  let rec find_root dir =
    if Sys.file_exists (Filename.concat dir "python.dylib") then dir
    else
      let parent = Filename.dirname dir in
      if parent = dir then failwith "Cannot find project root (python.dylib)"
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
  let dylib = Filename.concat project_root "python.dylib" in
  let query = Filename.concat project_root "queries/definitions.scm" in
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
}

let initial_state = {
  result = [];
  in_imports = false;
  paren_depth = 0;
  in_type_checking = false;
  type_checking_indent = 0;
  in_docstring = false;
  docstring_delim = None;
  done_extracting = false;
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
      if closes_docstring then
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

    (* Module docstring or shebang at start (before any imports) *)
    else if not state.in_imports && (
      starts_with stripped "#" ||
      starts_with stripped {|"""|} ||
      starts_with stripped "'''"
    ) then
      (* Check if it's a multi-line docstring opening *)
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
      add_line { state with
        in_docstring = Option.is_some docstring_delim;
        docstring_delim }

    (* Import statement *)
    else if starts_with stripped "import " || starts_with stripped "from " then
      let new_depth = state.paren_depth + count_char line '(' - count_char line ')' in
      add_line { state with in_imports = true; paren_depth = new_depth }

    (* Continuation of multi-line import *)
    else if state.paren_depth > 0 then
      let new_depth = state.paren_depth + count_char line '(' - count_char line ')' in
      add_line { state with paren_depth = new_depth }

    (* Empty line - include if we're in imports section *)
    else if stripped = "" then
      add_line state

    (* Non-import, non-empty line after imports started - we're done *)
    else if state.in_imports then
      { state with done_extracting = true }

    (* Non-import line before any imports - skip *)
    else
      state

(** Extract import block from beginning of file.
    Handles docstrings, shebangs, imports, multi-line imports, TYPE_CHECKING blocks.
    Pure: string list -> string list *)
let extract_imports (lines : string list) : string list =
  let final_state = List.fold_left process_line initial_state lines in
  List.rev final_state.result
