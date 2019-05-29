{ nixpkgs ? (import ./nix/nixpkgs.nix).nixpkgs {},
  test-dvm ? true,
  dvm ? null,
  export-shell ? false,
}:

let llvm = import ./nix/llvm.nix { system = nixpkgs.system; }; in

let stdenv = nixpkgs.stdenv; in

let sourceByRegex = src: regexes: builtins.path
  { name = "actorscript";
    path = src;
    filter = path: type:
      let relPath = nixpkgs.lib.removePrefix (toString src + "/") (toString path); in
      let match = builtins.match (nixpkgs.lib.strings.concatStringsSep "|" regexes); in
      ( type == "directory"  &&  match (relPath + "/") != null || match relPath != null);
  }; in

let ocaml_wasm = import ./nix/ocaml-wasm.nix {
  inherit (nixpkgs) stdenv fetchFromGitHub ocaml;
  inherit (nixpkgs.ocamlPackages) findlib ocamlbuild;
}; in

let ocaml_vlq = import ./nix/ocaml-vlq.nix {
  inherit (nixpkgs) stdenv fetchFromGitHub ocaml dune;
  inherit (nixpkgs.ocamlPackages) findlib;
}; in

let ocaml_bisect_ppx = import ./nix/ocaml-bisect_ppx.nix nixpkgs; in
let ocaml_bisect_ppx-ocamlbuild = import ./nix/ocaml-bisect_ppx-ocamlbuild.nix nixpkgs; in

let ocamlbuild-atdgen = import ./nix/ocamlbuild-atdgen.nix nixpkgs; in

# Include dvm
let real-dvm =
  if dvm == null
  then
    if test-dvm
    then
      let dev = builtins.fetchGit {
        url = "ssh://git@github.com/dfinity-lab/dev";
        ref = "master";
        rev = "65c295edfc4164ca89c129d501a403fa246d3d36";
      }; in
      (import dev { system = nixpkgs.system; }).dvm
    else null
  else dvm; in

let commonBuildInputs = [
  nixpkgs.ocaml
  nixpkgs.ocamlPackages.atdgen
  nixpkgs.ocamlPackages.base
  nixpkgs.ocamlPackages.menhir
  nixpkgs.ocamlPackages.findlib
  nixpkgs.ocamlPackages.ocamlbuild
  nixpkgs.ocamlPackages.num
  nixpkgs.ocamlPackages.stdint
  ocaml_wasm
  ocaml_vlq
  nixpkgs.ocamlPackages.zarith
  nixpkgs.ocamlPackages.yojson
  ocaml_bisect_ppx
  ocaml_bisect_ppx-ocamlbuild
  ocamlbuild-atdgen
]; in

let
  test_files = [
    "test/"
    "test/.*Makefile.*"
    "test/quick.mk"
    "test/(fail|run|run-dfinity|repl|ld|idl)/"
    "test/(fail|run|run-dfinity|repl|ld|idl)/lib/"
    "test/(fail|run|run-dfinity|repl|ld|idl)/lib/dir/"
    "test/(fail|run|run-dfinity|repl|ld|idl)/.*.as"
    "test/(fail|run|run-dfinity|repl|ld|idl)/.*.sh"
    "test/(fail|run|run-dfinity|repl|ld|idl)/.*.didl"
    "test/(fail|run|run-dfinity|repl|ld|idl)/[^/]*.wat"
    "test/(fail|run|run-dfinity|repl|ld|idl)/[^/]*.c"
    "test/(fail|run|run-dfinity|repl|ld|idl)/ok/"
    "test/(fail|run|run-dfinity|repl|ld|idl)/ok/.*.ok"
    "test/.*.sh"
  ];
  samples_files = [
    "samples/"
    "samples/.*"
  ];
  stdlib_files = [
    "stdlib/"
    "stdlib/.*Makefile.*"
    "stdlib/.*.as"
    "stdlib/examples/"
    "stdlib/examples/.*.as"
    "stdlib/examples/produce-exchange/"
    "stdlib/examples/produce-exchange/.*.as"
    "stdlib/examples/produce-exchange/test/"
    "stdlib/examples/produce-exchange/test/.*.as"
  ];
  stdlib_doc_files = [
    "stdlib/.*\.py"
    "stdlib/README.md"
    "stdlib/examples/produce-exchange/README.md"
  ];

  libtommath = nixpkgs.fetchFromGitHub {
    owner = "libtom";
    repo = "libtommath";
    rev = "9e1a75cfdc4de614eaf4f88c52d8faf384e54dd0";
    sha256 = "0qwmzmp3a2rg47pnrsls99jpk5cjj92m75alh1kfhcg104qq6w3d";
  };

  llvmBuildInputs = [
    llvm.clang_9
    llvm.lld_9
  ];

  llvmEnv = ''
    export CLANG="clang-9"
    export WASM_LD=wasm-ld
  '';
in

rec {

  rts = stdenv.mkDerivation {
    name = "asc-rts";

    src = sourceByRegex ./rts [
      "rts.c"
      "Makefile"
      "includes/"
      "includes/.*.h"
      ];

    nativeBuildInputs = [ nixpkgs.makeWrapper ];

    buildInputs = llvmBuildInputs;

    preBuild = ''
      ${llvmEnv}
      export TOMMATHSRC=${libtommath}
    '';

    installPhase = ''
      mkdir -p $out/rts
      cp as-rts.wasm $out/rts
    '';
  };

  asc-bin = stdenv.mkDerivation {
    name = "asc-bin";

    src = sourceByRegex ./src [
      "Makefile.*"
      "(lsp/)?(.*\.(atd|ml|mli|mll|mlpack|mly))?"
      "_tags"
      ];

    buildInputs = commonBuildInputs;

    buildPhase = ''
      make BUILD=native asc as-ld
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp asc $out/bin
      cp as-ld $out/bin
    '';
  };

  asc = nixpkgs.symlinkJoin {
    name = "asc";
    paths = [ asc-bin rts ];
    buildInputs = [ nixpkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/asc \
        --set-default ASC_RTS "$out/rts/as-rts.wasm"
    '';
  };

  tests = stdenv.mkDerivation {
    name = "tests";

    src = sourceByRegex ./. (
      test_files ++
      samples_files
    );

    buildInputs =
      [ asc
        idlc
        ocaml_wasm
        nixpkgs.wabt
        nixpkgs.bash
        nixpkgs.perl
        filecheck
      ] ++
      (if test-dvm then [ real-dvm ] else []) ++
      llvmBuildInputs;

    buildPhase = ''
        patchShebangs .
        ${llvmEnv}
        export ASC=asc
        export AS_LD=as-ld
        export IDLC=idlc
        asc --version
        make -C samples all
      '' +
      (if test-dvm then ''
        make -C test parallel
      '' else ''
        make -C test quick
      '');

    installPhase = ''
      mkdir -p $out
    '';
  };

  asc-bin-coverage = asc-bin.overrideAttrs (oldAttrs: {
    name = "asc-bin-coverage";
    buildPhase =
      "export BISECT_COVERAGE=YES;" +
      oldAttrs.buildPhase;
    installPhase =
      oldAttrs.installPhase + ''
      # The coverage report needs access to sources, including _build/parser.ml
      cp -r . $out/src
      '';
  });

  asc-coverage = nixpkgs.symlinkJoin {
    name = "asc-covergage";
    paths = [ asc-bin-coverage rts ];
    buildInputs = [ nixpkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/asc \
        --set-default ASC_RTS "$out/rts/as-rts.wasm"
    '';
  };

  coverage-report = stdenv.mkDerivation {
    name = "coverage-report";

    src = sourceByRegex ./. (
      test_files ++
      samples_files
    );

    buildInputs =
      [ asc-coverage
        nixpkgs.wabt
        nixpkgs.bash
        nixpkgs.perl
        ocaml_bisect_ppx
      ] ++
      (if test-dvm then [ real-dvm ] else []) ++
      llvmBuildInputs;

    buildPhase = ''
      patchShebangs .
      ${llvmEnv}
      export ASC=asc
      export AS_LD=as-ld
      ln -vs ${asc-coverage}/src src
      make -C test coverage
      '';

    installPhase = ''
      mkdir -p $out
      mv test/coverage/ $out/
      mkdir -p $out/nix-support
      echo "report coverage $out/coverage index.html" >> $out/nix-support/hydra-build-products
    '';
  };


  js = asc-bin.overrideAttrs (oldAttrs: {
    name = "asc.js";

    buildInputs = commonBuildInputs ++ [
      nixpkgs.ocamlPackages.js_of_ocaml
      nixpkgs.ocamlPackages.js_of_ocaml-ocamlbuild
      nixpkgs.ocamlPackages.js_of_ocaml-ppx
      nixpkgs.nodejs-10_x
    ];

    buildPhase = ''
      make asc.js
    '';

    installPhase = ''
      mkdir -p $out
      cp -v asc.js $out
      cp -vr ${rts}/rts $out
    '';

    doInstallCheck = true;

    installCheckPhase = ''
      NODE_PATH=$out node --experimental-wasm-mut-global --experimental-wasm-mv ${./test/node-test.js}
    '';

  });

  idlc = stdenv.mkDerivation {
    name = "idlc";

    src = sourceByRegex ./idl [
      "Makefile.*"
      ".*.ml"
      ".*.mli"
      ".*.mly"
      ".*.mll"
      ".*.mlpack"
      "_tags"
      ];

    buildInputs = commonBuildInputs;

    buildPhase = ''
      make BUILD=native idlc
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp idlc $out/bin
    '';
  };

  wasm = ocaml_wasm;
  dvm = real-dvm;
  filecheck = nixpkgs.linkFarm "FileCheck"
    [ { name = "bin/FileCheck"; path = "${nixpkgs.llvm}/bin/FileCheck";} ];
  wabt = nixpkgs.wabt;


  users-guide = stdenv.mkDerivation {
    name = "users-guide";

    src = sourceByRegex ./. [
      "design/"
      "design/guide.md"
      "guide/"
      "guide/Makefile"
      "guide/.*css"
      "guide/.*md"
      "guide/.*png"
      ];

    buildInputs =
      with nixpkgs;
      let tex = texlive.combine {
        inherit (texlive) scheme-small xetex newunicodechar;
      }; in
      [ pandoc tex bash ];

    NIX_FONTCONFIG_FILE =
      with nixpkgs;
      nixpkgs.makeFontsConf { fontDirectories = [ gyre-fonts inconsolata unifont lmodern lmmath ]; };

    buildPhase = ''
      patchShebangs .
      make -C guide
    '';

    installPhase = ''
      mkdir -p $out
      mv guide $out/
      rm $out/guide/Makefile
      mkdir -p $out/nix-support
      echo "report guide $out/guide index.html" >> $out/nix-support/hydra-build-products
    '';
  };


  stdlib-reference = stdenv.mkDerivation {
    name = "stdlib-reference";

    src = sourceByRegex ./. (
      stdlib_files ++
      stdlib_doc_files
    ) + "/stdlib";

    buildInputs = with nixpkgs;
      [ pandoc bash python ];

    buildPhase = ''
      patchShebangs .
      make alldoc
    '';

    installPhase = ''
      mkdir -p $out
      mv doc $out/
      mkdir -p $out/nix-support
      echo "report docs $out/doc README.html" >> $out/nix-support/hydra-build-products
    '';

    forceShare = ["man"];
  };

  produce-exchange = stdenv.mkDerivation {
    name = "produce-exchange";
    src = sourceByRegex ./. (
      stdlib_files
    );

    buildInputs = [
      asc
    ];

    doCheck = true;
    buildPhase = ''
      make -C stdlib ASC=asc OUTDIR=_out _out/ProduceExchange.wasm
    '';
    checkPhase = ''
      make -C stdlib ASC=asc OUTDIR=_out _out/ProduceExchange.out
    '';
    installPhase = ''
      mkdir -p $out
      cp stdlib/_out/ProduceExchange.wasm $out
    '';
  };

  all-systems-go = nixpkgs.releaseTools.aggregate {
    name = "all-systems-go";
    constituents = [
      asc
      js
      idlc
      tests
      coverage-report
      rts
      stdlib-reference
      produce-exchange
      users-guide
    ];
  };

  shell = if export-shell then nixpkgs.mkShell {

    #
    # Since building asc, and testing it, are two different derivation in default.nix
    # we have to create a fake derivation for shell.nix that commons up the build dependencies
    # of the two to provide a build environment that offers both
    #
    # Would not be necessary if nix-shell would take more than one `-A` flag, see
    # https://github.com/NixOS/nix/issues/955
    #

    buildInputs = nixpkgs.lib.lists.unique (builtins.filter (i: i != asc && i != idlc) (
      asc-bin.buildInputs ++
      rts.buildInputs ++
      idlc.buildInputs ++
      tests.buildInputs ++
      users-guide.buildInputs ++
      [ nixpkgs.ncurses nixpkgs.ocamlPackages.merlin ]
    ));

    shellHook = llvmEnv;
    TOMMATHSRC = libtommath;
    NIX_FONTCONFIG_FILE = users-guide.NIX_FONTCONFIG_FILE;
  } else null;

}
