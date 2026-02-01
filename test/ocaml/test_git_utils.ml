(** Tests for Git_utils module. *)

open Atomyst

(** Create a temporary directory and return its path *)
let make_temp_dir prefix =
  let base = Filename.get_temp_dir_name () in
  let rec try_create n =
    let name = Printf.sprintf "%s_%s_%d" prefix (string_of_int (Unix.getpid ())) n in
    let path = Filename.concat base name in
    if Sys.file_exists path then try_create (n + 1)
    else begin
      Unix.mkdir path 0o755;
      path
    end
  in
  try_create 0

(** Remove directory recursively *)
let rec rm_rf path =
  if Sys.is_directory path then begin
    Array.iter (fun name -> rm_rf (Filename.concat path name)) (Sys.readdir path);
    Unix.rmdir path
  end else
    Sys.remove path

(** Run a command in a directory, fail if non-zero exit *)
let run_in_dir dir cmd =
  let full_cmd = Printf.sprintf "cd %s && %s" (Filename.quote dir) cmd in
  let exit_code = Sys.command full_cmd in
  if exit_code <> 0 then
    failwith (Printf.sprintf "Command failed with exit %d: %s" exit_code cmd)

(** Write content to a file *)
let write_file path content =
  let oc = open_out path in
  output_string oc content;
  close_out oc

(** Test: file in git repo, tracked, no changes -> Safe *)
let test_safe_tracked_clean () =
  let dir = make_temp_dir "git_utils_test" in
  Fun.protect ~finally:(fun () -> rm_rf dir) (fun () ->
    run_in_dir dir "git init";
    let file_path = Filename.concat dir "test.py" in
    write_file file_path "class Foo: pass\n";
    run_in_dir dir "git add test.py";
    run_in_dir dir "git commit -m 'initial'";
    let result = Git_utils.check_safe_to_remove file_path in
    Alcotest.(check string) "should be safe"
      "safe to remove"
      (Git_utils.safe_remove_result_to_string result)
  )

(** Test: file in git repo, tracked, has uncommitted changes -> HasUncommittedChanges *)
let test_tracked_with_changes () =
  let dir = make_temp_dir "git_utils_test" in
  Fun.protect ~finally:(fun () -> rm_rf dir) (fun () ->
    run_in_dir dir "git init";
    let file_path = Filename.concat dir "test.py" in
    write_file file_path "class Foo: pass\n";
    run_in_dir dir "git add test.py";
    run_in_dir dir "git commit -m 'initial'";
    (* Now modify the file *)
    write_file file_path "class Foo: pass\n# modified\n";
    let result = Git_utils.check_safe_to_remove file_path in
    Alcotest.(check string) "should have uncommitted changes"
      "file has uncommitted changes"
      (Git_utils.safe_remove_result_to_string result)
  )

(** Test: file in git repo, tracked, staged changes -> HasUncommittedChanges *)
let test_tracked_with_staged_changes () =
  let dir = make_temp_dir "git_utils_test" in
  Fun.protect ~finally:(fun () -> rm_rf dir) (fun () ->
    run_in_dir dir "git init";
    let file_path = Filename.concat dir "test.py" in
    write_file file_path "class Foo: pass\n";
    run_in_dir dir "git add test.py";
    run_in_dir dir "git commit -m 'initial'";
    (* Modify and stage *)
    write_file file_path "class Foo: pass\n# modified\n";
    run_in_dir dir "git add test.py";
    let result = Git_utils.check_safe_to_remove file_path in
    Alcotest.(check string) "should have uncommitted changes"
      "file has uncommitted changes"
      (Git_utils.safe_remove_result_to_string result)
  )

(** Test: file in git repo but not tracked -> NotTracked *)
let test_untracked_file () =
  let dir = make_temp_dir "git_utils_test" in
  Fun.protect ~finally:(fun () -> rm_rf dir) (fun () ->
    run_in_dir dir "git init";
    let file_path = Filename.concat dir "test.py" in
    write_file file_path "class Foo: pass\n";
    (* Don't add to git *)
    let result = Git_utils.check_safe_to_remove file_path in
    Alcotest.(check string) "should be not tracked"
      "file is not tracked by git"
      (Git_utils.safe_remove_result_to_string result)
  )

(** Test: file not in a git repo -> NotInRepo *)
let test_not_in_repo () =
  let dir = make_temp_dir "git_utils_test" in
  Fun.protect ~finally:(fun () -> rm_rf dir) (fun () ->
    (* Don't init git *)
    let file_path = Filename.concat dir "test.py" in
    write_file file_path "class Foo: pass\n";
    let result = Git_utils.check_safe_to_remove file_path in
    Alcotest.(check string) "should not be in repo"
      "not in a git repository"
      (Git_utils.safe_remove_result_to_string result)
  )

let () =
  Alcotest.run "Git_utils" [
    "check_safe_to_remove", [
      Alcotest.test_case "tracked and clean" `Quick test_safe_tracked_clean;
      Alcotest.test_case "tracked with unstaged changes" `Quick test_tracked_with_changes;
      Alcotest.test_case "tracked with staged changes" `Quick test_tracked_with_staged_changes;
      Alcotest.test_case "untracked file" `Quick test_untracked_file;
      Alcotest.test_case "not in git repo" `Quick test_not_in_repo;
    ];
  ]
