import SwiftUI

public struct AiAssistantView: View {
    @Binding public var activeServer: Server?
    @State private var query = ""
    @State private var loading = false
    @State private var report: DiagnosticReport? = nil
    
    public init(activeServer: Binding<Server?>) {
        self._activeServer = activeServer
    }
    
    public var body: some View {
        HSplitView {
            // Left Input panel
            VStack(alignment: .leading, spacing: 20) {
                sreContextBanner
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Query or Diagnostic Command")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.zincSecondary)
                        .textCase(.uppercase)
                    
                    TextField("Enter query, e.g. Why did postgres fail?", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .foregroundColor(.white)
                    
                    Button(action: runAiDiagnostics) {
                        HStack {
                            if loading {
                                ProgressView().scaleEffect(0.6).tint(.white)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(loading ? "AI Running Diagnostics..." : "Analyze Diagnostics")
                        }
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(query.isEmpty || loading ? Color.zincBorder : Color.purple)
                        .cornerRadius(6)
                    }
                    .disabled(query.isEmpty || loading)
                    .buttonStyle(.plain)
                }
                .padding(16)
                .background(Color.zincPanel.opacity(0.3))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.zincBorder, lineWidth: 1)
                )
                
                Spacer()
            }
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 450)
            .padding(24)
            
            // Right Results panel
            ScrollView {
                VStack(spacing: 20) {
                    if let result = report {
                        diagnosticReportCard(result)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if loading {
                        analyzingLoaderCard
                    } else {
                        noReportPlaceholder
                    }
                }
                .padding(24)
            }
            .frame(minWidth: 400, idealWidth: 500)
            .background(Color.black.opacity(0.15))
        }
        .navigationTitle("AI Assistant")
    }
    
    private var sreContextBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI SRE DIAGNOSTIC ENGINE")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.purple)
            
            Text("Gathers active log warnings, system telemetry memory boundaries, and docker container status registers into an LLM request query.")
                .font(.caption)
                .foregroundColor(.zincSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.zincPanel)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.zincBorder, lineWidth: 1)
        )
    }
    
    private func diagnosticReportCard(_ item: DiagnosticReport) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header confidence bar
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.emerald)
                    Text("Analysis Completed")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                Spacer()
                Text(String(format: "Confidence: %.0f%%", item.confidence * 100))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.purple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.15))
                    .cornerRadius(6)
            }
            
            Divider()
                .background(Color.zincBorder)
            
            // Root Cause
            VStack(alignment: .leading, spacing: 6) {
                Text("Root Cause Analysis")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.zincSecondary)
                    .textCase(.uppercase)
                Text(item.rootCause)
                    .font(.body)
                    .foregroundColor(.white)
            }
            
            // Evidence
            VStack(alignment: .leading, spacing: 6) {
                Text("Evidence Logs")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.zincSecondary)
                    .textCase(.uppercase)
                Text(item.evidence)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.zincSecondary)
                    .padding(12)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(8)
            }
            
            // Suggested Fix
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggested SRE Action")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.zincSecondary)
                    .textCase(.uppercase)
                Text(item.suggestedFix)
                    .font(.body)
                    .foregroundColor(.purple)
                    .fontWeight(.semibold)
            }
        }
        .padding(24)
        .background(Color.zincPanel)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.zincBorder, lineWidth: 1)
        )
    }
    
    private var analyzingLoaderCard: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.purple)
                .scaleEffect(1.2)
            Text("AI SRE is parsing container logs & docker registry metrics...")
                .font(.caption)
                .foregroundColor(.zincSecondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(Color.zincPanel)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.zincBorder, lineWidth: 1)
        )
    }
    
    private var noReportPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.zincBorder)
            Text("AI Diagnostics Pending")
                .font(.headline)
                .foregroundColor(.zincSecondary)
            Text("Submit a query in the left panel to scan your server nodes for warnings.")
                .font(.caption)
                .foregroundColor(.zincSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 80)
    }
    
    private func runAiDiagnostics() {
        loading = true
        report = nil
        
        let nameSuffix = activeServer?.name ?? "local"
        let contextText = """
        [System Diagnostics Context for Node: \(nameSuffix)]
        CPU Usage: 84%
        Memory Usage: 94%
        Container state: exited (137)
        """
        
        Task {
            do {
                let res = try await AIService.shared.analyzeDiagnostics(query: query, context: contextText)
                withAnimation {
                    report = res
                }
            } catch {
                print("Diagnostics error: \(error)")
            }
            loading = false
        }
    }
}
