pkgs:
{ drun =
    pkgs.rustPlatform_moz_stable.buildRustPackage {
      name = "drun";

      src = pkgs.sources.ic + "/rs";

      # update this after bumping the dfinity/ic pin.
      # 1. change the hash to something arbitrary (e.g. flip one digit to 0)
      # 2. run nix-build -A drun nix/
      # 3. copy the “expected” hash from the output into this file
      # 4. commit and push
      #
      # To automate this, .github/workflows/update-hash.yml has been
      # installed. You will normally not be bothered to perform
      # the command therein manually.

      cargoSha256 = "sha256-dhDXhVNAAHzLRHdA6MpIGuoY76UhiF4ObeLO4gG/wo4=";
      # sha256 = "ea803b02f2db51aaa6302492ab5fa1301e05c9def68b7eefedddad522814ed00";

      # patches = [ ./rocks1.diff ];
      patchPhase = ''
      pwd
      ls ..
      cd ../drun-vendor.tar.gz
      ls -l librocksdb-sys/build.rs
      patch librocksdb-sys/build.rs << EOF
@@ -118,6 +118,8 @@
         config.define("OS_MACOSX", Some("1"));
         config.define("ROCKSDB_PLATFORM_POSIX", Some("1"));
         config.define("ROCKSDB_LIB_IO_POSIX", Some("1"));
+        config.define("isSSE42()", Some("0"));
+        config.define("isPCLMULQDQ()", Some("0"));
     } else if target.contains("android") {
         config.define("OS_ANDROID", Some("1"));
         config.define("ROCKSDB_PLATFORM_POSIX", Some("1"));
EOF

      sed -i -e s/08d86b53188dc6f15c8dc09d8aadece72e39f145e3ae497bb8711936a916335a/b099df5e4401ea37f9c04060cfc19a9f2d78e8f3ff90ce80377ad6f0164532c1/g librocksdb-sys/.cargo-checksum.json
      cd -
      '';

      nativeBuildInputs = with pkgs; [
        pkg-config
        cmake
      ];

      buildInputs = with pkgs; [
        openssl
        llvm_13
        llvmPackages_13.libclang
        lmdb
        libunwind
      ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
        pkgs.darwin.apple_sdk.frameworks.Security
      ];

      # needed for bindgen
      LIBCLANG_PATH = "${pkgs.llvmPackages_13.libclang.lib}/lib";
      CLANG_PATH = "${pkgs.llvmPackages_13.clang}/bin/clang";

      # needed for ic-protobuf
      PROTOC="${pkgs.protobuf}/bin/protoc";

      doCheck = false;

      buildAndTestSubdir = "drun";
    };
}
