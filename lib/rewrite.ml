(** Consumer import rewriting for atomization.

    When a file is atomized, consumers that imported "re-exports" break.
    This module detects such imports and rewrites them to use original sources.
*)

(** Classification of an imported name *)
type import_classification =
  | Definition
  | Reexport of { original_module : string }
  | Unknown

(** A single imported name with metadata *)
type import_name = {
  name : string;
  original_name : string;
  has_alias : bool;
}

(** A parsed import statement from a consumer file *)
type consumer_import = {
  target_module : string;
  names : import_name list;
  start_row : int;
  start_col : int;
  end_row : int;
  end_col : int;
  is_relative : bool;
  has_star : bool;
}

(** A rewrite to apply to a file *)
type rewrite = {
  file_path : string;
  start_row : int;
  start_col : int;
  end_row : int;
  end_col : int;
  old_text : string;
  new_text : string;
}

(** Details about imports fixed in a single file *)
type import_fix_detail = {
  file_path : string;
  names_moved : (string * string * string) list;  (** (name, from_module, to_module) *)
}

(** Result of attempting to fix consumer imports *)
type fix_result =
  | Fixed of { rewrites : rewrite list; files_changed : int; details : import_fix_detail list }
  | StarImportError of { file : string; line : int }
  | Error of string

(** Helper: check if string starts with prefix *)
let starts_with s prefix =
  String.length s >= String.length prefix &&
  String.sub s 0 (String.length prefix) = prefix

(** Find the git repository root containing a path *)
let find_git_root path =
  let cmd = Printf.sprintf "cd %s && git rev-parse --show-toplevel 2>/dev/null"
    (Filename.quote (if Sys.is_directory path then path else Filename.dirname path)) in
  let ic = Unix.open_process_in cmd in
  let result =
    try
      let line = input_line ic in
      Some (String.trim line)
    with End_of_file -> None
  in
  let _ = Unix.close_process_in ic in
  result

(** Find all Python files tracked by git *)
let find_python_files root =
  let cmd = Printf.sprintf "cd %s && git ls-files '*.py' 2>/dev/null"
    (Filename.quote root) in
  let ic = Unix.open_process_in cmd in
  let files = ref [] in
  (try
    while true do
      let line = input_line ic in
      files := (String.trim line) :: !files
    done
  with End_of_file -> ());
  let _ = Unix.close_process_in ic in
  List.rev !files

(** Convert file path to Python module path *)
let module_path_of_file ~root file =
  (* Remove root prefix if present *)
  let relative =
    if starts_with file root then
      let len = String.length root in
      let rest = String.sub file len (String.length file - len) in
      if String.length rest > 0 && rest.[0] = '/' then
        String.sub rest 1 (String.length rest - 1)
      else rest
    else file
  in
  (* Remove .py extension *)
  let without_ext =
    if Filename.check_suffix relative ".py" then
      Filename.chop_suffix relative ".py"
    else relative
  in
  (* Handle __init__.py -> just the directory *)
  let module_path =
    if Filename.basename without_ext = "__init__" then
      Filename.dirname without_ext
    else
      without_ext
  in
  (* Convert slashes to dots *)
  String.map (fun c -> if c = '/' then '.' else c) module_path

(** Count leading dots in a module reference *)
let count_leading_dots s =
  let len = String.length s in
  let rec count i =
    if i >= len then i
    else if s.[i] = '.' then count (i + 1)
    else i
  in
  count 0

(** Resolve a relative import to an absolute module path *)
let resolve_relative_import ~from_file ~module_ref =
  let dots = count_leading_dots module_ref in
  if dots = 0 then
    (* Absolute import *)
    module_ref
  else
    (* Relative import - compute base from file location *)
    let from_dir = Filename.dirname from_file in
    let parts = String.split_on_char '/' from_dir in
    let parts = List.filter (fun s -> s <> "" && s <> ".") parts in
    (* Go up (dots - 1) levels from the file's directory *)
    let levels_up = dots - 1 in
    let rec drop_last n lst =
      if n <= 0 then lst
      else match List.rev lst with
        | [] -> []
        | _ :: rest -> drop_last (n - 1) (List.rev rest)
    in
    let base_parts = drop_last levels_up parts in
    let base = String.concat "." base_parts in
    (* Add the module path after the dots *)
    let after_dots =
      if dots < String.length module_ref then
        String.sub module_ref dots (String.length module_ref - dots)
      else ""
    in
    if after_dots = "" then base
    else if base = "" then after_dots
    else base ^ "." ^ after_dots

(** Grammar filename varies by platform *)
let grammar_file =
  let ic = Unix.open_process_in "uname -s" in
  let os = try input_line ic with End_of_file -> "Unknown" in
  let _ = Unix.close_process_in ic in
  if os = "Darwin" then "python.dylib" else "python.so"

(** Resource directory - detected at runtime *)
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

(** Regex for parsing tree-sitter query capture output *)
let re_capture = Re.Pcre.regexp
  {|capture: \d+ - ([^,]+), start: \((\d+), (\d+)\), end: \((\d+), (\d+)\), text: `([^`]*)`|}

(** Run tree-sitter import query on source and parse results *)
let run_import_query source =
  let tmp_file = Filename.temp_file "atomyst_import_" ".py" in
  let oc = open_out tmp_file in
  output_string oc source;
  close_out oc;
  let dylib = Filename.concat resource_dir grammar_file in
  let query = Filename.concat resource_dir "queries/consumer_imports.scm" in
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
  Sys.remove tmp_file;
  Buffer.contents buf

(** Parse a single capture line from tree-sitter output *)
type raw_capture = {
  capture_name : string;
  start_row : int;
  start_col : int;
  end_row : int;
  end_col : int;
  text : string;
}

let parse_capture_line line =
  match Re.exec_opt re_capture line with
  | None -> None
  | Some groups ->
    Some {
      capture_name = Re.Group.get groups 1;
      start_row = int_of_string (Re.Group.get groups 2);
      start_col = int_of_string (Re.Group.get groups 3);
      end_row = int_of_string (Re.Group.get groups 4);
      end_col = int_of_string (Re.Group.get groups 5);
      text = Re.Group.get groups 6;
    }

(** Parse all captures from tree-sitter output *)
let parse_all_captures output =
  let lines = String.split_on_char '\n' output in
  List.filter_map (fun line ->
    let trimmed = String.trim line in
    if starts_with trimmed "capture:" then
      parse_capture_line trimmed
    else
      None
  ) lines

(** Group captures by import statement position.
    Since the same statement appears multiple times (once per name),
    we need to merge all names for each unique statement position. *)
let group_by_statement captures =
  (* Key: (start_row, start_col, end_row, end_col) *)
  let tbl = Hashtbl.create 16 in
  List.iter (fun cap ->
    if cap.capture_name = "import.statement" then begin
      let key = (cap.start_row, cap.start_col, cap.end_row, cap.end_col) in
      if not (Hashtbl.mem tbl key) then
        Hashtbl.add tbl key { cap with capture_name = "import.statement" }
    end
  ) captures;
  (* Now collect all captures for each statement *)
  Hashtbl.fold (fun key stmt acc ->
    let (sr, _sc, er, _ec) = key in
    (* Find all captures that belong to this statement *)
    let related = List.filter (fun c ->
      c.start_row >= sr && c.start_row <= er &&
      (c.capture_name = "import.module" ||
       c.capture_name = "import.name" ||
       c.capture_name = "import.original" ||
       c.capture_name = "import.alias" ||
       c.capture_name = "import.star")
    ) captures in
    (stmt :: related) :: acc
  ) tbl []

(** Build consumer_import from grouped captures *)
let build_consumer_import captures =
  let find_capture name =
    List.find_opt (fun c -> c.capture_name = name) captures
  in
  match find_capture "import.statement" with
  | None -> None
  | Some stmt ->
    let module_cap = find_capture "import.module" in
    let target_module = match module_cap with
      | Some c -> c.text
      | None -> ""
    in
    let is_relative = String.length target_module > 0 && target_module.[0] = '.' in
    (* Check for star import *)
    let has_star =
      List.exists (fun c -> c.capture_name = "import.star") captures
    in
    (* Collect all imported names and aliases *)
    let name_captures =
      List.filter (fun c -> c.capture_name = "import.name") captures
    in
    let original_captures =
      List.filter (fun c -> c.capture_name = "import.original") captures
    in
    let alias_captures =
      List.filter (fun c -> c.capture_name = "import.alias") captures
    in
    (* Build import names *)
    let names =
      (* First add aliased imports *)
      let aliased = List.map2 (fun orig alias ->
        { name = alias.text; original_name = orig.text; has_alias = true }
      ) original_captures alias_captures in
      (* Then add simple names *)
      let simple = List.map (fun c ->
        { name = c.text; original_name = c.text; has_alias = false }
      ) name_captures in
      aliased @ simple
    in
    Some {
      target_module;
      names;
      start_row = stmt.start_row;
      start_col = stmt.start_col;
      end_row = stmt.end_row;
      end_col = stmt.end_col;
      is_relative;
      has_star;
    }

(** Get the last component of a dotted module path *)
let module_basename module_path =
  match List.rev (String.split_on_char '.' module_path) with
  | last :: _ -> last
  | [] -> module_path

(** Check if a string ends with a suffix *)
let ends_with s suffix =
  let s_len = String.length s in
  let suffix_len = String.length suffix in
  s_len >= suffix_len &&
  String.sub s (s_len - suffix_len) suffix_len = suffix

(** Find all imports in consumer source that reference the target module *)
let find_imports_from_module ~consumer_source ~target_module =
  let output = run_import_query consumer_source in
  let all_captures = parse_all_captures output in
  let grouped = group_by_statement all_captures in
  let imports = List.filter_map build_consumer_import grouped in
  (* Filter to imports from target module *)
  List.filter (fun imp ->
    imp.target_module = target_module ||
    (* Handle relative imports ending with the module name *)
    (imp.is_relative &&
     let module_name = module_basename target_module in
     ends_with imp.target_module ("." ^ module_name))
  ) imports

(** Classify an import name *)
let classify_import_name ~name ~defined_names ~reexports =
  if List.mem name defined_names then
    Definition
  else
    match List.assoc_opt name reexports with
    | Some original_module -> Reexport { original_module }
    | None -> Unknown

(** Generate replacement import text *)
let generate_replacement_imports ~import ~classifications =
  (* Group names by their classification *)
  let definitions = ref [] in
  let by_module = Hashtbl.create 8 in
  let unknowns = ref [] in
  List.iter (fun (name, classification) ->
    let import_name =
      List.find (fun n -> n.name = name || n.original_name = name) import.names
    in
    match classification with
    | Definition ->
      definitions := import_name :: !definitions
    | Reexport { original_module } ->
      let existing = try Hashtbl.find by_module original_module with Not_found -> [] in
      Hashtbl.replace by_module original_module (import_name :: existing)
    | Unknown ->
      unknowns := import_name :: !unknowns
  ) classifications;

  let buf = Buffer.create 128 in

  (* Generate import for definitions (keep original module) *)
  if !definitions <> [] then begin
    let names = List.rev !definitions in
    let name_strs = List.map (fun n ->
      if n.has_alias then
        Printf.sprintf "%s as %s" n.original_name n.name
      else
        n.name
    ) names in
    Buffer.add_string buf (Printf.sprintf "from %s import %s\n"
      import.target_module
      (String.concat ", " name_strs))
  end;

  (* Generate imports for re-exports grouped by original module *)
  Hashtbl.iter (fun original_module names ->
    let names = List.rev names in
    let name_strs = List.map (fun n ->
      if n.has_alias then
        Printf.sprintf "%s as %s" n.original_name n.name
      else
        n.name
    ) names in
    Buffer.add_string buf (Printf.sprintf "from %s import %s\n"
      original_module
      (String.concat ", " name_strs))
  ) by_module;

  (* Generate import for unknowns (keep in original module with comment) *)
  if !unknowns <> [] then begin
    let names = List.rev !unknowns in
    let name_strs = List.map (fun n ->
      if n.has_alias then
        Printf.sprintf "%s as %s" n.original_name n.name
      else
        n.name
    ) names in
    Buffer.add_string buf (Printf.sprintf "from %s import %s  # TODO: verify source\n"
      import.target_module
      (String.concat ", " name_strs))
  end;

  (* Remove trailing newline to match original format *)
  let result = Buffer.contents buf in
  if String.length result > 0 && result.[String.length result - 1] = '\n' then
    String.sub result 0 (String.length result - 1)
  else
    result

(** Apply rewrites to a file atomically *)
let apply_rewrites ~file_path ~rewrites =
  if rewrites = [] then ()
  else begin
    (* Read file content *)
    let ic = open_in file_path in
    let content = really_input_string ic (in_channel_length ic) in
    close_in ic;

    (* Sort rewrites by position (descending) to preserve offsets *)
    let sorted = List.sort (fun (r1 : rewrite) (r2 : rewrite) ->
      let cmp = compare r2.start_row r1.start_row in
      if cmp <> 0 then cmp else compare r2.start_col r1.start_col
    ) rewrites in

    (* Split content into lines *)
    let lines = Array.of_list (String.split_on_char '\n' content) in

    (* Apply each rewrite *)
    let apply_one (rw : rewrite) =
      (* For simplicity, we'll rebuild the affected lines *)
      if rw.start_row = rw.end_row then begin
        (* Single line rewrite *)
        let line = lines.(rw.start_row) in
        let before = String.sub line 0 rw.start_col in
        let after =
          if rw.end_col < String.length line then
            String.sub line rw.end_col (String.length line - rw.end_col)
          else ""
        in
        lines.(rw.start_row) <- before ^ rw.new_text ^ after
      end else begin
        (* Multi-line rewrite - replace first line, clear middle, update last *)
        let first_line = lines.(rw.start_row) in
        let last_line = lines.(rw.end_row) in
        let before = String.sub first_line 0 rw.start_col in
        let after =
          if rw.end_col < String.length last_line then
            String.sub last_line rw.end_col (String.length last_line - rw.end_col)
          else ""
        in
        (* Set first line to merged content *)
        lines.(rw.start_row) <- before ^ rw.new_text ^ after;
        (* Mark middle/last lines for removal *)
        for i = rw.start_row + 1 to rw.end_row do
          lines.(i) <- "\x00REMOVE\x00"
        done
      end
    in
    List.iter apply_one sorted;

    (* Rebuild content, filtering removed lines *)
    let final_lines = Array.to_list lines
      |> List.filter (fun l -> l <> "\x00REMOVE\x00")
    in
    let new_content = String.concat "\n" final_lines in

    (* Write atomically *)
    let tmp_file = file_path ^ ".tmp" in
    let oc = open_out tmp_file in
    output_string oc new_content;
    close_out oc;
    Unix.rename tmp_file file_path
  end

(** Fix consumer imports after atomization *)
let fix_consumer_imports ~atomized_file ~defined_names ~reexports =
  match find_git_root atomized_file with
  | None -> Error "Not in a git repository"
  | Some root ->
    let python_files = find_python_files root in
    let atomized_module = module_path_of_file ~root atomized_file in

    let all_rewrites = ref [] in
    let all_details = ref [] in
    let files_changed = ref 0 in

    (* Process each Python file *)
    let rec process_files = function
      | [] -> Fixed { rewrites = !all_rewrites; files_changed = !files_changed; details = !all_details }
      | file :: rest ->
        let file_path = Filename.concat root file in
        (* Skip the atomized file itself *)
        if file_path = atomized_file then
          process_files rest
        else begin
          let ic = open_in file_path in
          let source = really_input_string ic (in_channel_length ic) in
          close_in ic;

          let imports = find_imports_from_module ~consumer_source:source ~target_module:atomized_module in

          (* Check for star imports first *)
          match List.find_opt (fun imp -> imp.has_star) imports with
          | Some star_import ->
            StarImportError { file = file_path; line = star_import.start_row + 1 }
          | None ->
            (* Track names moved for this file *)
            let file_names_moved = ref [] in

            (* Generate rewrites for each import *)
            let file_rewrites = List.filter_map (fun import ->
              let classifications = List.map (fun n ->
                (n.name, classify_import_name ~name:n.name ~defined_names ~reexports)
              ) import.names in

              (* Skip if all names are definitions (no change needed) *)
              let needs_rewrite = List.exists (fun (_, c) ->
                match c with Definition -> false | _ -> true
              ) classifications in

              if not needs_rewrite then None
              else begin
                (* Track which names moved where *)
                List.iter (fun (name, classification) ->
                  match classification with
                  | Reexport { original_module } ->
                    file_names_moved := (name, import.target_module, original_module) :: !file_names_moved
                  | _ -> ()
                ) classifications;

                let new_text = generate_replacement_imports ~import ~classifications in
                (* Get old text from source *)
                let lines = Array.of_list (String.split_on_char '\n' source) in
                let old_text =
                  if import.start_row = import.end_row then
                    let line = lines.(import.start_row) in
                    String.sub line import.start_col (import.end_col - import.start_col)
                  else
                    (* Multi-line *)
                    let buf = Buffer.create 128 in
                    for i = import.start_row to import.end_row do
                      if i = import.start_row then
                        Buffer.add_string buf (String.sub lines.(i) import.start_col
                          (String.length lines.(i) - import.start_col))
                      else if i = import.end_row then
                        Buffer.add_string buf ("\n" ^ String.sub lines.(i) 0 import.end_col)
                      else
                        Buffer.add_string buf ("\n" ^ lines.(i))
                    done;
                    Buffer.contents buf
                in
                Some {
                  file_path;
                  start_row = import.start_row;
                  start_col = import.start_col;
                  end_row = import.end_row;
                  end_col = import.end_col;
                  old_text;
                  new_text;
                }
              end
            ) imports in

            if file_rewrites <> [] then begin
              all_rewrites := file_rewrites @ !all_rewrites;
              all_details := { file_path; names_moved = List.rev !file_names_moved } :: !all_details;
              incr files_changed;
              (* Apply rewrites to file *)
              apply_rewrites ~file_path ~rewrites:file_rewrites
            end;
            process_files rest
        end
    in
    process_files python_files
