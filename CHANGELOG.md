# Changelog

## 2.1.1

- `roost new` writes apps that depend on swift-roost 2.1.3 or later with its
  `RichTerminal` trait, so `roost spectro` shows Spectro's colors, spinners,
  and styled tables again. Remove `"RichTerminal"` from `roostTraits` in the
  generated `Package.swift` to skip downloading Noora.
- `roost new --tailwind` generates a working Tailwind v4 setup: `@import
  "tailwindcss";` in `Public/css/input.css` and no `tailwind.config.js`.
  Earlier projects compiled an almost empty stylesheet because the generated
  v3 setup is ignored by v4. The Tailwind binary is pinned to v4.3.3, and
  `roost server` and `roost build` warn when `input.css` still uses the v3
  `@tailwind` directives.

## 2.1.0

The first release of the `roost` CLI as its own package. It previously shipped
inside swift-roost, which made `mint install` resolve the framework's whole
dependency graph.

- Install with `mint install roost-framework/roost-cli@2.1.0`.
- Generated apps depend on swift-roost 2.1.0 and ESW 1.6.0.
- `roost gen resource` generates controllers instead of closure routes:
  `TodoController` for HTML and `TodoAPIController` for JSON, registered with
  `resources(...)`. Scoped HTML controllers run `requireAuth()` as a controller
  plug. Actions decode input with `conn.permit`, so only the input type's
  fields can be set.
- `roost gen auth` generates `RegistrationController` and `SessionController`,
  with their routes in `Routes/AuthRoutes.swift`.
- `roost new` generates a `PageController` for `/` and logs requests with
  `roost_requestLogger()`.
- `roost spectro <arguments>` runs the `spectro` executable from the app's own
  dependencies.
