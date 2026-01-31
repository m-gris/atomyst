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
