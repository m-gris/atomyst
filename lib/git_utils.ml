(** Git utilities for safe file operations. *)

type safe_remove_result =
  | Safe
  | NotInRepo
  | NotTracked
  | HasUncommittedChanges

let safe_remove_result_to_string = function
  | Safe -> "safe to remove"
  | NotInRepo -> "not in a git repository"
  | NotTracked -> "file is not tracked by git"
  | HasUncommittedChanges -> "file has uncommitted changes"

let check_safe_to_remove path =
  let dir = Filename.dirname path in
  let basename = Filename.basename path in
  (* Check if in git repo - run from file's directory *)
  let in_repo_cmd = Printf.sprintf "cd %s && git rev-parse --git-dir >/dev/null 2>&1"
    (Filename.quote dir) in
  let in_repo = Sys.command in_repo_cmd = 0 in
  if not in_repo then
    NotInRepo
  else
    (* Check if file is tracked - run from file's directory *)
    let tracked_cmd = Printf.sprintf "cd %s && git ls-files --error-unmatch %s >/dev/null 2>&1"
      (Filename.quote dir) (Filename.quote basename) in
    let is_tracked = Sys.command tracked_cmd = 0 in
    if not is_tracked then
      NotTracked
    else
      (* Check if file has uncommitted changes - run from file's directory *)
      let status_cmd = Printf.sprintf "cd %s && git status --porcelain %s 2>/dev/null"
        (Filename.quote dir) (Filename.quote basename) in
      let ic = Unix.open_process_in status_cmd in
      let output = try input_line ic with End_of_file -> "" in
      let _ = Unix.close_process_in ic in
      if output <> "" then
        HasUncommittedChanges
      else
        Safe
