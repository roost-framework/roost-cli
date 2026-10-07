import Foundation

enum GeneratorTemplates {

    // MARK: - Model

    static func model(name: String, tableName: String, fields: [ParsedField], scopeKey: String? = nil) -> String {
        var lines = [
            "import Roost",
            "",
            "@Schema(\"\(tableName)\")",
            "struct \(name) {",
            "    @ID var id: UUID",
        ]

        if let scopeKey = scopeKey {
            lines.append("    @ForeignKey var \(toCamelCase(scopeKey)): UUID")
        }

        for field in fields {
            lines.append("    \(field.wrapper) var \(field.swiftName): \(field.swiftType)")
        }

        lines.append("    @Timestamp var createdAt: Date")
        lines.append("    @Timestamp var updatedAt: Date")
        lines.append("}")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    // MARK: - Migration

    static func migration(tableName: String, fields: [ParsedField], scopeKey: String? = nil) -> String {
        var columns = [
            "    \"id\" UUID PRIMARY KEY DEFAULT gen_random_uuid()",
        ]

        if let scopeKey = scopeKey {
            let snakeKey = toSnakeCase(scopeKey)
            let refTable = pluralize(String(snakeKey.dropLast(3)))  // strip _id
            columns.append("    \"\(snakeKey)\" UUID NOT NULL REFERENCES \"\(refTable)\"(\"id\")")
        }

        for field in fields {
            columns.append("    \(field.sqlDefinition)")
        }

        columns.append("    \"created_at\" TIMESTAMPTZ NOT NULL DEFAULT NOW()")
        columns.append("    \"updated_at\" TIMESTAMPTZ NOT NULL DEFAULT NOW()")

        let columnsSQL = columns.joined(separator: ",\n")
        let indexedKeys = (scopeKey.map { [toSnakeCase($0)] } ?? []) + fields.filter(\.isReference).map(\.columnName)
        let indexes = indexedKeys.map { "CREATE INDEX \"\(tableName)_\($0)_index\" ON \"\(tableName)\" (\"\($0)\");" }.joined(separator: "\n")

        return """
        -- migrate:up
        CREATE TABLE "\(tableName)" (
        \(columnsSQL)
        );
        \(indexes)

        -- migrate:down
        DROP TABLE "\(tableName)";
        """
    }

    // MARK: - Empty Migration

    static func emptyMigration(description: String) -> String {
        let date = DateFormatter.migrationDate.string(from: Date())
        return """
        -- Migration: \(description)
        -- Created: \(date)

        -- migrate:up
        -- TODO: Add your migration SQL here

        -- migrate:down
        -- TODO: Add your rollback SQL here
        """
    }

    // MARK: - Context (Phoenix-Style)

    static func contextTemplate(name: String, pluralName: String, fields: [ParsedField], scopeKey: String? = nil) -> String {
        let editable = fields.filter { $0.isFormField }
        let scopeParam = scopeKey == nil ? "" : ", scopeId: UUID"
        let scopeArg = scopeKey == nil ? "" : ", scopeId: scopeId"
        let scopeFilter = scopeKey.map { "\n            .where({ $0.\(toCamelCase($0)) == scopeId })" } ?? ""
        let scopeAssign = scopeKey.map { "\n        record.\(toCamelCase($0)) = scopeId" } ?? ""
        let updateFields = editable.map { "            \"\($0.swiftName)\": input.\($0.swiftName) as any Sendable," }.joined(separator: "\n")
        let rules = editable.filter { !$0.isOptional && !$0.isArray && ($0.type == .string || $0.type == .text) }
            .map { "            .required(\"\($0.swiftName)\") { $0.\($0.swiftName) }," }.joined(separator: "\n")
        return """
        import Roost

        /// Domain operations depend on a repository, including a transaction repository in tests.
        struct \(pluralName)Context: Sendable {
            let repo: any Repo

            func list\(pluralName)(\(scopeKey == nil ? "" : "scopeId: UUID")) async throws -> [\(name)] {
                try await repo.query(\(name).self)\(scopeFilter)
                    .orderBy(\\.createdAt, .asc).all()
            }

            func get\(name)(id: UUID\(scopeParam)) async throws -> \(name) {
                guard let record = try await repo.query(\(name).self)
                    .where({ $0.id == id })\(scopeFilter)
                    .first() else {
                    throw NexusHTTPError(.notFound, message: "\(name) not found")
                }
                return record
            }

            func create\(name)(_ input: Create\(name)Input\(scopeParam)) async throws -> \(name) {
                let input = try await input.validated()
                var record = \(name)()\(scopeAssign)
        \(buildAssignLines(fields: editable, modelVar: "record", sourceVar: "input"))
                return try await repo.insert(record)
            }

            func update\(name)(id: UUID, with input: Create\(name)Input\(scopeParam)) async throws -> \(name) {
                _ = try await get\(name)(id: id\(scopeArg))
                let input = try await input.validated()
                return try await repo.update(\(name).self, id: id, changes: [
        \(updateFields)
                    "updatedAt": Date(),
                ])
            }

            func delete\(name)(id: UUID\(scopeParam)) async throws {
                _ = try await get\(name)(id: id\(scopeArg))
                try await repo.delete(\(name).self, id: id)
            }
        }

        struct Create\(name)Input: Codable, Sendable {
        \(buildInputProps(fields: editable))

            func validated() async throws -> Self {
                var changeset = Changeset(data: self)
                await changeset.validate(using: [
        \(rules)
                ])
                return try changeset.requireValid()
            }
        }
        """
    }

    // MARK: - Controllers

    static func jsonController(name: String, pluralName: String, fields: [ParsedField], scopeKey: String? = nil) -> String {
        let scope = ControllerScope(scopeKey, requireAuth: false)
        let context = "\(pluralName)Context(repo: conn.repo())"
        return """
        import Roost

        struct \(name)APIController: Controller {
            enum Action: String, ControllerAction {
                case index, show, create, update, delete
            }

            static func action(_ action: Action) -> Plug {
                switch action {
        \(actionCases(["index", "show", "create", "update", "delete"]))
                }
            }

            static func index(_ conn: Connection) async throws -> Connection {\(scope.load)
                return try conn.json(value: await \(context).list\(pluralName)(\(scope.listArgument)))
            }

            static func show(_ conn: Connection) async throws -> Connection {\(scope.load)
                let id: UUID = try conn.requireParam("id")
                return try conn.json(value: await \(context).get\(name)(id: id\(scope.argument)))
            }

            static func create(_ conn: Connection) async throws -> Connection {\(scope.load)
                do {
                    let input = try conn.permit(Create\(name)Input.self)
                    return try conn.json(status: .created, value: await \(context).create\(name)(input\(scope.argument)))
                } catch let errors as ValidationErrors {
                    return try conn.json(status: .unprocessableContent, value: errors)
                }
            }

            static func update(_ conn: Connection) async throws -> Connection {\(scope.load)
                let id: UUID = try conn.requireParam("id")
                do {
                    let input = try conn.permit(Create\(name)Input.self)
                    return try conn.json(value: await \(context).update\(name)(id: id, with: input\(scope.argument)))
                } catch let errors as ValidationErrors {
                    return try conn.json(status: .unprocessableContent, value: errors)
                }
            }

            static func delete(_ conn: Connection) async throws -> Connection {\(scope.load)
                let id: UUID = try conn.requireParam("id")
                try await \(context).delete\(name)(id: id\(scope.argument))
                return try conn.json(value: ["deleted": true])
            }\(scope.helper)
        }
        """
    }

    static func htmlController(name: String, pluralName: String, fields: [ParsedField], scopeKey: String? = nil) -> String {
        let singular = toLowerFirst(name)
        let plural = toLowerFirst(pluralName)
        let scope = ControllerScope(scopeKey, requireAuth: true)
        let context = "\(pluralName)Context(repo: conn.repo())"
        return """
        import Roost

        struct \(name)Controller: Controller {
            enum Action: String, ControllerAction {
                case index, new, create, show, edit, update, delete
            }\(scope.plugs)

            static func action(_ action: Action) -> Plug {
                switch action {
        \(actionCases(["index", "new", "create", "show", "edit", "update", "delete"]))
                }
            }

            static func index(_ conn: Connection) async throws -> Connection {\(scope.load)
                let \(plural) = try await \(context).list\(pluralName)(\(scope.listArgument))
                return try conn.render(\(pluralName)IndexView(\(plural): \(plural)), title: "\(pluralName)")
            }

            static func new(_ conn: Connection) async throws -> Connection {
                try conn.render(\(name)NewView(), title: "New \(name)")
            }

            static func create(_ conn: Connection) async throws -> Connection {\(scope.load)
                do {
                    let input = try conn.permit(Create\(name)Input.self)
                    let created = try await \(context).create\(name)(input\(scope.argument))
                    return conn.putFlash(.info, "\(name) created").redirect(to: "/\(plural)/\\(created.id)")
                } catch let errors as ValidationErrors {
                    return try conn.render(\(name)NewView(values: conn.bodyParams, errors: errors), title: "New \(name)", status: .unprocessableContent)
                }
            }

            static func show(_ conn: Connection) async throws -> Connection {\(scope.load)
                let id: UUID = try conn.requireParam("id")
                let \(singular) = try await \(context).get\(name)(id: id\(scope.argument))
                return try conn.render(\(name)ShowView(\(singular): \(singular)), title: "\(name)")
            }

            static func edit(_ conn: Connection) async throws -> Connection {\(scope.load)
                let id: UUID = try conn.requireParam("id")
                let \(singular) = try await \(context).get\(name)(id: id\(scope.argument))
                return try conn.render(\(name)EditView(\(singular): \(singular)), title: "Edit \(name)")
            }

            static func update(_ conn: Connection) async throws -> Connection {\(scope.load)
                let context = \(context)
                let id: UUID = try conn.requireParam("id")
                let \(singular) = try await context.get\(name)(id: id\(scope.argument))
                do {
                    let input = try conn.permit(Create\(name)Input.self)
                    _ = try await context.update\(name)(id: id, with: input\(scope.argument))
                    return conn.putFlash(.info, "\(name) updated").redirect(to: "/\(plural)/\\(id)")
                } catch let errors as ValidationErrors {
                    return try conn.render(\(name)EditView(\(singular): \(singular), values: conn.bodyParams, errors: errors), title: "Edit \(name)", status: .unprocessableContent)
                }
            }

            static func delete(_ conn: Connection) async throws -> Connection {\(scope.load)
                let id: UUID = try conn.requireParam("id")
                try await \(context).delete\(name)(id: id\(scope.argument))
                return conn.putFlash(.info, "\(name) deleted").redirect(to: "/\(plural)")
            }\(scope.helper)
        }
        """
    }

    /// The `App.swift` route lines for a generated resource.
    static func htmlRegistration(name: String, pluralName: String) -> String {
        "resources(\"/\(toLowerFirst(pluralName))\", \(name)Controller.self)"
    }

    static func jsonRegistration(name: String, pluralName: String) -> String {
        "scope(\"/api\") { resources(\"/\(toLowerFirst(pluralName))\", \(name)APIController.self) }"
    }

    /// The exhaustive `switch` cases mapping each action to its function.
    private static func actionCases(_ actions: [String]) -> String {
        actions.map { "        case .\($0): \($0)" }.joined(separator: "\n")
    }

    /// What a controller adds when records belong to the signed-in user.
    private struct ControllerScope {
        var plugs = ""
        var load = ""
        var argument = ""
        var listArgument = ""
        var helper = ""

        init(_ key: String?, requireAuth: Bool) {
            guard key != nil else { return }
            if requireAuth {
                plugs = "\n\n    // Every action needs a signed-in user, whose ID scopes the context's queries.\n"
                    + "    static let plugs: [ActionPlug<Action>] = [.plug(requireAuth())]"
            }
            load = "\n        let scopeId = try currentUserID(conn)"
            argument = ", scopeId: scopeId"
            listArgument = "scopeId: scopeId"
            helper = "\n\n" + [
                "    private static func currentUserID(_ conn: Connection) throws -> UUID {",
                "        guard let id = conn.authenticatedUserID.flatMap(UUID.init(uuidString:)) else {",
                "            throw NexusHTTPError(.unauthorized, message: \"Authentication required\")",
                "        }",
                "        return id",
                "    }",
            ].joined(separator: "\n")
        }
    }

    private static func formValueExpression(field: ParsedField, model: String) -> String {
        let value = "\(model).\(field.swiftName)"
        if field.isArray {
            return "String(data: try JSONEncoder().encode(\(value)), encoding: .utf8) ?? \"\""
        }
        if field.type == .date {
            return field.isOptional ? "\(value).map { ISO8601DateFormatter().string(from: $0) } ?? \"\"" : "ISO8601DateFormatter().string(from: \(value))"
        }
        if field.type == .data {
            return field.isOptional ? "\(value)?.base64EncodedString() ?? \"\"" : "\(value).base64EncodedString()"
        }
        return field.isOptional ? "\(value).map { String(describing: $0) } ?? \"\"" : "String(describing: \(value))"
    }

    /// Editable Swift state and presentation helpers, created once by the CLI.
    static func htmlViews(name: String, fields: [ParsedField]) -> [(String, String)] {
        let singular = toLowerFirst(name)
        let plural = pluralize(singular)
        let values = fields.filter { $0.isFormField }.map { field in
            "\"\(field.swiftName)\": \(formValueExpression(field: field, model: singular))"
        }.joined(separator: ", ")
        func view(_ type: String, _ template: String, _ body: String) -> (String, String) {
            (type + ".swift", """
            import Roost

            @ESWTemplate("\(template).esw")
            struct \(type) {
            \(body)
            }
            """)
        }
        return [
            view("\(pluralize(name))IndexView", "index", "    let \(plural): [\(name)]"),
            view("\(name)ShowView", "show", "    let \(singular): \(name)"),
            view("\(name)NewView", "new", """
                var values: [String: String] = [:]
                var errors = ValidationErrors()
            """),
            view("\(name)EditView", "edit", """
                let \(singular): \(name)
                var values: [String: String]
                var errors: ValidationErrors

                init(\(singular): \(name), values: [String: String]? = nil, errors: ValidationErrors = ValidationErrors()) throws {
                    self.\(singular) = \(singular)
                    self.errors = errors
                    if let values {
                        self.values = values
                    } else {
                        self.values = [\(values.isEmpty ? ":" : values)]
                    }
                }
            """),
        ]
    }

    // MARK: - ESW Views: Index (List)

    static func listTemplate(name: String, fields: [ParsedField]) -> String {
        let lowerName = toLowerFirst(name)
        let lowerPlural = pluralize(String(lowerName))

        let headerCells = fields.prefix(3).map { "<th>\($0.swiftName)</th>" }.joined(separator: "\n            ")
        let bodyCells = fields.prefix(3).map { "<td><%= \(lowerName).\($0.swiftName) %></td>" }.joined(separator: "\n            ")

        return """
        <h1>\(name) List</h1>

        <p><a href="/\(lowerPlural)/new">New \(name)</a></p>

        <table>
            <thead>
                <tr>
                \(headerCells)
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
            <% for \(lowerName) in \(lowerPlural) { %>
                <tr>
                \(bodyCells)
                    <td>
                        <a href="/\(lowerPlural)/<%= \(lowerName).id %>">View</a>
                        <a href="/\(lowerPlural)/<%= \(lowerName).id %>/edit">Edit</a>
                    </td>
                </tr>
            <% } %>
            </tbody>
        </table>
        """
    }

    // MARK: - ESW Views: Show (Detail)

    static func showTemplate(name: String, fields: [ParsedField]) -> String {
        let lowerName = toLowerFirst(name)
        let lowerPlural = pluralize(String(lowerName))

        let fieldLines = fields.filter { $0.isFormField }.map { field in
            "<p><strong>\(field.swiftName):</strong> <%= \(lowerName).\(field.swiftName) %></p>"
        }.joined(separator: "\n")

        return """
        <h1><%= \(lowerName).\(fields.first?.swiftName ?? "id") %></h1>

        <p><small>Created: <%= \(lowerName).createdAt %></small></p>

        \(fieldLines)

        <p>
            <a href="/\(lowerPlural)">Back</a>
            <a href="/\(lowerPlural)/<%= \(lowerName).id %>/edit">Edit</a>
        </p>

        <.form action={"/\(lowerPlural)/\\(\(lowerName).id)"} method="delete">
            <button type="submit">Delete</button>
        </.form>
        """
    }

    // MARK: - ESW Views: New

    static func newTemplate(name: String, fields: [ParsedField]) -> String {
        let lowerPlural = pluralize(toLowerFirst(name))
        let formFields = fields.filter { $0.isFormField }

        let fieldInputs = formFields.map { field in
            buildFormInput(for: field, modelVar: nil)
        }.joined(separator: "\n\n")

        return """
        <h1>New \(name)</h1>

        <.form action="/\(lowerPlural)" method="post">

        \(fieldInputs)

            <button type="submit">Create \(name)</button>
        </.form>

        <p><a href="/\(lowerPlural)">Back</a></p>
        """
    }

    // MARK: - ESW Views: Edit

    static func editTemplate(name: String, fields: [ParsedField]) -> String {
        let lowerName = toLowerFirst(name)
        let lowerPlural = pluralize(lowerName)
        let formFields = fields.filter { $0.isFormField }

        let fieldInputs = formFields.map { field in
            buildFormInput(for: field, modelVar: lowerName)
        }.joined(separator: "\n\n")

        return """
        <h1>Edit \(name)</h1>

        <.form action={"/\(lowerPlural)/\\(\(lowerName).id)"} method="put">

        \(fieldInputs)

            <button type="submit">Update \(name)</button>
        </.form>

        <p><a href="/\(lowerPlural)/<%= \(lowerName).id %>">Cancel</a></p>
        """
    }

    // MARK: - Legacy Alias

    static func detailTemplate(name: String, fields: [ParsedField]) -> String {
        showTemplate(name: name, fields: fields)
    }

    // MARK: - Filename Helpers

    static func inputTests(appName: String, name: String, fields: [ParsedField]) -> String {
        let values = fields.filter { $0.isFormField }.map { field -> String in
            let value: String
            if field.isArray { value = "[]" }
            else {
                switch field.type {
                case .string, .text: value = "Example"
                case .json: value = "{}"
                case .int, .double: value = "1"
                case .bool: value = "true"
                case .uuid: value = "00000000-0000-0000-0000-000000000001"
                case .date: value = "2026-01-01T12:00:00Z"
                case .data: value = "SGVsbG8="
                }
            }
            return "\"\(field.swiftName)\": \"\(value)\""
        }.joined(separator: ", ")
        return """
        import Roost
        import Testing
        @testable import \(appName)

        @Test("\(name) accepts valid form input")
        func \(toLowerFirst(name))ValidForm() async throws {
            let input = try FormValues([\(values.isEmpty ? ":" : values)]).decode(as: Create\(name)Input.self)
            _ = try await input.validated()
        }
        """
    }

    static func migrationFilename(tableName: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        return "\(timestamp)_create_\(tableName).sql"
    }

    static func migrationFilename(description: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let sanitized = description
            .replacing(#/[^a-zA-Z0-9]/#) { _ in "_" }
            .lowercased()
            .replacing(#/__+/#) { _ in "_" }
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return "\(timestamp)_\(sanitized).sql"
    }

    // MARK: - Private Helpers

    /// Generates `modelVar.field = sourceVar.field` assignment lines for template code.
    private static func buildAssignLines(fields: [ParsedField], modelVar: String, sourceVar: String = "input") -> String {
        fields.map { field in
            "        \(modelVar).\(field.swiftName) = \(sourceVar).\(field.swiftName)"
        }.joined(separator: "\n")
    }

    /// Generates `let fieldName: Type` property declarations for input structs.
    private static func buildInputProps(fields: [ParsedField]) -> String {
        fields.map { field in
            "    let \(field.swiftName): \(field.swiftType)"
        }.joined(separator: "\n")
    }

    /// Generates an HTML form input. When `modelVar` is non-nil, pre-populates with existing values.
    private static func buildFormInput(for field: ParsedField, modelVar: String?) -> String {
        let key = field.swiftName
        let value = "<%= values[\"\(key)\"] ?? \"\" %>"
        let control: String
        if field.type == .bool && !field.isArray {
            control = "<input type=\"checkbox\" name=\"\(key)\" value=\"true\" <%= [\"true\", \"on\", \"1\"].contains(values[\"\(key)\"] ?? \"\") ? \"checked\" : \"\" %>>"
        } else if field.isTextarea || field.isArray {
            control = "<textarea name=\"\(key)\">\(value)</textarea>"
        } else {
            let type = [.date, .data].contains(field.type) ? "text" : field.htmlInputType
            let step = field.type == .double ? " step=\"any\"" : ""
            control = "<input type=\"\(type)\" name=\"\(key)\" value=\"\(value)\"\(step)>"
        }
        return """
            <label>
                \(field.displayName)
                \(control)
                <% for error in errors["\(key)"] { %>
                <small role="alert"><%= error %></small>
                <% } %>
            </label>
        """
    }

}

// MARK: - DateFormatter Extension

private extension DateFormatter {
    static let migrationDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}
