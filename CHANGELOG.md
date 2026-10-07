# Changelog

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
