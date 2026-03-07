import SwiftUI

/// Visual management overlay for MCP (Model Context Protocol) servers
/// Uses `claude mcp list/add/remove` CLI commands
struct MCPServerOverlay: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var theme: ThemeEngine
    @StateObject private var mcpManager = MCPServerManager.shared

    @State private var selectedServer: MCPServer?
    @State private var showAddForm = false
    @State private var showDeleteConfirm = false

    // Add form fields
    @State private var newName = ""
    @State private var newTransport: MCPTransport = .stdio
    @State private var newEndpoint = ""
    @State private var envVars: [(key: String, value: String)] = [("", "")]
    @State private var headers: [(key: String, value: String)] = [("", "")]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "server.rack")
                    .font(.system(size: 14))
                    .foregroundColor(theme.sky)
                Text("MCP Servers")
                    .font(Typography.heading2)
                    .foregroundColor(theme.bright)

                Text("\(mcpManager.servers.count)")
                    .font(Typography.caption)
                    .foregroundColor(theme.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.surface)
                    .clipShape(Capsule())

                Spacer()

                if mcpManager.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }

                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showAddForm.toggle()
                        selectedServer = nil
                        resetAddForm()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                        Text("Add Server")
                            .font(Typography.caption)
                    }
                    .foregroundColor(theme.sky)
                }
                .buttonStyle(.plain)

                Button {
                    mcpManager.load()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(theme.muted)
                }
                .buttonStyle(.plain)
                .help("Refresh server list")

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(theme.muted)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider().opacity(0.3)

            // Body: left server list + right detail/add
            HStack(spacing: 0) {
                // Left column: server list
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(mcpManager.servers) { server in
                            Button {
                                selectedServer = server
                                showAddForm = false
                            } label: {
                                HStack {
                                    // Status indicator
                                    Circle()
                                        .fill(statusColor(server.status))
                                        .frame(width: 8, height: 8)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(server.name)
                                            .font(Typography.bodyBold)
                                            .foregroundColor(selectedServer?.id == server.id ? theme.sky : theme.primary)

                                        Text(server.transport.rawValue.uppercased())
                                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                                            .foregroundColor(theme.muted)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedServer?.id == server.id ? theme.sky.opacity(0.1) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }

                        if mcpManager.servers.isEmpty && !mcpManager.isLoading {
                            VStack(spacing: 8) {
                                Spacer()
                                Image(systemName: "server.rack")
                                    .font(.system(size: 24))
                                    .foregroundColor(theme.muted)
                                Text("No MCP servers")
                                    .font(Typography.body)
                                    .foregroundColor(theme.muted)
                                Text("Add servers to extend\nClaude's capabilities")
                                    .font(Typography.caption)
                                    .foregroundColor(theme.muted)
                                    .multilineTextAlignment(.center)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                    .padding(8)
                }
                .frame(width: 220)

                Divider().opacity(0.3)

                // Right column: detail or add form
                if showAddForm {
                    addFormView
                } else if let server = selectedServer {
                    serverDetailView(server)
                } else {
                    VStack {
                        Spacer()
                        Text("Select a server or add a new one")
                            .font(Typography.body)
                            .foregroundColor(theme.muted)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: 450)
        }
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.sky.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        .frame(width: 720)
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    // MARK: - Server Detail

    private func serverDetailView(_ server: MCPServer) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Circle()
                    .fill(statusColor(server.status))
                    .frame(width: 10, height: 10)

                Text(server.name)
                    .font(Typography.heading2)
                    .foregroundColor(theme.bright)

                Spacer()

                Button {
                    showDeleteConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("Remove")
                            .font(Typography.caption)
                    }
                    .foregroundColor(theme.rose)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    detailRow("Transport", value: server.transport.rawValue.uppercased())
                    detailRow("Endpoint", value: server.endpoint)
                    detailRow("Status", value: server.status.displayName)
                }
                .padding(16)
            }
        }
        .alert("Remove Server?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                mcpManager.remove(name: server.name)
                selectedServer = nil
            }
        } message: {
            Text("This will remove the MCP server '\(server.name)' from your configuration.")
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Typography.caption)
                .foregroundColor(theme.muted)
            Text(value)
                .font(Typography.codeBlock)
                .foregroundColor(theme.primary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Add Form

    private var addFormView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add MCP Server")
                    .font(Typography.heading2)
                    .foregroundColor(theme.bright)

                // Name
                TextField("Server name", text: $newName)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundColor(theme.primary)
                    .padding(8)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                // Transport picker
                HStack(spacing: 8) {
                    Text("Transport:")
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)

                    Picker("", selection: $newTransport) {
                        Text("stdio").tag(MCPTransport.stdio)
                        Text("HTTP").tag(MCPTransport.http)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                // Endpoint
                TextField(
                    newTransport == .stdio ? "Command (e.g., npx @modelcontextprotocol/server-github)" : "URL (e.g., http://localhost:3000/mcp)",
                    text: $newEndpoint
                )
                .textFieldStyle(.plain)
                .font(Typography.codeBlock)
                .foregroundColor(theme.primary)
                .padding(8)
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Environment Variables
                VStack(alignment: .leading, spacing: 4) {
                    Text("Environment Variables")
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)

                    ForEach(envVars.indices, id: \.self) { i in
                        HStack(spacing: 4) {
                            TextField("Key", text: Binding(
                                get: { envVars[i].key },
                                set: { envVars[i].key = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .font(Typography.caption)
                            .foregroundColor(theme.primary)
                            .padding(6)
                            .background(theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                            Text("=")
                                .foregroundColor(theme.muted)

                            TextField("Value", text: Binding(
                                get: { envVars[i].value },
                                set: { envVars[i].value = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .font(Typography.caption)
                            .foregroundColor(theme.primary)
                            .padding(6)
                            .background(theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }

                    Button {
                        envVars.append(("", ""))
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.system(size: 9))
                            Text("Add Variable")
                                .font(Typography.caption)
                        }
                        .foregroundColor(theme.sky)
                    }
                    .buttonStyle(.plain)
                }

                // Headers (HTTP only)
                if newTransport == .http {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Headers")
                            .font(Typography.caption)
                            .foregroundColor(theme.muted)

                        ForEach(headers.indices, id: \.self) { i in
                            HStack(spacing: 4) {
                                TextField("Header", text: Binding(
                                    get: { headers[i].key },
                                    set: { headers[i].key = $0 }
                                ))
                                .textFieldStyle(.plain)
                                .font(Typography.caption)
                                .foregroundColor(theme.primary)
                                .padding(6)
                                .background(theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                                Text(":")
                                    .foregroundColor(theme.muted)

                                TextField("Value", text: Binding(
                                    get: { headers[i].value },
                                    set: { headers[i].value = $0 }
                                ))
                                .textFieldStyle(.plain)
                                .font(Typography.caption)
                                .foregroundColor(theme.primary)
                                .padding(6)
                                .background(theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }

                        Button {
                            headers.append(("", ""))
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9))
                                Text("Add Header")
                                    .font(Typography.caption)
                            }
                            .foregroundColor(theme.sky)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Action buttons
                HStack {
                    Spacer()
                    Button("Cancel") {
                        showAddForm = false
                        resetAddForm()
                    }
                    .font(Typography.body)
                    .foregroundColor(theme.muted)
                    .buttonStyle(.plain)

                    Button("Add Server") {
                        mcpManager.add(
                            name: newName,
                            transport: newTransport,
                            endpoint: newEndpoint,
                            envVars: envVars.filter { !$0.key.isEmpty },
                            headers: headers.filter { !$0.key.isEmpty }
                        )
                        showAddForm = false
                        resetAddForm()
                    }
                    .disabled(newName.isEmpty || newEndpoint.isEmpty)
                    .font(Typography.bodyBold)
                    .foregroundColor(newName.isEmpty || newEndpoint.isEmpty ? theme.muted : theme.sky)
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Helpers

    private func statusColor(_ status: MCPServerStatus) -> Color {
        switch status {
        case .healthy: return theme.sage
        case .needsAuth: return theme.amber
        case .error: return theme.rose
        }
    }

    private func resetAddForm() {
        newName = ""
        newTransport = .stdio
        newEndpoint = ""
        envVars = [("", "")]
        headers = [("", "")]
    }
}
