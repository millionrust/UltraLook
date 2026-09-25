import SwiftUI

struct WorkspaceView: View {
    let workspace: Workspace
    @State private var selection: Project?

    var body: some View {
        NavigationSplitView {
            List(workspace.projects, selection: $selection) { project in
                Label(project.name, systemImage: "folder")
            }
            .navigationTitle("Workspace")
        } detail: {
            if let selection {
                ProjectPreview(project: selection)
            } else {
                ContentUnavailableView("Select a project",
                    systemImage: "folder")
            }
        }
    }
}
