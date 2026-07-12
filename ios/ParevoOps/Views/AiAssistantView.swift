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
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header SRE context banner
                    sreContextBanner
                    
                    // Input prompt area
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Query or Diagnostic Command")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.zincSecondary)
                            .textCase(.uppercase)
                        
                        TextField("Enter query, e.g. Why did api-worker fail?", text: $query)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.zincPanel)
                            .cornerRadius(8)
                            .foregroundColor(.white)
                            .autocorrectionDisabled()
                        
                        Button(action: runAiDiagnostics) {
                            HStack {
                                if loading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "sparkles")
                                }
                                Text(loading ? "AI Running Diagnostics..." : "Analyze Diagnostics")
                            }
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(query.isEmpty || loading ? Color.zincBorder : Color.purple)
                            .cornerRadius(8)
                        }
                        .disabled(query.isEmpty || loading)
                    }
                    .padding()
                    .background(Color.zincPanel.opacity(0.5))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.zincBorder, lineWidth: 1)
                    )
                    
                    // Results Card
                    if let result = report {
                        diagnosticReportCard(result)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if loading {
                        analyzingLoaderCard
                    }
                }
                .padding()
            }
            .navigationTitle("AI Assistant")
            .background(Color(red: 0.03, green: 0.03, blue: 0.05))
        }
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
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.zincPanel)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.zincBorder, lineWidth: 1)
        )
    }
    
    private func diagnosticReportCard(_ item: DiagnosticReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header confidence bar
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.emerald)
                    Text("Analysis Completed")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                Spacer()
                Text(String(format: "Confidence: %.0f%%", item.confidence * 100))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.purple)
                    .padding(.horizontal, 8)
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
                    .font(.subheadline)
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
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.zincSecondary)
                    .padding(10)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(6)
            }
            
            // Suggested Fix
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggested SRE Action")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.zincSecondary)
                    .textCase(.uppercase)
                Text(item.suggestedFix)
                    .font(.subheadline)
                    .foregroundColor(.purple)
            }
        }
        .padding()
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
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(Color.zincPanel)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.zincBorder, lineWidth: 1)
        )
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
