# go-module

A [garnix](https://garnix.io) module for projects using Go.

It builds your Go packages with `buildGoModule`, runs `go test` and `go vet`,
checks formatting with `gofmt`, and can optionally deploy a web server.

## Usage

In your project's `flake.nix`, consume the module through
[`garnix-lib`](https://github.com/joegoldin/garnix-lib)'s `mkModules`:

```nix
{
  inputs.garnix-lib.url = "github:joegoldin/garnix-lib";
  inputs.go-module.url = "github:joegoldin/go-module";

  outputs = { garnix-lib, go-module, ... }:
    garnix-lib.lib.mkModules {
      modules = [ go-module.garnixModules.default ];
      config = {
        go.myapp = {
          src = ./.;
          # goVersion = "1.23";
          # vendorHash = "sha256-...";   # set once you have dependencies
          # subPackages = [ "./cmd/server" ];
        };
      };
    };
}
```

This produces:

- `packages.<system>.myapp` — the built Go binary/binaries.
- `checks.<system>.myapp-test` — `go test ./...` (plus `go vet ./...` when
  `vet = true`).
- `checks.<system>.myapp-gofmt` — fails if any file is not `gofmt`-formatted.
- `devShells.<system>.myapp` — the Go toolchain plus your dev tools.

### Options

| Option | Default | Description |
| --- | --- | --- |
| `src` | (required) | Directory containing `go.mod`/`go.sum`. |
| `goVersion` | `"1.23"` | Toolchain version (nixpkgs `go_<major>_<minor>`). |
| `vendorHash` | `null` | Hash of vendored deps; `null` for no external deps. |
| `subPackages` | `null` | Import paths to build; `null` builds everything. |
| `ldflags` | `[ ]` | Extra `-ldflags`. |
| `tags` | `[ ]` | Go build tags. |
| `vet` | `true` | Run `go vet` in the test check. |
| `webServer` | `null` | Deploy a systemd + nginx web server (garnix hosting). |
| `devTools` / `buildDependencies` / `runtimeDependencies` | `[ ]` | Extra packages. |

An evaluable `example/` project is included; see
`.#lib.exampleFlakeOutputs` in this flake.
