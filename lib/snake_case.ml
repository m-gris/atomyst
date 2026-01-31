(** Convert PascalCase/camelCase identifiers to snake_case. *)

(** Regex: any char followed by uppercase then lowercase(s)
    Example: "HTTPServer" matches ("P", "Se") -> "HTTP_Server" *)
let re_upper_lower = Re.Pcre.regexp {|(.)([A-Z][a-z]+)|}

(** Regex: lowercase or digit followed by uppercase
    Example: "getID" matches ("t", "I") and ("I", "D") -> "get_ID" *)
let re_lower_upper = Re.Pcre.regexp {|([a-z0-9])([A-Z])|}

let to_snake_case name =
  name
  |> Re.replace re_upper_lower ~f:(fun g ->
       Re.Group.get g 1 ^ "_" ^ Re.Group.get g 2)
  |> Re.replace re_lower_upper ~f:(fun g ->
       Re.Group.get g 1 ^ "_" ^ Re.Group.get g 2)
  |> String.lowercase_ascii
