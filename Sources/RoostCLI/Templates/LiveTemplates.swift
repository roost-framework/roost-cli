import Foundation

/// `roost gen live`: a resource whose index is a live page, like `mix phx.gen.live`.
/// The HTML controller still serves show, new, and edit, and the live forms post
/// to it when JavaScript is unavailable.
enum LiveTemplates {
    /// The `LivePage` for the index: the list, a create form validated as you type, and delete.
    static func livePage(name: String, pluralName: String, scopeKey: String?) -> String {
        let plural = toLowerFirst(pluralName)
        let context = "\(pluralName)Context(repo: conn.repo())"
        let scoped = scopeKey != nil
        let scopeArgument = scoped ? ", scopeId: state.scopeId" : ""
        let listArgument = scoped ? "scopeId: state.scopeId" : ""
        let route = scoped ? """
            static let route = LiveRoute(\(pluralName)Live(), path: "/_live/\(plural)") { conn in
                    _ = try \(pluralName)Live.currentUserID(conn)
                }
            """ : """
            static let route = LiveRoute(\(pluralName)Live(), path: "/_live/\(plural)")
            """
        let mount = scoped ? """
            let scopeId = try Self.currentUserID(conn)
                    return try await State(scopeId: scopeId, \(plural): \(context).list\(pluralName)(scopeId: scopeId))
            """ : """
            try await State(\(plural): \(context).list\(pluralName)())
            """
        let ownerCheck = scoped ? """

                    // The page belongs to the user who opened it.
                    guard try Self.currentUserID(conn) == state.scopeId else { throw LiveError.unauthorized }
            """ : ""
        let helper = scoped ? """


                private static func currentUserID(_ conn: Connection) throws -> UUID {
                    guard let id = conn.authenticatedUserID.flatMap(UUID.init(uuidString:)) else { throw LiveError.unauthorized }
                    return id
                }
            """ : ""
        return """
        import Roost

        /// The live \(plural) index. `\(name)Controller.index` renders it; `route` is registered in App.swift.
        struct \(pluralName)Live: LivePage {
            \(route)

            struct State: Sendable {\(scoped ? "\n        let scopeId: UUID" : "")
                var \(plural): [\(name)]
                var form = FormValues([:])
            }

            func mount(_ conn: Connection, context: LiveContext) async throws -> State {
                \(mount)
            }

            func handleEvent(_ event: LiveEvent, state: State, conn: Connection) async throws -> State {\(ownerCheck)
                let context = try \(context)
                var next = state
                switch event.name {
                case "validate", "save":
                    let values = event.values.compactMapValues(\\.first)
                    do {
                        let input = try FormValues(values).decode(as: Create\(name)Input.self)
                        if event.name == "save" {
                            _ = try await context.create\(name)(input\(scopeArgument))
                            next.\(plural) = try await context.list\(pluralName)(\(listArgument))
                            next.form = FormValues([:])
                        } else {
                            _ = try await input.validated()
                            next.form = FormValues(values)
                        }
                    } catch let errors as ValidationErrors {
                        next.form = FormValues(values, errors: errors)
                    }
                case "delete":
                    guard let id = event.value("id").flatMap(UUID.init(uuidString:)) else { throw LiveError.invalidEvent }
                    try await context.delete\(name)(id: id\(scopeArgument))
                    next.\(plural) = try await context.list\(pluralName)(\(listArgument))
                default:
                    throw LiveError.invalidEvent
                }
                return next
            }

            func render(_ state: State) -> ESWLiveRender {
                \(pluralName)LiveView(\(plural): state.\(plural), form: state.form).render()
            }\(helper)
        }
        """
    }

    static func liveView(name: String, pluralName: String) -> String {
        """
        import Roost

        @ESWTemplate("index.live.hesw")
        struct \(pluralName)LiveView {
            let \(toLowerFirst(pluralName)): [\(name)]
            let form: FormValues
        }
        """
    }

    static func liveTemplate(name: String, pluralName: String, fields: [ParsedField]) -> String {
        let singular = toLowerFirst(name)
        let plural = toLowerFirst(pluralName)
        let inputs = fields.map { "    " + input(for: $0) }.joined(separator: "\n")
        let headers = fields.prefix(3).map { "<th>\($0.swiftName)</th>" }.joined(separator: "\n            ")
        let cells = fields.prefix(3).map { "<td>{\(singular).\($0.swiftName)}</td>" }.joined(separator: "\n            ")
        return """
        <h1>\(pluralName)</h1>

        <.form action="/\(plural)" method="post" id="new-\(singular)" attributes={["esw-submit": "save", "esw-change": "validate"]}>
        \(inputs)
            <button type="submit">Create \(name)</button>
        </.form>

        <p :if={\(plural).isEmpty}>No \(plural) yet.</p>

        <table :if={!\(plural).isEmpty}>
            <thead>
                <tr>
                    \(headers)
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                <tr :for={\(singular) in \(plural)} :key={\(singular).id} id={"\(singular)-\\(\(singular).id)"}>
                    \(cells)
                    <td>
                        <a href={"/\(plural)/\\(\(singular).id)"}>View</a>
                        <a href={"/\(plural)/\\(\(singular).id)/edit"}>Edit</a>
                        <.form action={"/\(plural)/\\(\(singular).id)"} method="delete" id={"delete-\(singular)-\\(\(singular).id)"} attributes={["esw-submit": "delete"]}>
                            <input type="hidden" name="id" value={\(singular).id}>
                            <button type="submit">Delete</button>
                        </.form>
                    </td>
                </tr>
            </tbody>
        </table>
        """
    }

    /// A Roost form component for one field, named like the input struct's property.
    private static func input(for field: ParsedField) -> String {
        let attributes = "field={form[\"\(field.swiftName)\"]} label=\"\(field.displayName)\""
        if field.isTextarea || field.isArray { return "<.textarea \(attributes) />" }
        switch field.type {
        case .bool: return "<.input \(attributes) type=\"checkbox\" />"
        case .int: return "<.input \(attributes) type=\"number\" />"
        case .double: return "<.input \(attributes) type=\"number\" attributes={[\"step\": \"any\"]} />"
        default: return "<.input \(attributes) />"
        }
    }
}
