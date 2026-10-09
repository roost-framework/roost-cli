# roost

The command-line tool for the [Roost](https://github.com/roost-framework/swift-roost)
web framework. It creates apps, generates code, runs the development server, and
fronts the tools of Roost's companion libraries.

## Install

You need Swift 6.3 or later on macOS 14+ or Linux.

```sh
brew install mint
mint install roost-framework/roost-cli@2.1.0
roost --version
```

Mint links `roost` into `~/.mint/bin`; add that directory to your `PATH`.

Without Mint, for example on Linux, build from a checkout and copy
`.build/release/roost` to a directory on your `PATH`:

```sh
git clone --branch 2.1.0 --depth 1 https://github.com/roost-framework/roost-cli.git
cd roost-cli
swift build -c release --product roost
```

## Use

```sh
roost new TodoApp
cd TodoApp
roost gen auth
roost gen resource Todo title:string done:bool --both --scope user_id
roost spectro database create todo_app_dev
roost migrate
roost server --port 8080
```

`roost server`, `roost migrate`, and `roost spectro` run the app's Postgres 18
in its own container, `roost-<app>-db`, with Apple's `container` when it is
installed and Docker otherwise. It listens on 127.0.0.1 at a port derived from
the app name, printed at startup. macOS blocks the ports Apple's `container`
publishes until you allow `container-runtime-linux` in System Settings >
Privacy & Security > Local Network. Run tests against it with
`DB_HOST=127.0.0.1 DB_PORT=<port> swift test`. Delete the container to start
over: `container rm -f roost-todoapp-db` or `docker rm -fv roost-todoapp-db`.
Set `DB_HOST` to use a Postgres you run yourself, or
`ROOST_CONTAINER_RUNTIME=docker` to pick the runtime. Apps created with
`--no-db` get no container. Without `--port` or `ROOST_PORT`, `roost server`
moves to the next free port when 8080 is taken.

`roost gen resource` writes a model, a context, a migration, ESW views, and
controllers: `TodoController` for HTML and `TodoAPIController` for JSON. It
registers them in `App.swift` as `resources("/todos", TodoController.self)`.
Actions decode input with `conn.permit`, so only the input type's fields can be
set. `roost gen auth` writes `RegistrationController` and `SessionController`,
routed from `Routes/AuthRoutes.swift`.

Generated apps depend on swift-roost 2.1.0 or later. Spectro, Nexus, and ESW
arrive through SwiftPM as the app's own dependencies; there is nothing else to
install. `roost spectro <arguments>` runs the `spectro` executable from those
dependencies, so its version always matches the app's `Package.resolved`. ESW
compiles templates through its build plugin during `swift build`.

Run `roost <command> --help` for options. The
[framework documentation](https://github.com/roost-framework/swift-roost#readme)
covers the generated code and the full workflow.

## Develop

```sh
swift test
python3 scripts/check_generated_app.py --framework ../swift-roost
```

The acceptance script generates an app, builds it, migrates an owned PostgreSQL
database, runs its tests, and drives it over HTTP. Omit `--framework` to check
the published framework; see the script's header for every option.
