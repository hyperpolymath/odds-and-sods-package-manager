;; SPDX-License-Identifier: MPL-2.0
;; Guix development environment.
;; Usage: guix shell -D -f guix.scm

(use-modules (guix packages)
             (guix build-system gnu)
             (guix licenses)
             (gnu packages base)
             (gnu packages bash)
             (gnu packages base)
             (gnu packages java)
             (gnu packages rust)
             (gnu packages cmake)
             (gnu packages zig)
             (gnu packages golang)
             (gnu packages node)
             (gnu packages erlang)
             (gnu packages elixir)
             (gnu packages python))

(package
  (name "odds-and-sods-package-manager")
  (version "0.1.0")
  (source #f)
  (build-system gnu-build-system)
  (inputs (list coreutils bash  make openjdk rust cmake zig go node erlang elixir python))
  (synopsis "odds-and-sods-package-manager")
  (description "odds-and-sods-package-manager — part of the hyperpolymath ecosystem.")
  (home-page "https://github.com/hyperpolymath/odds-and-sods-package-manager")
  (license ((@@ (guix licenses) license) "MPL-2.0" "https://github.com/hyperpolymath/palimpsest-license")))
