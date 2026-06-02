{
  description = "os_counters — cross-process atomic counters in LuaJIT with three backends (filesystem locking, POSIX shm, System V IPC) trading off portability vs. capability per OS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        runtimeTools = [ pkgs.luajit ];
        testTools = with pkgs; [ bashInteractive coreutils gnugrep gawk ];

        os_counters = pkgs.stdenv.mkDerivation {
          pname = "os_counters";
          version = "0.1.0";
          src = ./.;
          buildInputs = runtimeTools;
          dontBuild = true;
          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin $out/lib $out/share/os_counters/tests
            cp bin/fs-counter bin/posix-counter bin/sysv-counter $out/bin/
            cp lib/truthy.lua $out/lib/
            cp tests/counter_test $out/share/os_counters/tests/counter_test
            chmod +x $out/bin/fs-counter $out/bin/posix-counter $out/bin/sysv-counter
            # `counter` is the default (filesystem) backend
            ln -s fs-counter $out/bin/counter
            # Nix sandbox has no /usr/bin/env; resolve the luajit shebangs
            patchShebangs $out/bin
            runHook postInstall
          '';
          meta = with pkgs.lib; {
            description = "Cross-process atomic counters (LuaJIT): fs / POSIX shm / System V IPC backends";
            license = licenses.mit;
            platforms = platforms.unix;
            mainProgram = "counter";
          };
        };
      in {
        packages.default = os_counters;
        packages.os_counters = os_counters;

        # Garnix runs this. Only the fs backend is exercised hermetically: posix shm is
        # macOS-limited and sysv IPC needs elevated privileges (no sudo in the sandbox).
        # The posix/sysv backends remain runnable locally via `COUNTER_TYPE=… ./test`.
        checks.counter-test = pkgs.runCommand "counter-test"
          { nativeBuildInputs = runtimeTools ++ testTools; } ''
            cp -r ${./.} work
            chmod -R u+w work
            cd work
            patchShebangs bin tests
            export HOME="$TMPDIR"
            export PATH="$PWD/bin:$PATH"
            export COUNTER_TEST_FILE="$PWD/tests/counter_test"
            export COUNTER_TYPE=fs
            export FS_COUNTER_DIR="$TMPDIR/fs-counter"
            bash tests/counter_test
            touch $out
          '';

        devShells.default = pkgs.mkShell {
          packages = runtimeTools ++ testTools;
        };
      });
}
