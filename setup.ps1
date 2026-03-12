# Run this in PowerShell as Admin
# It creates the entire boi-ts-tuff project on your Desktop

$base = "$env:USERPROFILE\Desktop\synapsez-ui"
New-Item -ItemType Directory -Force -Path "$base\src" | Out-Null
New-Item -ItemType Directory -Force -Path "$base\dist" | Out-Null

Write-Host "Creating files..." -ForegroundColor Cyan

# ── package.json ─────────────────────────────────────────────────────────────
@'
{
  "name": "synapsez-ui",
  "version": "1.0.0",
  "description": "boi ts tuff - Custom UI for Synapse Z",
  "main": "dist/main.js",
  "scripts": {
    "build": "tsc",
    "start": "npm run build && electron .",
    "pack": "npm run build && electron-builder --win --x64",
    "dev": "tsc && electron ."
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "electron": "^28.0.0",
    "electron-builder": "^24.0.0",
    "typescript": "^5.0.0"
  },
  "build": {
    "appId": "com.boitstuff.ui",
    "productName": "boi ts tuff",
    "win": {
      "target": "nsis"
    },
    "nsis": {
      "oneClick": false,
      "allowToChangeInstallationDirectory": true
    },
    "files": [
      "dist/**/*",
      "src/index.html"
    ]
  }
}
'@ | Set-Content "$base\package.json" -Encoding UTF8

# ── tsconfig.json ─────────────────────────────────────────────────────────────
@'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": false,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*.ts"],
  "exclude": ["node_modules"]
}
'@ | Set-Content "$base\tsconfig.json" -Encoding UTF8

# ── src/main.ts ───────────────────────────────────────────────────────────────
@'
import { app, BrowserWindow, ipcMain, dialog } from "electron";
import * as path from "path";
import * as fs from "fs";
import * as os from "os";

let mainWindow: BrowserWindow | null = null;

const SYNZ_BASE  = path.join(os.homedir(), "AppData", "Local", "Synapse Z");
const SYNZ_BIN   = path.join(SYNZ_BASE, "bin");
const SYNZ_SCHED = path.join(SYNZ_BIN, "scheduler");
const SYNZ_AUTH  = path.join(os.homedir(), "AppData", "Local", "auth_v2.syn");

let latestError = "";

function synapseExecute(script: string, pid?: number): number {
  if (!fs.existsSync(SYNZ_BIN)) {
    latestError = "Bin folder not found at: " + SYNZ_BIN;
    return 1;
  }
  if (!fs.existsSync(SYNZ_SCHED)) {
    latestError = "Scheduler folder not found at: " + SYNZ_SCHED;
    return 2;
  }
  const randomName = Array.from({ length: 10 }, () =>
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[Math.floor(Math.random() * 36)]
  ).join("") + ".lua";
  const fileName = pid ? `PID${pid}_${randomName}` : randomName;
  const filePath = path.join(SYNZ_SCHED, fileName);
  try {
    fs.writeFileSync(filePath, script + "@@FileFullyWritten@@", "utf8");
    latestError = "";
    return 0;
  } catch (e: any) {
    latestError = e.message;
    return 3;
  }
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 960, height: 680, minWidth: 800, minHeight: 560,
    frame: false, backgroundColor: "#080808",
    webPreferences: {
      nodeIntegration: false, contextIsolation: true,
      preload: path.join(__dirname, "preload.js"),
    },
    show: false,
  });
  mainWindow.loadFile(path.join(__dirname, "..", "src", "index.html"));
  mainWindow.once("ready-to-show", () => mainWindow!.show());
  mainWindow.on("closed", () => { mainWindow = null; });
}

app.whenReady().then(createWindow);
app.on("window-all-closed", () => app.quit());

ipcMain.on("window-minimize", () => mainWindow?.minimize());
ipcMain.on("window-maximize", () => {
  if (mainWindow?.isMaximized()) mainWindow.unmaximize();
  else mainWindow?.maximize();
});
ipcMain.on("window-close", () => mainWindow?.close());

ipcMain.handle("execute-script", (_e, script: string, pid?: number) => {
  const code = synapseExecute(script, pid);
  const msgs: Record<number, string> = {
    0: "Script queued successfully",
    1: "Bin folder not found — is Synapse Z installed?",
    2: "Scheduler folder not found — is Synapse Z running?",
    3: "No write access to scheduler folder",
  };
  return { code, message: msgs[code] ?? "Unknown error", error: latestError };
});

ipcMain.handle("get-error", () => latestError || "No error.");

ipcMain.handle("get-synz-status", () => ({
  baseExists: fs.existsSync(SYNZ_BASE),
  binExists:  fs.existsSync(SYNZ_BIN),
  schedExists: fs.existsSync(SYNZ_SCHED),
  authExists: fs.existsSync(SYNZ_AUTH),
  basePath:   SYNZ_BASE,
}));

ipcMain.handle("open-script-file", async () => {
  const r = await dialog.showOpenDialog(mainWindow!, {
    title: "Open Script",
    filters: [{ name: "Lua Scripts", extensions: ["lua", "txt"] }, { name: "All Files", extensions: ["*"] }],
    properties: ["openFile"],
  });
  if (r.canceled || !r.filePaths.length) return null;
  return fs.readFileSync(r.filePaths[0], "utf8");
});

ipcMain.handle("save-script-file", async (_e, content: string) => {
  const r = await dialog.showSaveDialog(mainWindow!, {
    title: "Save Script",
    filters: [{ name: "Lua Scripts", extensions: ["lua", "txt"] }],
    defaultPath: "script.lua",
  });
  if (r.canceled || !r.filePath) return false;
  fs.writeFileSync(r.filePath, content, "utf8");
  return true;
});
'@ | Set-Content "$base\src\main.ts" -Encoding UTF8

# ── src/preload.ts ────────────────────────────────────────────────────────────
@'
const { contextBridge, ipcRenderer } = require("electron");
contextBridge.exposeInMainWorld("synapseAPI", {
  execute:       (script: string, pid?: number) => ipcRenderer.invoke("execute-script", script, pid),
  getError:      () => ipcRenderer.invoke("get-error"),
  getSynzStatus: () => ipcRenderer.invoke("get-synz-status"),
  openFile:      () => ipcRenderer.invoke("open-script-file"),
  saveFile:      (content: string) => ipcRenderer.invoke("save-script-file", content),
  minimize:      () => ipcRenderer.send("window-minimize"),
  maximize:      () => ipcRenderer.send("window-maximize"),
  close:         () => ipcRenderer.send("window-close"),
});
'@ | Set-Content "$base\src\preload.ts" -Encoding UTF8

# ── src/index.html ────────────────────────────────────────────────────────────
# We write this via a temp file to avoid quoting issues with the large HTML
$html = Get-Content "$PSScriptRoot\src\index.html" -Raw -ErrorAction SilentlyContinue
if (-not $html) {
    Write-Host "WARNING: Could not find src\index.html next to this script." -ForegroundColor Yellow
    Write-Host "Make sure setup.ps1 and src\index.html are in the same folder, OR" -ForegroundColor Yellow
    Write-Host "manually copy index.html into $base\src\" -ForegroundColor Yellow
} else {
    $html | Set-Content "$base\src\index.html" -Encoding UTF8
    Write-Host "index.html copied." -ForegroundColor Green
}

Write-Host ""
Write-Host "Done! Now run:" -ForegroundColor Green
Write-Host "  cd $base" -ForegroundColor White
Write-Host "  npm install" -ForegroundColor White
Write-Host "  npm run dev" -ForegroundColor White
'@
