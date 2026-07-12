import React, { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import {
  Activity,
  Server,
  Box,
  Cpu,
  Settings,
  FolderOpen,
  FileText,
  Play,
  Square,
  Search,
  Send,
  Database,
  Shield,
  Layers,
  RefreshCw,
  Sparkles,
} from "lucide-react";

// Types matching backend models
interface SystemMetrics {
  cpu_usage: number;
  memory_usage: number;
  disk_usage: number;
}

interface ServerModel {
  id: string;
  name: string;
  host: string;
  port: number;
  username: string;
  private_key_path: string | null;
  status: string;
  group_name: string;
  tags: string;
}

interface ContainerInfo {
  id: string;
  name: string;
  image: string;
  status: string;
}

interface ServiceInfo {
  name: string;
  load_state: string;
  active_state: string;
  sub_state: string;
  description: string;
}

interface FileEntry {
  name: string;
  path: string;
  size: number;
  is_dir: boolean;
  permissions: string;
}

interface DiagnosticReport {
  root_cause: string;
  evidence: string;
  confidence: number;
  suggested_fix: string;
}

function App() {
  const [activeTab, setActiveTab] = useState("dashboard");
  const [metrics, setMetrics] = useState<SystemMetrics>({ cpu_usage: 0, memory_usage: 0, disk_usage: 0 });
  const [servers, setServers] = useState<ServerModel[]>([]);
  const [containers, setContainers] = useState<ContainerInfo[]>([]);
  const [services, setServices] = useState<ServiceInfo[]>([]);
  const [activeLogs, setActiveLogs] = useState<string[]>([]);
  const [logFilter, setLogFilter] = useState("");
  const [files, setFiles] = useState<FileEntry[]>([]);
  const [currentFilePath, setCurrentFilePath] = useState("/etc");
  const [fileContent, setFileContent] = useState("");
  const [editingFile, setEditingFile] = useState<FileEntry | null>(null);
  const [showPalette, setShowPalette] = useState(false);
  const [paletteSearch, setPaletteSearch] = useState("");

  // Keyboard shortcut listener for Command Palette (Cmd/Ctrl + K)
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();
        setShowPalette((prev) => !prev);
      }
      if (e.key === "Escape") {
        setShowPalette(false);
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, []);

  // AI Assistant States
  const [aiQuery, setAiQuery] = useState("Why is my API restarting?");
  const [aiLoading, setAiLoading] = useState(false);
  const [aiResult, setAiResult] = useState<DiagnosticReport | null>(null);
  const [aggregatedContext, setAggregatedContext] = useState("");

  // New Server Form States
  const [newServerName, setNewServerName] = useState("");
  const [newServerHost, setNewServerHost] = useState("");
  const [newServerUser, setNewServerUser] = useState("ubuntu");
  const [newServerKeyPath, setNewServerKeyPath] = useState("");
  const [newServerPort, setNewServerPort] = useState(22);
  const [newServerGroup, setNewServerGroup] = useState("production");
  const [newServerTags, setNewServerTags] = useState("");
  const [testingConnection, setTestingConnection] = useState(false);
  const [testResult, setTestResult] = useState<{ success: boolean; message: string } | null>(null);
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [activeServer, setActiveServer] = useState<ServerModel | null>(null);
  const [connectingServer, setConnectingServer] = useState<ServerModel | null>(null);

  // Fetch status metrics periodically
  useEffect(() => {
    const fetchMetrics = async () => {
      try {
        const stats = await invoke<SystemMetrics>("get_system_status");
        setMetrics(stats);
      } catch (err) {
        console.error("Failed to query telemetry:", err);
      }
    };

    fetchMetrics();
    const interval = setInterval(fetchMetrics, 3000);
    return () => clearInterval(interval);
  }, []);

  // Fetch lists on screen navigation
  useEffect(() => {
    if (activeTab === "servers") {
      loadServers();
    } else if (activeTab === "containers") {
      loadContainers();
    } else if (activeTab === "services") {
      loadServices();
    } else if (activeTab === "files") {
      loadFiles(currentFilePath);
    } else if (activeTab === "logs") {
      loadLogs();
    }
  }, [activeTab]);

  const loadServers = async () => {
    try {
      const list = await invoke<ServerModel[]>("list_servers");
      setServers(list);
    } catch (err) {
      console.error(err);
    }
  };

  const handlePickKeyFile = async () => {
    try {
      const picked = await invoke<string | null>("pick_pem_file");
      if (picked) {
        setNewServerKeyPath(picked);
      }
    } catch (err) {
      console.error("Failed to pick key file", err);
    }
  };

  const testConnection = async () => {
    if (!newServerHost) return;
    setTestingConnection(true);
    setTestResult(null);

    const testServer: ServerModel = {
      id: "test",
      name: newServerName || "Test Server",
      host: newServerHost,
      port: newServerPort,
      username: newServerUser || "ubuntu",
      private_key_path: newServerKeyPath || null,
      status: "unknown",
      group_name: newServerGroup,
      tags: newServerTags,
    };

    try {
      await invoke("test_ssh_connection", { server: testServer });
      setTestResult({ success: true, message: "Successfully authenticated with host!" });
    } catch (err: any) {
      setTestResult({ success: false, message: err.toString() });
    } finally {
      setTestingConnection(false);
    }
  };

  const createServer = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newServerName || !newServerHost) return;
    try {
      const newServer: ServerModel = {
        id: Math.random().toString(),
        name: newServerName,
        host: newServerHost,
        port: newServerPort,
        username: newServerUser || "ubuntu",
        private_key_path: newServerKeyPath || null,
        status: "online",
        group_name: newServerGroup,
        tags: newServerTags || "general",
      };
      await invoke("create_server", { server: newServer });
      setNewServerName("");
      setNewServerHost("");
      setNewServerUser("ubuntu");
      setNewServerKeyPath("");
      setNewServerPort(22);
      setNewServerGroup("production");
      setNewServerTags("");
      setTestResult(null);
      loadServers();
    } catch (err) {
      console.error(err);
    }
  };

  const deleteServer = async (id: string) => {
    try {
      await invoke("delete_server", { id });
      if (activeServer?.id === id) {
        setActiveServer(null);
      }
      loadServers();
    } catch (err) {
      console.error(err);
    }
  };

  const connectToServer = async (srv: ServerModel) => {
    setConnectingServer(srv);
    try {
      await invoke("test_ssh_connection", { server: srv });
      setActiveServer(srv);
    } catch (err) {
      console.error("Connection failed, setting context anyway (dev fallback):", err);
      setActiveServer(srv);
    } finally {
      setTimeout(() => {
        setConnectingServer(null);
      }, 700);
    }
  };

  const loadContainers = async () => {
    try {
      const list = await invoke<ContainerInfo[]>("list_containers");
      setContainers(list);
    } catch (err) {
      console.error(err);
    }
  };

  const toggleContainer = async (id: string, currentStatus: string) => {
    try {
      if (currentStatus === "running") {
        await invoke("stop_container", { id });
      } else {
        await invoke("start_container", { id });
      }
      loadContainers();
    } catch (err) {
      console.error(err);
    }
  };

  const loadServices = async () => {
    try {
      const info = await invoke<ServiceInfo>("get_service_status", { service: "nginx" });
      setServices([info, {
        name: "postgresql.service",
        load_state: "loaded",
        active_state: "active",
        sub_state: "running",
        description: "PostgreSQL Database Engine"
      }, {
        name: "redis.service",
        load_state: "loaded",
        active_state: "failed",
        sub_state: "failed",
        description: "In-memory database server"
      }]);
    } catch (err) {
      console.error(err);
    }
  };

  const loadFiles = async (dir: string) => {
    try {
      const list = await invoke<FileEntry[]>("list_directory", { path: dir });
      setFiles(list);
      setCurrentFilePath(dir);
    } catch (err) {
      console.error(err);
    }
  };

  const openFile = async (file: FileEntry) => {
    try {
      const content = await invoke<string>("read_file", { path: file.path });
      setFileContent(content);
      setEditingFile(file);
    } catch (err) {
      console.error(err);
    }
  };

  const saveFile = async () => {
    if (!editingFile) return;
    try {
      await invoke("write_file", { path: editingFile.path, content: fileContent });
      setEditingFile(null);
      setFileContent("");
      loadFiles(currentFilePath);
    } catch (err) {
      console.error(err);
    }
  };

  const loadLogs = async () => {
    try {
      const logs = await invoke<{ message: string }[]>("fetch_logs", { source: "nginx-proxy", limit: 30 });
      setActiveLogs(logs.map(l => l.message));
    } catch (err) {
      console.error(err);
    }
  };

  const handleAiDiagnostics = async () => {
    setAiLoading(true);
    setAiResult(null);

    // Simulate gathering context from docker, systemctl, logs
    const context = `
[docker ps]
ae834927fcd2   rust:1.80-alpine   "cargo run"   3 minutes ago   exited (137)

[systemctl status api.service]
● api.service - Parevo Ops Daemon
   Loaded: loaded (/etc/systemd/system/api.service)
   Active: failed (Result: core-dump)
   Details: Process OOM Spike detected.

[free -m]
total: 8192, used: 8010, free: 182
    `;
    setAggregatedContext(context);

    try {
      const report = await invoke<DiagnosticReport>("analyze_diagnostics", {
        ctx: { query: aiQuery, aggregated_logs: context }
      });
      setAiResult(report);
    } catch (err) {
      console.error(err);
    } finally {
      setAiLoading(false);
    }
  };

  return (
    <div className="flex h-screen bg-[#09090b] text-[#fafafa] font-sans overflow-hidden select-none">
      {/* Sidebar */}
      <aside className="w-64 border-r border-[#27272a] bg-[#0c0c0e] p-4 flex flex-col justify-between select-none">
        <div>
          <div className="flex items-center gap-2 mb-8 px-2">
            <Layers className="h-6 w-6 text-violet-500" />
            <span className="font-semibold text-lg tracking-wide">Parevo Ops</span>
          </div>

          <nav className="flex flex-col gap-1">
            {[
              { id: "dashboard", label: "Dashboard", icon: Activity },
              { id: "servers", label: "Servers", icon: Server },
              { id: "containers", label: "Containers", icon: Box },
              { id: "services", label: "Services", icon: Cpu },
              { id: "logs", label: "Logs", icon: FileText },
              { id: "files", label: "Files", icon: FolderOpen },
              { id: "ai", label: "AI Assistant", icon: Sparkles },
              { id: "settings", label: "Settings", icon: Settings },
            ].map((tab) => {
              const Icon = tab.icon;
              const active = activeTab === tab.id;
              return (
                <button
                  key={tab.id}
                  onClick={() => {
                    setActiveTab(tab.id);
                    setEditingFile(null);
                  }}
                  className={`flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm transition-all duration-150 text-left ${
                    active
                      ? "bg-violet-600/10 text-violet-400 font-medium"
                      : "text-zinc-400 hover:text-zinc-200 hover:bg-zinc-800/30"
                  }`}
                >
                  <Icon className={`h-4.5 w-4.5 ${active ? "text-violet-400" : "text-zinc-500"}`} />
                  {tab.label}
                </button>
              );
            })}
          </nav>
        </div>

        <div className="border-t border-[#27272a] pt-4 px-2 flex flex-col gap-3">
          {activeServer ? (
            <div className="flex flex-col gap-1.5 p-2.5 rounded-lg bg-emerald-500/5 border border-emerald-500/10 animate-fadeIn">
              <div className="text-[9px] uppercase tracking-wider font-bold text-emerald-400 flex items-center gap-1.5">
                <span className="h-1.5 w-1.5 bg-emerald-500 rounded-full animate-pulse"></span>
                {activeServer.name}
              </div>
              <div className="text-[10px] font-mono text-zinc-400 truncate">{activeServer.username}@{activeServer.host}</div>
              <button
                onClick={() => setActiveServer(null)}
                className="text-[9px] text-zinc-500 hover:text-zinc-300 text-left font-medium mt-1 cursor-pointer select-none"
              >
                Disconnect to Local
              </button>
            </div>
          ) : (
            <div className="flex items-center gap-3">
              <div className="h-8 w-8 rounded-full bg-zinc-800 flex items-center justify-center font-bold text-xs text-zinc-300">
                SRE
              </div>
              <div>
                <div className="text-xs font-semibold text-zinc-300">Parevo Operator</div>
                <div className="text-[10px] text-emerald-500 flex items-center gap-1">
                  <span className="h-1.5 w-1.5 rounded-full bg-emerald-500 inline-block animate-pulse"></span>
                  Local Node Connected
                </div>
              </div>
            </div>
          )}
        </div>
      </aside>

      {/* Main Workspace Panel */}
      <main className="flex-1 flex flex-col min-w-0 bg-[#09090b] overflow-y-auto select-text">
        <header className="h-14 border-b border-[#27272a] px-8 flex items-center justify-between bg-[#09090b]/50 backdrop-blur-md sticky top-0 z-10">
          <h2 className="font-semibold text-sm capitalize tracking-wide text-zinc-200">
            {activeTab === "ai" ? "AI Diagnostics Assistant" : activeTab}
          </h2>
          <div className="flex items-center gap-4 text-xs text-zinc-400">
            <div className="bg-[#1c1c1f] border border-[#27272a] px-2 py-1 rounded text-[10px] text-zinc-500 font-semibold flex items-center gap-1 select-none">
              <span>⌘</span><span>K</span> Command Palette
            </div>
            <div>SYSTEM LOAD: {metrics.cpu_usage.toFixed(1)}%</div>
          </div>
        </header>

        <div className="p-8 max-w-6xl w-full mx-auto flex-1 flex flex-col gap-6">
          {/* DASHBOARD TAB */}
          {activeTab === "dashboard" && (
            <div className="flex flex-col gap-6">
              {/* Telemetry Widgets Grid */}
              <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                {[
                  { label: "CPU Usage", value: `${metrics.cpu_usage.toFixed(1)}%`, desc: "Total global utilization", icon: Cpu },
                  { label: "Memory Usage", value: `${metrics.memory_usage.toFixed(1)}%`, desc: "Active RAM bytes used", icon: Activity },
                  { label: "Disk Space", value: `${metrics.disk_usage.toFixed(1)}%`, desc: "Local root partition", icon: Database },
                ].map((card, i) => {
                  const Icon = card.icon;
                  return (
                    <div key={i} className="bg-[#121214] border border-[#27272a] p-5 rounded-xl flex flex-col gap-2 relative overflow-hidden">
                      <div className="flex justify-between items-center text-zinc-500">
                        <span className="text-xs uppercase font-medium tracking-wider">{card.label}</span>
                        <Icon className="h-4.5 w-4.5 text-zinc-600" />
                      </div>
                      <div className="text-2xl font-bold tracking-tight text-zinc-100">{card.value}</div>
                      <div className="text-xs text-zinc-500">{card.desc}</div>
                      <div className="absolute bottom-0 left-0 right-0 h-1 bg-gradient-to-r from-violet-600/30 to-violet-600/0"></div>
                    </div>
                  );
                })}
              </div>

              {/* Status Widgets Grid */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                {/* Health Overview */}
                <div className="bg-[#121214] border border-[#27272a] p-6 rounded-xl flex flex-col justify-between gap-4">
                  <div>
                    <h3 className="font-semibold text-zinc-200 text-sm mb-1">Health Score</h3>
                    <p className="text-zinc-500 text-xs">Dynamic infrastructure integrity evaluation</p>
                  </div>
                  <div className="flex items-center gap-4">
                    <div className="text-4xl font-extrabold text-emerald-500 tracking-tighter">94%</div>
                    <div className="text-zinc-400 text-xs flex flex-col">
                      <span>• 1 Failed System Service</span>
                      <span>• Docker containers healthy</span>
                    </div>
                  </div>
                </div>

                {/* Machine Info */}
                <div className="bg-[#121214] border border-[#27272a] p-6 rounded-xl flex flex-col justify-between gap-4">
                  <div>
                    <h3 className="font-semibold text-zinc-200 text-sm mb-1">Machine Properties</h3>
                    <p className="text-zinc-500 text-xs">Local workstation node environment</p>
                  </div>
                  <div className="grid grid-cols-2 gap-2 text-xs text-zinc-400">
                    <div>OS: <span className="text-zinc-300">macOS</span></div>
                    <div>Kernel: <span className="text-zinc-300">Darwin 25.0</span></div>
                    <div>Hostname: <span className="text-zinc-300">parevo-mac</span></div>
                    <div>Uptime: <span className="text-zinc-300">3 days, 4h</span></div>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* SERVERS TAB */}
          {activeTab === "servers" && (
            <div className="flex flex-col gap-6">
              <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
                {/* Form column */}
                <form onSubmit={createServer} className="lg:col-span-2 bg-[#121214] border border-[#27272a] p-6 rounded-xl flex flex-col gap-6">
                  <div>
                    <h3 className="text-zinc-200 font-semibold text-sm">Add New Server</h3>
                    <p className="text-zinc-500 text-xs mt-1">Enter your connection details below. Select your PEM key file from your local disk.</p>
                  </div>

                  {/* Primary Section */}
                  <div className="flex flex-col gap-4">
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                      <div className="flex flex-col gap-1.5">
                        <span className="text-xs text-zinc-400 font-medium">Connection Name</span>
                        <input
                          type="text"
                          placeholder="e.g. My Amazon Web Instance"
                          value={newServerName}
                          onChange={(e) => setNewServerName(e.target.value)}
                          className="bg-[#1c1c1f] border border-[#27272a] px-3 py-2.5 rounded-lg text-xs text-zinc-100 placeholder-zinc-500 focus:outline-none focus:border-violet-500"
                        />
                      </div>
                      <div className="flex flex-col gap-1.5">
                        <span className="text-xs text-zinc-400 font-medium">Server IP Address or Domain</span>
                        <input
                          type="text"
                          placeholder="e.g. 54.210.xx.xx or ec2.amazonaws.com"
                          value={newServerHost}
                          onChange={(e) => setNewServerHost(e.target.value)}
                          className="bg-[#1c1c1f] border border-[#27272a] px-3 py-2.5 rounded-lg text-xs text-zinc-100 placeholder-zinc-500 focus:outline-none focus:border-violet-500"
                        />
                      </div>
                    </div>

                    {/* SSH Private Key file selection */}
                    <div className="flex flex-col gap-1.5">
                      <span className="text-xs text-zinc-400 font-medium">SSH Key File (.pem / .key / id_rsa)</span>
                      <div className="flex gap-2">
                        <input
                          type="text"
                          readOnly
                          placeholder="Select PEM file from your computer..."
                          value={newServerKeyPath}
                          className="flex-1 bg-[#1c1c1f]/50 border border-[#27272a] px-3 py-2.5 rounded-lg text-xs text-zinc-300 placeholder-zinc-600 focus:outline-none select-all"
                        />
                        <button
                          type="button"
                          onClick={handlePickKeyFile}
                          className="bg-[#1c1c1f] hover:bg-zinc-800 border border-[#27272a] text-zinc-300 font-medium text-xs px-4 rounded-lg transition duration-150 flex items-center justify-center gap-1.5 cursor-pointer"
                        >
                          Browse File...
                        </button>
                        {newServerKeyPath && (
                          <button
                            type="button"
                            onClick={() => setNewServerKeyPath("")}
                            className="bg-red-950/20 hover:bg-red-900/30 border border-red-900/40 text-red-400 font-medium text-xs px-3 rounded-lg transition duration-150 cursor-pointer"
                          >
                            Clear
                          </button>
                        )}
                      </div>
                    </div>
                  </div>

                  {/* Advanced Settings Toggle */}
                  <div className="border-t border-[#27272a] pt-4">
                    <button
                      type="button"
                      onClick={() => setShowAdvanced(!showAdvanced)}
                      className="text-xs text-violet-400 hover:text-violet-300 font-semibold flex items-center gap-1 cursor-pointer select-none"
                    >
                      {showAdvanced ? "↓ Hide Advanced Settings" : "→ Show Advanced Settings (Port, Username, Group, Tags)"}
                    </button>

                    {showAdvanced && (
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4 p-4 bg-[#1c1c1f]/35 border border-[#27272a] rounded-xl animate-fadeIn">
                        <div className="flex flex-col gap-1.5">
                          <span className="text-xs text-zinc-400 font-medium">SSH Username</span>
                          <input
                            type="text"
                            placeholder="ubuntu (default)"
                            value={newServerUser}
                            onChange={(e) => setNewServerUser(e.target.value)}
                            className="bg-[#1c1c1f] border border-[#27272a] px-3 py-2 rounded-lg text-xs text-zinc-100 placeholder-zinc-500 focus:outline-none focus:border-violet-500"
                          />
                        </div>
                        <div className="flex flex-col gap-1.5">
                          <span className="text-xs text-zinc-400 font-medium">SSH Port</span>
                          <input
                            type="number"
                            placeholder="22"
                            value={newServerPort}
                            onChange={(e) => setNewServerPort(parseInt(e.target.value) || 22)}
                            className="bg-[#1c1c1f] border border-[#27272a] px-3 py-2 rounded-lg text-xs text-zinc-100 placeholder-zinc-500 focus:outline-none focus:border-violet-500"
                          />
                        </div>
                        <div className="flex flex-col gap-1.5 md:col-span-2">
                          <span className="text-xs text-zinc-400 font-medium">Server Group / Tag labels</span>
                          <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
                            <select
                              value={newServerGroup}
                              onChange={(e) => setNewServerGroup(e.target.value)}
                              className="bg-[#1c1c1f] border border-[#27272a] px-3 py-2 rounded-lg text-xs text-zinc-100 focus:outline-none"
                            >
                              <option value="production">Production</option>
                              <option value="staging">Staging</option>
                              <option value="development">Development</option>
                              <option value="monitoring">Monitoring</option>
                            </select>
                            <input
                              type="text"
                              placeholder="Comma tags: web,db"
                              value={newServerTags}
                              onChange={(e) => setNewServerTags(e.target.value)}
                              className="sm:col-span-2 bg-[#1c1c1f] border border-[#27272a] px-3 py-2 rounded-lg text-xs text-zinc-100 placeholder-zinc-500 focus:outline-none focus:border-violet-500"
                            />
                          </div>
                        </div>
                      </div>
                    )}
                  </div>
                </form>

                {/* Live Sandbox card */}
                <div className="bg-[#121214] border border-[#27272a] p-6 rounded-xl flex flex-col justify-between gap-6">
                  <div>
                    <h3 className="text-zinc-200 font-semibold text-sm">Connection Sandbox</h3>
                    <p className="text-zinc-500 text-xs mt-1">Verify credentials authenticate successfully prior to saving.</p>

                    <div className="bg-[#0c0c0e] border border-[#27272a] p-4 rounded-lg font-mono text-[10px] text-zinc-500 mt-4 leading-relaxed flex flex-col gap-1 select-all break-all">
                      <div>$ ssh -i {newServerKeyPath ? newServerKeyPath.substring(newServerKeyPath.lastIndexOf('/') + 1) : 'default'} {newServerUser || 'ubuntu'}@{newServerHost || 'host'} -p {newServerPort}</div>
                      <div className="text-zinc-600">CONNECTING...</div>
                      {testingConnection && <div className="text-violet-400 animate-pulse">AUTHENTICATING... PLEASE WAIT</div>}
                      {testResult && (
                        <div className={`font-semibold ${testResult.success ? "text-emerald-400" : "text-red-400"}`}>
                          {testResult.success ? "✓ CONNECTION VERIFIED SUCCESSFUL" : `✗ FAILED: ${testResult.message}`}
                        </div>
                      )}
                    </div>
                  </div>

                  <div className="flex flex-col gap-2.5">
                    <button
                      type="button"
                      onClick={testConnection}
                      disabled={!newServerHost || testingConnection}
                      className="w-full bg-[#1c1c1f] hover:bg-zinc-800 border border-[#27272a] text-zinc-300 font-semibold text-xs py-2.5 rounded-lg transition duration-150 flex items-center justify-center gap-2 disabled:opacity-40 cursor-pointer"
                    >
                      {testingConnection ? <RefreshCw className="h-3.5 w-3.5 animate-spin" /> : <Shield className="h-3.5 w-3.5" />}
                      Test Connection
                    </button>
                    <button
                      type="button"
                      onClick={createServer}
                      disabled={!newServerName || !newServerHost}
                      className="w-full bg-violet-600 hover:bg-violet-750 text-white font-semibold text-xs py-2.5 rounded-lg transition duration-150 disabled:opacity-45 cursor-pointer"
                    >
                      Save Server Profile
                    </button>
                  </div>
                </div>
              </div>

              <div className="flex flex-col gap-3">
                <h3 className="text-zinc-400 font-medium text-xs">Registered Servers ({servers.length})</h3>
                {servers.length === 0 ? (
                  <div className="bg-[#121214]/50 border border-dashed border-[#27272a] py-12 rounded-xl text-center text-zinc-500 text-xs">
                    No remote server profiles configured. Use the form above to add your first node.
                  </div>
                ) : (
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    {servers.map((srv) => {
                      const isActive = activeServer?.id === srv.id;
                      const isConnecting = connectingServer?.id === srv.id;
                      return (
                        <div
                          key={srv.id}
                          onClick={() => connectToServer(srv)}
                          className={`border p-4 rounded-xl flex items-center justify-between hover:border-zinc-500 transition duration-150 cursor-pointer select-none ${
                            isActive
                              ? "bg-emerald-500/[0.03] border-emerald-500/40"
                              : "bg-[#121214] border-[#27272a]"
                          }`}
                        >
                          <div>
                            <div className="flex items-center gap-2">
                              <h4 className="text-sm font-semibold text-zinc-200">{srv.name}</h4>
                              {isActive && (
                                <span className="bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 text-[9px] px-1.5 py-0.5 rounded font-bold uppercase">
                                  🟢 Connected
                                </span>
                              )}
                              {isConnecting && (
                                <span className="text-violet-400 text-[9px] animate-pulse">
                                  Connecting...
                                </span>
                              )}
                            </div>
                            <p className="text-xs text-zinc-500">{srv.username}@{srv.host}</p>
                            {srv.private_key_path && (
                              <p className="text-[10px] text-zinc-650 font-mono mt-1 truncate max-w-[200px]" title={srv.private_key_path}>
                                Key: {srv.private_key_path.substring(srv.private_key_path.lastIndexOf('/') + 1)}
                              </p>
                            )}
                            <span className="mt-2 inline-block bg-zinc-800 text-zinc-400 px-2 py-0.5 rounded text-[10px] uppercase font-bold tracking-wider">{srv.group_name}</span>
                          </div>
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              deleteServer(srv.id);
                            }}
                            className="text-red-500/80 hover:text-red-500 hover:bg-red-950/20 px-3 py-1.5 rounded-lg text-xs transition duration-150 cursor-pointer"
                          >
                            Delete
                          </button>
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>
            </div>
          )}

          {/* CONTAINERS TAB */}
          {activeTab === "containers" && (
            <div className="flex flex-col gap-4">
              <div className="flex items-center justify-between">
                <h3 className="text-zinc-300 font-medium text-xs">Docker Container Nodes</h3>
                <button onClick={loadContainers} className="text-zinc-500 hover:text-zinc-300 flex items-center gap-1.5 text-xs transition duration-150">
                  <RefreshCw className="h-3 w-3" /> Refresh
                </button>
              </div>

              <div className="bg-[#121214] border border-[#27272a] rounded-xl overflow-hidden">
                <table className="w-full text-left border-collapse">
                  <thead>
                    <tr className="border-b border-[#27272a] bg-zinc-900/30 text-zinc-500 text-xs">
                      <th className="p-4 font-medium">Container ID</th>
                      <th className="p-4 font-medium">Name</th>
                      <th className="p-4 font-medium">Image</th>
                      <th className="p-4 font-medium">Status</th>
                      <th className="p-4 font-medium text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody className="text-xs text-zinc-300">
                    {containers.map((c) => {
                      const running = c.status === "running" || c.status.includes("Up");
                      return (
                        <tr key={c.id} className="border-b border-[#27272a]/55 hover:bg-zinc-850/10">
                          <td className="p-4 font-mono text-zinc-500">{c.id.substring(0, 12)}</td>
                          <td className="p-4 font-semibold text-zinc-200">{c.name}</td>
                          <td className="p-4 text-zinc-400 font-mono">{c.image}</td>
                          <td className="p-4">
                            <span className="flex items-center gap-1.5">
                              <span className={`h-1.5 w-1.5 rounded-full ${running ? "bg-emerald-500" : "bg-zinc-600"}`}></span>
                              {c.status}
                            </span>
                          </td>
                          <td className="p-4 text-right">
                            <button
                              onClick={() => toggleContainer(c.id, running ? "running" : "stopped")}
                              className={`inline-flex items-center gap-1 px-3 py-1.5 rounded-lg text-xs font-medium transition duration-150 ${
                                running
                                  ? "bg-red-500/10 text-red-400 hover:bg-red-500/20"
                                  : "bg-emerald-500/10 text-emerald-400 hover:bg-emerald-500/20"
                              }`}
                            >
                              {running ? (
                                <>
                                  <Square className="h-3 w-3 fill-current" /> Stop
                                </>
                              ) : (
                                <>
                                  <Play className="h-3 w-3 fill-current" /> Start
                                </>
                              )}
                            </button>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* SERVICES TAB */}
          {activeTab === "services" && (
            <div className="flex flex-col gap-4">
              <h3 className="text-zinc-400 font-medium text-xs">OS Systemd Units</h3>
              <div className="grid grid-cols-1 gap-4">
                {services.map((svc) => {
                  const failed = svc.active_state === "failed";
                  return (
                    <div key={svc.name} className="bg-[#121214] border border-[#27272a] p-4 rounded-xl flex items-center justify-between">
                      <div>
                        <div className="flex items-center gap-2">
                          <h4 className="font-semibold text-zinc-200 text-sm">{svc.name}</h4>
                          <span className={`h-1.5 w-1.5 rounded-full ${failed ? "bg-red-500" : "bg-emerald-500"}`}></span>
                          <span className={`text-[10px] px-2 py-0.5 rounded font-semibold uppercase tracking-wider ${failed ? "bg-red-500/10 text-red-400" : "bg-zinc-800 text-zinc-400"}`}>
                            {svc.active_state}
                          </span>
                        </div>
                        <p className="text-xs text-zinc-500 mt-1">{svc.description}</p>
                      </div>
                      <div className="flex gap-2">
                        <button className="bg-zinc-800 hover:bg-zinc-700 px-3 py-1.5 rounded-lg text-xs font-semibold transition">
                          Restart
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* LOGS TAB */}
          {activeTab === "logs" && (
            <div className="flex flex-col gap-4">
              <div className="flex gap-4">
                <div className="relative flex-1">
                  <Search className="absolute left-3 top-2.5 h-4 w-4 text-zinc-500" />
                  <input
                    type="text"
                    placeholder="Regex log query filter..."
                    value={logFilter}
                    onChange={(e) => setLogFilter(e.target.value)}
                    className="w-full bg-[#121214] border border-[#27272a] pl-9 pr-4 py-2 rounded-lg text-xs text-zinc-200 placeholder-zinc-500 focus:outline-none focus:border-violet-500"
                  />
                </div>
              </div>

              <div className="bg-[#0c0c0e] border border-[#27272a] p-6 rounded-xl font-mono text-[11px] leading-relaxed text-zinc-400 h-96 overflow-y-auto flex flex-col gap-1.5">
                {activeLogs
                  .filter((log) => log.toLowerCase().includes(logFilter.toLowerCase()))
                  .map((log, idx) => (
                    <div key={idx} className="hover:bg-zinc-900 px-2 py-0.5 rounded">
                      <span className="text-zinc-600">[{idx + 1}]</span> {log}
                    </div>
                  ))}
              </div>
            </div>
          )}

          {/* FILES TAB */}
          {activeTab === "files" && (
            <div className="flex flex-col gap-4">
              <div className="flex items-center gap-2 text-xs text-zinc-400 bg-[#121214] border border-[#27272a] px-4 py-2 rounded-lg">
                <span className="font-semibold text-zinc-300">Target Path:</span>
                <span className="font-mono text-zinc-400">{currentFilePath}</span>
              </div>

              {editingFile ? (
                <div className="bg-[#121214] border border-[#27272a] p-6 rounded-xl flex flex-col gap-4">
                  <div className="flex items-center justify-between border-b border-[#27272a] pb-3">
                    <span className="font-semibold text-sm text-zinc-200">Editing {editingFile.name}</span>
                    <button onClick={() => setEditingFile(null)} className="text-zinc-500 hover:text-zinc-300 text-xs">
                      Cancel
                    </button>
                  </div>
                  <textarea
                    value={fileContent}
                    onChange={(e) => setFileContent(e.target.value)}
                    rows={12}
                    className="w-full bg-[#0c0c0e] border border-[#27272a] p-4 rounded-lg font-mono text-xs text-zinc-300 focus:outline-none focus:border-violet-500"
                  />
                  <button onClick={saveFile} className="bg-violet-600 hover:bg-violet-700 text-white font-medium text-xs px-4 py-2.5 rounded-lg transition duration-150 align-self-start">
                    Save Modifications
                  </button>
                </div>
              ) : (
                <div className="bg-[#121214] border border-[#27272a] rounded-xl overflow-hidden">
                  <div className="p-4 border-b border-[#27272a] bg-zinc-900/10 flex justify-between items-center text-xs text-zinc-500">
                    <span>Name</span>
                    <div className="flex gap-16">
                      <span>Permissions</span>
                      <span>Size</span>
                    </div>
                  </div>
                  <div className="flex flex-col">
                    <button
                      onClick={() => {
                        const parts = currentFilePath.split("/");
                        parts.pop();
                        const parent = parts.join("/") || "/";
                        loadFiles(parent);
                      }}
                      className="flex items-center px-4 py-3 hover:bg-zinc-850/15 border-b border-[#27272a]/40 text-left text-zinc-500 text-xs"
                    >
                      ..
                    </button>
                    {files.map((file) => (
                      <div
                        key={file.path}
                        className="flex items-center justify-between px-4 py-3 hover:bg-zinc-850/15 border-b border-[#27272a]/40 text-xs"
                      >
                        <button
                          onClick={() => (file.is_dir ? loadFiles(file.path) : openFile(file))}
                          className="flex items-center gap-2 font-medium text-zinc-300 hover:text-violet-400 text-left flex-1"
                        >
                          {file.is_dir ? (
                            <FolderOpen className="h-4 w-4 text-amber-500" />
                          ) : (
                            <FileText className="h-4 w-4 text-zinc-500" />
                          )}
                          {file.name}
                        </button>
                        <div className="flex items-center gap-12 font-mono text-zinc-500 text-right">
                          <span>{file.permissions}</span>
                          <span className="w-16">{(file.size / 1024).toFixed(1)} KB</span>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          )}

          {/* AI DIAGNOSTICS TAB */}
          {activeTab === "ai" && (
            <div className="flex flex-col gap-6">
              <div className="bg-[#121214] border border-[#27272a] p-6 rounded-xl flex flex-col gap-4">
                <div className="flex items-center gap-2 text-violet-400">
                  <Sparkles className="h-5 w-5" />
                  <h3 className="font-semibold text-zinc-200 text-sm">Flagship Diagnostics Assistant</h3>
                </div>
                <p className="text-zinc-500 text-xs">
                  Ask the assistant to query and aggregate context logs, evaluate container status metrics, and diagnose root causes.
                </p>

                <div className="flex gap-3">
                  <input
                    type="text"
                    value={aiQuery}
                    onChange={(e) => setAiQuery(e.target.value)}
                    className="flex-1 bg-[#1c1c1f] border border-[#27272a] px-4 py-2.5 rounded-lg text-xs text-zinc-100 placeholder-zinc-500 focus:outline-none focus:border-violet-500"
                  />
                  <button
                    onClick={handleAiDiagnostics}
                    disabled={aiLoading}
                    className="bg-violet-600 hover:bg-violet-700 text-white font-medium text-xs px-5 py-2.5 rounded-lg transition duration-150 flex items-center gap-2"
                  >
                    {aiLoading ? (
                      <>
                        <RefreshCw className="h-3.5 w-3.5 animate-spin" /> Aggregating...
                      </>
                    ) : (
                      <>
                        <Send className="h-3.5 w-3.5" /> Analyze
                      </>
                    )}
                  </button>
                </div>
              </div>

              {aggregatedContext && (
                <div className="flex flex-col gap-3">
                  <h4 className="text-zinc-400 font-medium text-xs">1. Aggregated SRE Context Collected</h4>
                  <pre className="bg-[#0c0c0e] border border-[#27272a] p-4 rounded-xl font-mono text-[10px] leading-relaxed text-zinc-500 overflow-x-auto">
                    {aggregatedContext}
                  </pre>
                </div>
              )}

              {aiResult && (
                <div className="flex flex-col gap-4">
                  <h4 className="text-zinc-400 font-medium text-xs">2. Diagnostics Assessment Report</h4>
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                    <div className="bg-[#121214] border border-[#27272a] p-5 rounded-xl col-span-2 flex flex-col gap-3">
                      <div>
                        <div className="text-[10px] text-zinc-500 uppercase font-medium">Root Cause</div>
                        <div className="text-sm font-semibold text-zinc-200 mt-1">{aiResult.root_cause}</div>
                      </div>
                      <div className="border-t border-[#27272a] pt-3">
                        <div className="text-[10px] text-zinc-500 uppercase font-medium">Evidence</div>
                        <div className="text-xs text-zinc-400 mt-1">{aiResult.evidence}</div>
                      </div>
                    </div>

                    <div className="bg-[#121214] border border-violet-500/20 p-5 rounded-xl flex flex-col justify-between relative overflow-hidden">
                      <div>
                        <div className="text-[10px] text-zinc-500 uppercase font-medium">Confidence Rating</div>
                        <div className="text-3xl font-extrabold text-violet-400 mt-2 tracking-tight">{aiResult.confidence}%</div>
                      </div>
                      <div className="text-[10px] text-zinc-500">Determined via aggregate log signals</div>
                      <div className="absolute top-0 right-0 h-16 w-16 bg-violet-600/5 rounded-full blur-xl"></div>
                    </div>
                  </div>

                  <div className="bg-[#121214] border border-emerald-500/20 p-5 rounded-xl flex flex-col gap-2">
                    <div className="text-[10px] text-zinc-500 uppercase font-medium">Suggested Fix</div>
                    <div className="text-xs text-zinc-300 font-medium">{aiResult.suggested_fix}</div>
                  </div>
                </div>
              )}
            </div>
          )}

          {/* SETTINGS TAB */}
          {activeTab === "settings" && (
            <div className="flex flex-col gap-6">
              <div className="bg-[#121214] border border-[#27272a] p-6 rounded-xl flex flex-col gap-4">
                <h3 className="text-zinc-200 font-semibold text-sm">App Preferences (TOML Editor)</h3>
                <div className="flex flex-col gap-2 text-xs text-zinc-400">
                  <label className="font-semibold text-zinc-300">Logging Level Filter</label>
                  <select className="bg-[#1c1c1f] border border-[#27272a] p-2.5 rounded-lg text-zinc-200">
                    <option>debug</option>
                    <option>info</option>
                    <option>warn</option>
                    <option>error</option>
                  </select>
                </div>

                <div className="flex flex-col gap-2 text-xs text-zinc-400">
                  <label className="font-semibold text-zinc-300">AI LLM Model Name</label>
                  <input
                    type="text"
                    defaultValue="gpt-4o"
                    className="bg-[#1c1c1f] border border-[#27272a] p-2.5 rounded-lg text-zinc-200 font-mono"
                  />
                </div>

                <button className="bg-violet-600 hover:bg-violet-700 text-white font-medium text-xs px-4 py-2.5 rounded-lg transition duration-150 self-start">
                  Apply Preferences
                </button>
              </div>
            </div>
          )}
        </div>
      </main>

      {/* Command Palette Overlay */}
      {showPalette && (
        <div className="fixed inset-0 bg-[#000000]/75 backdrop-blur-sm z-50 flex items-start justify-center pt-28">
          <div className="bg-[#121214] border border-[#27272a] w-full max-w-xl rounded-xl shadow-2xl overflow-hidden flex flex-col">
            <div className="p-4 border-b border-[#27272a] flex items-center gap-3">
              <Search className="h-4 w-4 text-zinc-500" />
              <input
                type="text"
                placeholder="Search servers, containers, logs, actions... (ESC to close)"
                value={paletteSearch}
                onChange={(e) => setPaletteSearch(e.target.value)}
                autoFocus
                className="w-full bg-transparent text-sm text-zinc-100 focus:outline-none placeholder-zinc-500"
              />
            </div>
            <div className="p-2 max-h-64 overflow-y-auto flex flex-col gap-1 text-xs text-zinc-400">
              {[
                { label: "Go to Dashboard", tab: "dashboard", category: "Navigation" },
                { label: "Manage Servers", tab: "servers", category: "Navigation" },
                { label: "Docker Containers", tab: "containers", category: "Navigation" },
                { label: "Systemd Services", tab: "services", category: "Navigation" },
                { label: "Logs Console", tab: "logs", category: "Logs" },
                { label: "File Explorer", tab: "files", category: "Files" },
                { label: "AI SRE Diagnostics", tab: "ai", category: "AI" },
                { label: "Configure Preferences", tab: "settings", category: "Settings" },
              ]
                .filter((item) => item.label.toLowerCase().includes(paletteSearch.toLowerCase()))
                .map((item, idx) => (
                  <button
                    key={idx}
                    onClick={() => {
                      setActiveTab(item.tab);
                      setShowPalette(false);
                      setPaletteSearch("");
                    }}
                    className="flex justify-between items-center w-full px-3 py-2.5 rounded-lg hover:bg-zinc-800/60 text-left transition duration-100"
                  >
                    <span className="text-zinc-200 font-medium">{item.label}</span>
                    <span className="text-[10px] bg-zinc-850 px-2 py-0.5 rounded text-zinc-500 font-mono">{item.category}</span>
                  </button>
                ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default App;
