const fs = require('node:fs');
const path = require('node:path');
const { execSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const dist = path.join(root, 'dist');
const appName = 'ARES';

function clean() {
  if (fs.existsSync(dist)) fs.rmSync(dist, { recursive: true });
  fs.mkdirSync(dist, { recursive: true });
}

function run(cmd) {
  console.log('[pkg]', cmd);
  execSync(cmd, { cwd: root, stdio: 'inherit', shell: 'cmd.exe' });
}

function installerScript() {
  return `
[Setup]
AppId={{A8D7B4A2-6F1C-4E7A-93D4-E9C3F2B1A7D0}}
AppName=ARES
AppVersion=0.1.0
DefaultDirName={localappdata}\\${appName}
DisableProgramGroupPage=yes
OutputDir=${dist.replace(/\\/g, '/')}
OutputBaseFilename=${appName}-Setup
Compression=lzma
SolidCompression=yes

[Icons]
Name: "{autoprograms}\\ARES"; Filename: "{app}\\${appName}.exe"
Name: "{autodesktop}\\ARES"; Filename: "{app}\\${appName}.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\\${appName}.exe"; Description: "Launch ARES"; Flags: nowait postinstall skipifsilent
`;
}

try {
  clean();
  const issPath = path.join(root, 'installer.iss');
  const buildDir = path.join(root, 'inno');
  if (!fs.existsSync(buildDir)) fs.mkdirSync(buildDir, { recursive: true });
  fs.writeFileSync(issPath, installerScript());
  console.log('[pkg] wrote installer.iss');

  // Copy app files to inno/ for packaging
  const copy = (src, dest) => {
    if (fs.existsSync(dest)) fs.rmSync(dest, { recursive: true });
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    if (fs.statSync(src).isDirectory()) {
      fs.cpSync(src, dest, { recursive: true });
    } else {
      fs.cpFileSync ? fs.cpFileSync(src, dest) : fs.copyFileSync(src, dest);
    }
  };
  copy(path.join(root, 'src'), path.join(buildDir, 'src'));
  copy(path.join(root, 'assets'), path.join(buildDir, 'assets'));
  copy(path.join(root, 'package.json'), path.join(buildDir, 'package.json'));

  // Create stub launcher batch so Inno has an exe target
  const bat = path.join(buildDir, 'launch.bat');
  fs.writeFileSync(bat, '@echo off\r\n"' + path.join(process.env.ProgramFiles || 'C:\\Program Files', 'nodejs', 'node.exe') + '" "' + path.join(root, 'src', 'main.js') + '"\r\n');
  console.log('[pkg] wrote launch.bat');

  // Compile installer
  const iscc = path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Inno Setup 6', 'ISCC.exe');
  if (!fs.existsSync(iscc)) {
    const iscc5 = path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Inno Setup 5', 'ISCC.exe');
    if (fs.existsSync(iscc5)) {
      run(`"${iscc5}" "${issPath}"`);
    } else {
      console.log('[pkg] Inno Setup not found, installer script prepared at', issPath);
    }
  } else {
    run(`"${iscc}" "${issPath}"`);
  }

  console.log('[pkg] done');
} catch (e) {
  console.error('[pkg] failed', e);
  process.exit(1);
}
