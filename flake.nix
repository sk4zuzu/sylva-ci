{
  inputs = {
    sylva-core = {
      url = "git+https://gitlab.com/mopala/sylva-core.git?ref=capone";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, sylva-core, ... }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
    in {
      packages.x86_64-linux = rec {
        sylva-ci =
          let
            script = (pkgs.writeScriptBin "sylva-ci" (builtins.readFile ./sylva-ci.sh)).overrideAttrs(old: {
              buildCommand = "${old.buildCommand}\n patchShebangs $out";
            });
          in pkgs.symlinkJoin {
            name        = "sylva-ci";
            paths       = with pkgs; [ cowsay ddate ] ++ [ script ];
            buildInputs = [ pkgs.makeWrapper ];
            postBuild   = "wrapProgram $out/bin/sylva-ci --prefix PATH : $out/bin";
          };
        default = sylva-ci;
      };

      checks.x86_64-linux.sylva-ci = pkgs.runCommand
        "sylva-ci-test"
        { buildInputs = [ self.packages.x86_64-linux.sylva-ci ]; }
        ''
          sylva-ci '${sylva-core}'
          touch $out
        '';
    };
}
