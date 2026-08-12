{
  description = "Plugins for AI coding harnesses: Claude Code (claude/), Codex (codex/) and Pi (pi/)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      version = "1.2.0";

      # ponytail: genAttrs instead of a flake-utils input - one line does it.
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # The whole tree is one unit: both marketplace manifests reference plugin
      # directories by path relative to the repo root, so splitting per harness
      # would break those `source` fields.
      packages = forAllSystems (pkgs: {
        default = self.packages.${pkgs.system}.claude-marketplace;

        claude-marketplace = pkgs.runCommandLocal "claude-marketplace-${version}" { } ''
          cp -R ${self} $out
          chmod -R u+w $out
        '';
      });

      checks = forAllSystems (pkgs: {
        # pi/typecheck.sh is deliberately absent: it resolves the Pi types from a
        # global npm install, which does not exist in the sandbox. Run it locally.
        hook-contracts =
          pkgs.runCommand "claude-marketplace-hook-contracts"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.jq
                pkgs.python3
              ]
              # test-project-config.sh drives the real checkers against fixture
              # projects. It skips any checker it cannot find, so without these
              # it would pass by doing nothing.
              ++ [
                pkgs.black
                pkgs.python3Packages.flake8
                pkgs.nixfmt
                pkgs.prettier
                pkgs.rustfmt
              ];
            }
            ''
              cp -R ${self} src
              chmod -R u+w src
              cd src

              bash claude/test-hook-contract.sh
              bash claude/test-bin-pinning.sh
              bash claude/plugins/code-quality/test-payload-parsing.sh
              bash claude/plugins/code-quality/test-project-config.sh
              bash claude/plugins/notifications/test-notifications.sh
              python3 claude/plugins/session-hygiene/test-session-staleness.py

              bash codex/test-hook-stdout-contract.sh
              bash codex/test-and-then-stop-hook.sh
              bash codex/test-tool-payload-hooks.sh
              python3 codex/validate-plugins.py

              touch $out
            '';
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
