const { app, BrowserWindow, ipcMain, dialog, clipboard, nativeImage } = require('electron');
const { autoUpdater } = require('electron-updater');
const path = require('path');
const fs = require('fs');
const { promisify } = require('util');
const { exec, spawn } = require('child_process');
const xml2js = require('xml2js');
const { shell } = require('electron');

console.log('Application starting...');
console.log('Current directory:', __dirname);
console.log('Resource path:', process.resourcesPath);

let mainWindow = null;
let defaultBasePath;
let pendingSteOpenPayload = null;
let pendingOpenFilePath = null;

const STE_PROG_ID = 'jp.tomippe.sftpgen.ste';

// ウィンドウの設定を定数として定義
const WINDOW_CONFIG = {
    width: 500,
    height: 550,
    webPreferences: {
        nodeIntegration: false,
        contextIsolation: true,
        sandbox: false,
        enableRemoteModule: false,
        preload: path.join(__dirname, 'preload.js')
    },
    autoHideMenuBar: true,
    resizable: false,
    maximizable: false,
    fullscreenable: false,
    backgroundColor: '#F5F5F5'
};

function getAppPath() {
    if (app.isPackaged) {
        return path.join(process.resourcesPath, 'app');
    }
    return __dirname;
}

function createWindow() {
    console.log('Creating window...');
    if (mainWindow) {
        console.log('Window already exists');
        return;
    }

    defaultBasePath = app.getPath('home');
    console.log('Default base path:', defaultBasePath);

    try {
        mainWindow = new BrowserWindow({
            width: 490,
            height: 560,
            resizable: false,
            show: false,
            autoHideMenuBar: true,
            webPreferences: {
                nodeIntegration: false,
                contextIsolation: true,
                preload: path.join(__dirname, 'preload.js')
            }
        });
        console.log('Window created successfully');

        const indexPath = path.join(getAppPath(), 'index.html');
        console.log('Loading index.html from:', indexPath);
        
        mainWindow.loadFile(indexPath).catch(error => {
            console.error('Error loading index.html:', error);
        });

        // 言語ファイルの読み込みが完了してからウィンドウを表示
        mainWindow.webContents.on('did-finish-load', () => {
            mainWindow.show();
        });

        mainWindow.on('closed', () => {
            mainWindow = null;
            app.quit();
        });
    } catch (error) {
        console.error('Error creating window:', error);
    }
}

function getStePathFromArgv(argv) {
    return argv.slice(1).find((arg) => {
        if (arg.startsWith('-')) return false;
        return arg.toLowerCase().endsWith('.ste');
    });
}

function deliverSteOpenToRenderer(payload) {
    pendingSteOpenPayload = payload;
    if (mainWindow && !mainWindow.isDestroyed() && !mainWindow.webContents.isLoading()) {
        mainWindow.webContents.send('ste-file-opened', payload);
        mainWindow.show();
        mainWindow.focus();
    }
}

async function openSteAtPath(filePath) {
    if (!filePath || !filePath.toLowerCase().endsWith('.ste')) return;
    try {
        const config = await parseSteFile(filePath);
        deliverSteOpenToRenderer({ success: true, config });
    } catch (error) {
        console.error('Failed to open STE file:', error);
        deliverSteOpenToRenderer({ success: false, error: error.message });
    }
}

function registerWindowsSteAssociation() {
    if (process.platform !== 'win32' || !app.isPackaged) return;

    const exePath = process.execPath;
    const exeName = path.basename(exePath);
    const openCommand = `"${exePath}" "%1"`;

    const regAdd = (key, parts) => {
        spawn('reg', ['add', key, '/f', ...parts], { windowsHide: true, stdio: 'ignore' });
    };

    regAdd(`HKCU\\Software\\Classes\\Applications\\${exeName}\\shell\\open\\command`, ['/ve', '/d', openCommand]);
    regAdd(`HKCU\\Software\\Classes\\Applications\\${exeName}\\SupportedTypes`, ['/v', '.ste', '/t', 'REG_SZ', '/d', '']);
    regAdd(`HKCU\\Software\\Classes\\${STE_PROG_ID}`, ['/ve', '/d', 'Dreamweaver Site Settings']);
    regAdd(`HKCU\\Software\\Classes\\${STE_PROG_ID}\\DefaultIcon`, ['/ve', '/d', `"${exePath}",0`]);
    regAdd(`HKCU\\Software\\Classes\\${STE_PROG_ID}\\shell\\open\\command`, ['/ve', '/d', openCommand]);
    regAdd('HKCU\\Software\\Classes\\.ste\\OpenWithProgids', ['/v', STE_PROG_ID, '/t', 'REG_NONE']);
    regAdd('HKCU\\Software\\Classes\\.ste\\OpenWithList', ['/v', exeName, '/t', 'REG_SZ', '/d', '']);
}

const gotSingleInstanceLock = app.requestSingleInstanceLock();
if (!gotSingleInstanceLock) {
    app.quit();
} else {
    app.on('second-instance', (_event, argv) => {
        const stePath = getStePathFromArgv(argv);
        if (stePath) {
            openSteAtPath(stePath);
        }
        if (mainWindow) {
            mainWindow.show();
            mainWindow.focus();
        }
    });
}

app.on('open-file', (event, filePath) => {
    event.preventDefault();
    if (app.isReady()) {
        openSteAtPath(filePath);
    } else {
        pendingOpenFilePath = filePath;
    }
});

app.whenReady().then(() => {
    registerWindowsSteAssociation();
    createWindow();

    if (pendingOpenFilePath) {
        openSteAtPath(pendingOpenFilePath);
        pendingOpenFilePath = null;
    }

    const steFromArgv = getStePathFromArgv(process.argv);
    if (steFromArgv) {
        openSteAtPath(steFromArgv);
    }

    autoUpdater.checkForUpdatesAndNotify();

    app.on('activate', () => {
        if (BrowserWindow.getAllWindows().length === 0) {
            createWindow();
        }
    });
});

app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') {
        app.quit();
    }
});

// IPCハンドラーの最適化
ipcMain.handle('select-file', async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
        properties: ['openFile', 'openDirectory']
    });
    return result.filePaths[0];
});

ipcMain.handle('select-base-path', async () => {
    try {
        const result = await dialog.showOpenDialog(mainWindow, {
            properties: ['openDirectory'],
            defaultPath: defaultBasePath
        });
        return result.filePaths[0] || null;
    } catch (error) {
        console.error('Base path selection error:', error);
        return null;
    }
});

ipcMain.handle('handle-path', async (event, filePath, basePath) => {
    try {
        const stats = await fs.promises.stat(filePath);
        return {
            success: true,
            path: filePath,
            basePath: basePath || defaultBasePath,
            isDirectory: stats.isDirectory()
        };
    } catch (error) {
        console.error('Path handling error:', error);
        return {
            success: false,
            error: error.message
        };
    }
});

ipcMain.handle('write-to-clipboard', async (event, text) => {
    try {
        if (typeof text !== 'string') throw new Error('Invalid text format');
        clipboard.writeText(text);
        return { success: true };
    } catch (error) {
        console.error('Clipboard error:', error);
        return { success: false, error: error.message };
    }
});

// フォルダ選択ダイアログを開く
ipcMain.handle('select-directory', async (event, type) => {
    const result = await dialog.showOpenDialog(mainWindow, {
        properties: ['openDirectory', 'createDirectory']
    });
    return result.filePaths[0];
});

function decodePassword(hash) {
    if (!hash || typeof hash !== 'string') return '';
    const normalized = hash.trim();
    let pass = '';
    for (let i = 0; i < normalized.length; i += 2) {
        const hex = normalized.substr(i, 2);
        if (hex.length < 2) break;
        pass += String.fromCharCode(parseInt(hex, 16) - (i / 2));
    }
    return pass;
}

function decodeDreamweaverPath(encoded) {
    if (!encoded) return '';
    let s = String(encoded).trim();
    for (let n = 0; n < 3; n++) {
        const withSlashes = s.replace(/%5[Cc]/g, '\\');
        try {
            const decoded = decodeURIComponent(withSlashes.replace(/\+/g, '%20'));
            if (decoded === s) break;
            s = decoded;
        } catch {
            s = withSlashes.replace(/%5[Cc]/g, '\\');
            break;
        }
    }
    return s.replace(/%5[Cc]/g, '\\');
}

function normalizeSiteFolderPath(decodedPath) {
    const sep = process.platform === 'win32' ? '\\' : '/';
    let localroot = decodedPath
        .replace(/%5[Cc]/g, sep)
        .replace(/[\/\\]+/g, sep);
    localroot = localroot.replace(/html[\/\\]*$/i, '');
    return localroot.replace(new RegExp(`${sep.replace('\\', '\\\\')}+$`), '');
}

function getServerAttributes(site) {
    const localinfo = site.localinfo && site.localinfo[0] && site.localinfo[0].$;
    const serverlist = site.serverlist && site.serverlist[0];
    if (!serverlist || !serverlist.server) return {};

    const servers = Array.isArray(serverlist.server) ? serverlist.server : [serverlist.server];
    const cur = localinfo && localinfo.curserver;

    if (cur) {
        const matched = servers.find((entry) => {
            const attrs = entry.$ || {};
            const name = attrs.name || attrs.servername || '';
            if (name === cur) return true;
            try {
                return decodeURIComponent(name) === cur;
            } catch {
                return false;
            }
        });
        if (matched && matched.$) return matched.$;
    }

    return (servers[0] && servers[0].$) || {};
}

function readServerPassword(serverinfo) {
    const raw = serverinfo.pw || serverinfo.Pw || serverinfo.password || '';
    return decodePassword(String(raw).trim());
}

async function parseSteFile(filePath) {
    try {
        console.log('Reading STE file:', filePath);
        const fileContent = fs.readFileSync(filePath, 'utf-8');
        const parser = new xml2js.Parser();
        
        const result = await parser.parseStringPromise(fileContent);
        const site = result.site;
        const localinfo = site.localinfo[0].$;
        const serverinfo = getServerAttributes(site);

        const pathRaw =
            localinfo.localroot ||
            localinfo.csspreprocessorshtmlpathforcompass ||
            '';
        const localroot = normalizeSiteFolderPath(decodeDreamweaverPath(pathRaw));
        const password = readServerPassword(serverinfo);

        const config = {
            folderPath: localroot,
            host: serverinfo.host || '',
            username: serverinfo.user || '',
            password: password,
            remotePath: serverinfo.remoteroot || ''
        };

        return config;
    } catch (error) {
        console.error('STE file parsing error:', error);
        throw new Error('STEファイルの解析に失敗しました: ' + error.message);
    }
}

// STEファイル選択ハンドラー
ipcMain.handle('select-ste-file', async () => {
    try {
        console.log('Opening STE file dialog');
        const result = await dialog.showOpenDialog(mainWindow, {
            properties: ['openFile'],
            filters: [
                { name: 'Dreamweaver Site Settings', extensions: ['ste'] }
            ]
        });
        
        console.log('Dialog result:', result);
        
        if (result.canceled || result.filePaths.length === 0) {
            console.log('File selection cancelled');
            return { success: false };
        }

        const config = await parseSteFile(result.filePaths[0]);
        return { success: true, config };
    } catch (error) {
        console.error('STE file selection error:', error);
        return { success: false, error: error.message };
    }
});

// エディタ名を取得する関数
async function getEditorName() {
    if (process.platform === 'darwin') {
        const cursorPath = '/Applications/Cursor.app';
        const vscodePath = '/Applications/Visual Studio Code.app';

        if (fs.existsSync(cursorPath)) {
            return 'Cursor';
        } else if (fs.existsSync(vscodePath)) {
            return 'VSCode';
        }
    } else if (process.platform === 'win32') {
        const cursorPath = path.join(process.env.LOCALAPPDATA, 'Programs', 'Cursor', 'Cursor.exe');
        const vscodePath = path.join(process.env.LOCALAPPDATA, 'Programs', 'Microsoft VS Code', 'Code.exe');
        const vscodePath2 = path.join('C:', 'Program Files', 'Microsoft VS Code', 'Code.exe');

        if (fs.existsSync(cursorPath)) {
            return 'Cursor';
        } else if (fs.existsSync(vscodePath) || fs.existsSync(vscodePath2)) {
            return 'VSCode';
        }
    }
    
    // エラーメッセージは renderer 側で多言語化されるため、ここではエラーコードを返す
    throw new Error('EDITOR_NOT_FOUND');
}

// フォルダをエディタで開く関数
async function openInEditor(folderPath, checkOnly = false) {
    try {
        if (checkOnly) {
            return await getEditorName();
        }

        if (process.platform === 'darwin') {
            const cursorPath = '/Applications/Cursor.app';
            const vscodePath = '/Applications/Visual Studio Code.app';

            if (fs.existsSync(cursorPath)) {
                exec(`open -a "${cursorPath}" "${folderPath}"`);
                return 'Cursor';
            } else if (fs.existsSync(vscodePath)) {
                exec(`open -a "${vscodePath}" "${folderPath}"`);
                return 'VSCode';
            }
        } else if (process.platform === 'win32') {
            const cursorPath = path.join(process.env.LOCALAPPDATA, 'Programs', 'Cursor', 'Cursor.exe');
            const vscodePath = path.join(process.env.LOCALAPPDATA, 'Programs', 'Microsoft VS Code', 'Code.exe');
            const vscodePath2 = path.join('C:', 'Program Files', 'Microsoft VS Code', 'Code.exe');

            if (fs.existsSync(cursorPath)) {
                exec(`"${cursorPath}" "${folderPath}"`);
                return 'Cursor';
            } else if (fs.existsSync(vscodePath)) {
                exec(`"${vscodePath}" "${folderPath}"`);
                return 'VSCode';
            } else if (fs.existsSync(vscodePath2)) {
                exec(`"${vscodePath2}" "${folderPath}"`);
                return 'VSCode';
            }
        }

        throw new Error('エディタがインストールされていません。');
    } catch (error) {
        console.error('エディタでフォルダを開く際にエラーが発生しました:', error);
        throw error;
    }
}

ipcMain.handle('openInEditor', async (event, folderPath, checkOnly = false) => {
    return await openInEditor(folderPath, checkOnly);
});

ipcMain.handle('generate-sftp-json', async (event, { folderPath, config }) => {
    const vscodePath = path.join(folderPath, '.vscode');
    const sftpJsonPath = path.join(vscodePath, 'sftp.json');

    if (!fs.existsSync(vscodePath)) {
        fs.mkdirSync(vscodePath);
    }

    const sftpConfig = {
        name: "My Server",
        host: config.host,
        protocol: "ftp",
        port: 21,
        passive: true,
        username: config.username,
        password: config.password,
        remotePath: config.remotePath,
        uploadOnSave: true,
        watcher: {
            files: "{**/*.css}",
            autoUpload: true,
            autoDelete: false
        },
        ignore: [
            "**/.vscode",
            "**/.git/**",
            "**/.DS_Store"
        ],
        syncOption: {
            delete: true
        }
    };

    fs.writeFileSync(sftpJsonPath, JSON.stringify(sftpConfig, null, 4));
    
    return true;
});

// システムロケールを取得するハンドラー
ipcMain.handle('get-system-locale', () => {
    return app.getLocale();
});

ipcMain.handle('take-pending-ste-open', () => {
    const payload = pendingSteOpenPayload;
    pendingSteOpenPayload = null;
    return payload;
}); 