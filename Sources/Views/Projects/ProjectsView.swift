import SwiftUI
import SwiftData

// MARK: - Projects (list + detail)

struct ProjectsView: View {
    @Query private var projects: [Project]
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSession.self) private var session
    @Query private var servers: [Server]
    @State private var showCreate = false
    @State private var name = ""
    @State private var descriptionText = ""
    @State private var directory = ""
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if projects.isEmpty {
                    ContentUnavailableView {
                        Label("No Projects", systemImage: "folder.badge.gearshape")
                    } description: {
                        Text("Projects group compose stacks, paths, and deployments.")
                    } actions: {
                        Button("New Project") { showCreate = true }
                        Button("Add CustFind Demo") {
                            modelContext.insert(Project(
                                name: "CustFind",
                                projectDescription: "API, Worker, Redis, PostgreSQL, Nginx",
                                directoryPath: "/var/www/custfind",
                                composeFiles: ["docker-compose.yml"],
                                tags: ["production", "api"]
                            ))
                        }
                    }
                } else {
                    List(projects) { project in
                        NavigationLink(value: project.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(project.name, systemImage: "folder.fill").font(.headline)
                                Text(project.projectDescription)
                                    .font(.subheadline)
                                    .foregroundStyle(BrandColor.textSecondary)
                                    .lineLimit(2)
                                Text(project.directoryPath)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(BrandColor.textMuted)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let project = projects.first(where: { $0.id == id }) {
                    ProjectDetailView(project: project)
                } else {
                    ContentUnavailableView("Project not found", systemImage: "folder")
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreate = true } label: { Label("New Project", systemImage: "plus") }
                }
            }
            .onAppear {
                if let id = session.selectedProjectID {
                    path.append(id)
                    session.selectedProjectID = nil
                }
            }
            .onChange(of: session.selectedProjectID) { _, id in
                if let id {
                    path.append(id)
                    session.selectedProjectID = nil
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                Form {
                    TextField("Name", text: $name)
                    TextField("Description", text: $descriptionText)
                    TextField("Directory", text: $directory, prompt: Text("/var/www/app"))
                }
                .formStyle(.grouped)
                .navigationTitle("New Project")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showCreate = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            let project = Project(name: name, projectDescription: descriptionText, directoryPath: directory)
                            modelContext.insert(project)
                            showCreate = false
                            name = ""; descriptionText = ""; directory = ""
                            path.append(project.id)
                        }
                        .disabled(name.isEmpty || directory.isEmpty)
                    }
                }
            }
            .frame(minWidth: 420, minHeight: 280)
        }
    }
}
