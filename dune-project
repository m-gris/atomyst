(lang dune 3.0)
(name atomyst)
(version 0.1.0)

(generate_opam_files true)

(source (github m-gris/atomyst))
(authors "Marc Gris")
(maintainers "marc@gris.dev")
(license MIT)

(package
 (name atomyst)
 (synopsis "Atomize source files into one-definition-per-file structure")
 (description "Extract top-level definitions from source files into separate files, maintaining a clean directory structure with __init__.py as the public interface.")
 (depends
  (ocaml (>= 5.0))
  dune
  cmdliner
  yojson
  ppx_deriving
  re
  (alcotest :with-test)))
