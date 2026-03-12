import SwiftUI

/// MCP Server management overlay — two tabs: Installed servers + Catalog of popular MCPs.
/// Installed: browse, inspect, remove configured servers.
/// Catalog: one-click install from a curated list of popular MCP servers.
struct MCPServerOverlay: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var theme: ThemeEngine
    @StateObject private var mcpManager = MCPServerManager.shared

    // Tab
    @State private var activeTab: MCPTab = .installed

    // Installed tab state
    @State private var selectedServer: MCPServer?
    @State private var showAddForm = false
    @State private var showDeleteConfirm = false
    @State private var newName = ""
    @State private var newTransport: MCPTransport = .stdio
    @State private var newEndpoint = ""
    @State private var envVars: [(key: String, value: String)] = [("", "")]
    @State private var headers: [(key: String, value: String)] = [("", "")]

    // Catalog tab state
    @State private var selectedCategory: MCPCatalogEntry.Category? = nil
    @State private var selectedCatalogEntry: MCPCatalogEntry?
    @State private var catalogParamValues: [String: String] = [:]
    @State private var isInstalling = false
    @State private var installSuccessId: String?

    enum MCPTab {
        case installed, catalog
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)

            switch activeTab {
            case .installed:
                installedBody
            case .catalog:
                catalogBody
            }
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

    // MARK: - Header

    private var header: some View {
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

            // Tab picker
            HStack(spacing: 2) {
                tabButton("Installed", tab: .installed)
                tabButton("Catalog", tab: .catalog)
            }
            .padding(3)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            Spacer()

            if mcpManager.isLoading {
                ProgressView().controlSize(.small).padding(.trailing, 4)
            }

            if activeTab == .installed {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showAddForm.toggle()
                        selectedServer = nil
                        resetAddForm()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 12))
                        Text("Add Server").font(Typography.caption)
                    }
                    .foregroundColor(theme.sky)
                }
                .buttonStyle(.plain)
            }

            Button { mcpManager.load() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(theme.muted)
            }
            .buttonStyle(.plain)
            .help("Refresh server list")

            Button { isPresented = false } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(theme.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    private func tabButton(_ label: String, tab: MCPTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { activeTab = tab }
        } label: {
            Text(label)
                .font(Typography.caption)
                .foregroundColor(activeTab == tab ? theme.bright : theme.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(activeTab == tab ? theme.sky.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Installed Tab

    private var installedBody: some View {
        HStack(spacing: 0) {
            // Left: server list
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(mcpManager.servers) { server in
                        Button {
                            selectedServer = server
                            showAddForm = false
                        } label: {
                            HStack {
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
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { activeTab = .catalog }
                            } label: {
                                Text("Browse catalog →")
                                    .font(Typography.caption)
                                    .foregroundColor(theme.sky)
                            }
                            .buttonStyle(.plain)
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

            // Right: detail or add form
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

    // MARK: - Catalog Tab

    private var catalogBody: some View {
        HStack(spacing: 0) {
            // Left: category filter + entry list
            VStack(alignment: .leading, spacing: 0) {
                // Category pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        categoryPill(nil, label: "All")
                        ForEach(MCPCatalogEntry.Category.allCases, id: \.self) { cat in
                            categoryPill(cat, label: cat.rawValue)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }

                Divider().opacity(0.2)

                // Entry list
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(filteredCatalogEntries) { entry in
                            catalogEntryRow(entry)
                        }
                    }
                    .padding(6)
                }
            }
            .frame(width: 220)

            Divider().opacity(0.3)

            // Right: detail + install form
            if let entry = selectedCatalogEntry {
                catalogDetailView(entry)
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 28))
                        .foregroundColor(theme.muted.opacity(0.4))
                    Text("Select a server to install")
                        .font(Typography.body)
                        .foregroundColor(theme.muted)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxHeight: 450)
    }

    private func categoryPill(_ category: MCPCatalogEntry.Category?, label: String) -> some View {
        let isActive = selectedCategory == category
        return Button {
            withAnimation(.easeInOut(duration: 0.1)) {
                selectedCategory = isActive ? nil : category
            }
        } label: {
            HStack(spacing: 4) {
                if let cat = category {
                    Image(systemName: cat.icon).font(.system(size: 9))
                }
                Text(label).font(Typography.caption)
            }
            .foregroundColor(isActive ? theme.sky : theme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? theme.sky.opacity(0.15) : theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private var filteredCatalogEntries: [MCPCatalogEntry] {
        guard let cat = selectedCategory else { return MCPServerManager.catalog }
        return MCPServerManager.catalog.filter { $0.category == cat }
    }

    private func catalogEntryRow(_ entry: MCPCatalogEntry) -> some View {
        let isSelected = selectedCatalogEntry?.id == entry.id
        let isInstalled = mcpManager.isCatalogEntryInstalled(entry)
        return Button {
            selectedCatalogEntry = entry
            catalogParamValues = [:]
        } label: {
            HStack(spacing: 8) {
                Image(systemName: entry.icon)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? theme.sky : theme.muted)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(entry.name)
                            .font(Typography.bodyBold)
                            .foregroundColor(isSelected ? theme.sky : theme.primary)
                        if isInstalled {
                            Text("✓")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(theme.sage)
                        }
                    }
                    Text(entry.category.rawValue)
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? theme.sky.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func catalogDetailView(_ entry: MCPCatalogEntry) -> some View {
        let isInstalled = mcpManager.isCatalogEntryInstalled(entry)
        let justInstalled = installSuccessId == entry.id
        let canInstall = entry.params.filter(\.isRequired).allSatisfy { param in
            let val = catalogParamValues[param.key] ?? ""
            return !val.isEmpty
        }

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Icon + name + category
                HStack(spacing: 10) {
                    Image(systemName: entry.icon)
                        .font(.system(size: 22))
                        .foregroundColor(theme.sky)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(Typography.heading2)
                            .foregroundColor(theme.bright)
                        HStack(spacing: 4) {
                            Image(systemName: entry.category.icon)
                                .font(.system(size: 10))
                            Text(entry.category.rawValue)
                                .font(Typography.caption)
                        }
                        .foregroundColor(theme.muted)
                    }
                    Spacer()
                    if isInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .font(Typography.caption)
                            .foregroundColor(theme.sage)
                    }
                }

                Text(entry.description)
                    .font(Typography.body)
                    .foregroundColor(theme.primary)
                    .fixedSize(horizontal: false, vertical: true)

                // Command preview
                VStack(alignment: .leading, spacing: 4) {
                    Text("Command")
                        .font(Typography.caption)
                        .foregroundColor(theme.muted)
                    Text(entry.commandTemplate)
                        .font(Typography.codeBlock)
                        .foregroundColor(theme.muted)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }

                // Params form
                if !entry.params.isEmpty {
                    Divider().opacity(0.3)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Configuration")
                            .font(Typography.caption)
                            .foregroundColor(theme.muted)

                        ForEach(entry.params) { param in
                            paramField(param, entry: entry)
                        }
                    }
                }

                // Install button
                HStack {
                    Spacer()
                    if justInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .font(Typography.bodyBold)
                            .foregroundColor(theme.sage)
                    } else if isInstalling {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            installEntry(entry)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isInstalled ? "arrow.triangle.2.circlepath" : "plus.circle.fill")
                                    .font(.system(size: 12))
                                Text(isInstalled ? "Reinstall" : "Install")
                                    .font(Typography.bodyBold)
                            }
                            .foregroundColor(canInstall ? theme.sky : theme.muted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(canInstall ? theme.sky.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canInstall)
                    }
                }
            }
            .padding(16)
        }
    }

    private func paramField(_ param: MCPCatalogEntry.Param, entry: MCPCatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(param.displayName)
                    .font(Typography.caption)
                    .foregroundColor(theme.primary)
                if param.isRequired {
                    Text("required")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(theme.rose.opacity(0.8))
                }
            }
            Text(param.description)
                .font(.system(size: 10))
                .foregroundColor(theme.muted)

            let binding = Binding<String>(
                get: { catalogParamValues[param.key] ?? "" },
                set: { catalogParamValues[param.key] = $0 }
            )

            if param.isSecret {
                SecureField(param.placeholder, text: binding)
                    .textFieldStyle(.plain)
                    .font(Typography.codeBlock)
                    .foregroundColor(theme.primary)
                    .padding(7)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                TextField(param.placeholder, text: binding)
                    .textFieldStyle(.plain)
                    .font(Typography.codeBlock)
                    .foregroundColor(theme.primary)
                    .padding(7)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
    }

    private func installEntry(_ entry: MCPCatalogEntry) {
        isInstalling = true
        mcpManager.add(
            name: entry.id,
            transport: .stdio,
            endpoint: entry.resolvedCommand(with: catalogParamValues),
            envVars: entry.resolvedEnvVars(with: catalogParamValues)
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isInstalling = false
            installSuccessId = entry.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if installSuccessId == entry.id { installSuccessId = nil }
            }
        }
    }

    // MARK: - Server Detail (Installed tab)

    private func serverDetailView(_ server: MCPServer) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Circle().fill(statusColor(server.status)).frame(width: 10, height: 10)
                Text(server.name).font(Typography.heading2).foregroundColor(theme.bright)
                Spacer()
                Button {
                    showDeleteConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash").font(.system(size: 11))
                        Text("Remove").font(Typography.caption)
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
            Text("This will remove '\(server.name)' from your configuration.")
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(Typography.caption).foregroundColor(theme.muted)
            Text(value).font(Typography.codeBlock).foregroundColor(theme.primary).textSelection(.enabled)
        }
    }

    // MARK: - Add Form (Installed tab)

    private var addFormView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add MCP Server").font(Typography.heading2).foregroundColor(theme.bright)

                TextField("Server name", text: $newName)
                    .textFieldStyle(.plain).font(Typography.body).foregroundColor(theme.primary)
                    .padding(8).background(theme.surface).clipShape(RoundedRectangle(cornerRadius: 6))

                HStack(spacing: 8) {
                    Text("Transport:").font(Typography.caption).foregroundColor(theme.muted)
                    Picker("", selection: $newTransport) {
                        Text("stdio").tag(MCPTransport.stdio)
                        Text("HTTP").tag(MCPTransport.http)
                    }
                    .pickerStyle(.segmented).frame(width: 160)
                }

                TextField(
                    newTransport == .stdio
                        ? "Command (e.g., npx @modelcontextprotocol/server-github)"
                        : "URL (e.g., http://localhost:3000/mcp)",
                    text: $newEndpoint
                )
                .textFieldStyle(.plain).font(Typography.codeBlock).foregroundColor(theme.primary)
                .padding(8).background(theme.surface).clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Environment Variables").font(Typography.caption).foregroundColor(theme.muted)
                    ForEach(envVars.indices, id: \.self) { i in
                        HStack(spacing: 4) {
                            TextField("Key", text: Binding(get: { envVars[i].key }, set: { envVars[i].key = $0 }))
                                .textFieldStyle(.plain).font(Typography.caption).foregroundColor(theme.primary)
                                .padding(6).background(theme.surface).clipShape(RoundedRectangle(cornerRadius: 4))
                            Text("=").foregroundColor(theme.muted)
                            TextField("Value", text: Binding(get: { envVars[i].value }, set: { envVars[i].value = $0 }))
                                .textFieldStyle(.plain).font(Typography.caption).foregroundColor(theme.primary)
                                .padding(6).background(theme.surface).clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Button {
                        envVars.append(("", ""))
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus").font(.system(size: 9))
                            Text("Add Variable").font(Typography.caption)
                        }
                        .foregroundColor(theme.sky)
                    }
                    .buttonStyle(.plain)
                }

                if newTransport == .http {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Headers").font(Typography.caption).foregroundColor(theme.muted)
                        ForEach(headers.indices, id: \.self) { i in
                            HStack(spacing: 4) {
                                TextField("Header", text: Binding(get: { headers[i].key }, set: { headers[i].key = $0 }))
                                    .textFieldStyle(.plain).font(Typography.caption).foregroundColor(theme.primary)
                                    .padding(6).background(theme.surface).clipShape(RoundedRectangle(cornerRadius: 4))
                                Text(":").foregroundColor(theme.muted)
                                TextField("Value", text: Binding(get: { headers[i].value }, set: { headers[i].value = $0 }))
                                    .textFieldStyle(.plain).font(Typography.caption).foregroundColor(theme.primary)
                                    .padding(6).background(theme.surface).clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        Button {
                            headers.append(("", ""))
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus").font(.system(size: 9))
                                Text("Add Header").font(Typography.caption)
                            }
                            .foregroundColor(theme.sky)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Spacer()
                    Button("Cancel") { showAddForm = false; resetAddForm() }
                        .font(Typography.body).foregroundColor(theme.muted).buttonStyle(.plain)
                    Button("Add Server") {
                        mcpManager.add(
                            name: newName, transport: newTransport, endpoint: newEndpoint,
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
        newName = ""; newTransport = .stdio; newEndpoint = ""
        envVars = [("", "")]; headers = [("", "")]
    }
}
