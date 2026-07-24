const { app, BrowserWindow, ipcMain, dialog, clipboard } = require('electron');
const { autoUpdater } = require('electron-updater');
const path = require('path');
const fs = require('fs');
const { exec, spawn } = require('child_process');
const xml2js = require('xml2js');
const { shell } = require('electron');
const { setupApplicationMenu, closeAboutWindow, getAppsLogoPath, buildAboutDetail, t, INTRO_URL } = require('./mac-app-menu');
const { setupWindowsApplicationMenu } = require('./win-app-menu');

console.log('Application starting...');
console.log('Current directory:', __dirname);
console.log('Resource path:', process.resourcesPath);

let mainWindow = null;
let defaultBasePath;
let pendingSteOpenPayload = null;
let pendingOpenFilePath = null;
let manualUpdateCheck = false;

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
            autoHideMenuBar: process.platform !== 'win32',
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

function checkForUpdatesManual() {
    if (!app.isPackaged) {
        dialog.showMessageBox(mainWindow || undefined, {
            type: 'info',
            title: 'SFTP Generator',
            message: t('updateDevMode'),
            buttons: [t('ok')],
            defaultId: 0
        });
        return;
    }

    manualUpdateCheck = true;
    autoUpdater.checkForUpdates().catch((error) => {
        manualUpdateCheck = false;
        dialog.showErrorBox('SFTP Generator', t('updateError').replace('{error}', error.message));
    });
}

const UPDATE_FEED_URL = 'https://apps.tomippe.jp/sftp-gen/';

function setupAutoUpdaterFeedback() {
    if (app.isPackaged) {
        autoUpdater.setFeedURL({
            provider: 'generic',
            url: UPDATE_FEED_URL
        });
    }

    autoUpdater.autoDownload = true;
    autoUpdater.autoInstallOnAppQuit = true;

    autoUpdater.on('update-not-available', () => {
        if (!manualUpdateCheck) return;
        manualUpdateCheck = false;
        dialog.showMessageBox(mainWindow || undefined, {
            type: 'info',
            title: 'SFTP Generator',
            message: t('updateNotAvailable'),
            buttons: [t('ok')],
            defaultId: 0
        });
    });

    autoUpdater.on('update-available', (info) => {
        if (!manualUpdateCheck) return;
        manualUpdateCheck = false;
        dialog.showMessageBox(mainWindow || undefined, {
            type: 'info',
            title: 'SFTP Generator',
            message: t('updateAvailable').replace('{version}', info.version),
            buttons: [t('ok')],
            defaultId: 0
        });
    });

    autoUpdater.on('update-downloaded', () => {
        dialog.showMessageBox(mainWindow || undefined, {
            type: 'info',
            title: 'SFTP Generator',
            message: t('updateDownloaded'),
            buttons: [t('ok'), t('restartNow')],
            defaultId: 1
        }).then(({ response }) => {
            if (response === 1) {
                autoUpdater.quitAndInstall();
            }
        });
    });

    autoUpdater.on('error', (error) => {
        console.error('Auto-update error:', error);
        if (!manualUpdateCheck) return;
        manualUpdateCheck = false;
        dialog.showErrorBox('SFTP Generator', t('updateError').replace('{error}', error.message));
    });
}

app.whenReady().then(() => {
    registerWindowsSteAssociation();

    if (process.platform !== 'win32') {
        setupAutoUpdaterFeedback();
    }

    setupApplicationMenu({
        getMainWindow: () => mainWindow,
        checkForUpdates: () => checkForUpdatesManual()
    });
    setupWindowsApplicationMenu({
        getMainWindow: () => mainWindow
    });

    createWindow();

    if (pendingOpenFilePath) {
        openSteAtPath(pendingOpenFilePath);
        pendingOpenFilePath = null;
    }

    const steFromArgv = getStePathFromArgv(process.argv);
    if (steFromArgv) {
        openSteAtPath(steFromArgv);
    }

    if (process.platform !== 'win32') {
        autoUpdater.checkForUpdates().catch((error) => {
            console.error('Startup update check failed:', error);
        });
    }

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

let mainI18nCache = null;

function getMainI18n() {
    if (mainI18nCache) return mainI18nCache;
    const locale = app.getLocale();
    let lang = 'en';
    if (locale.startsWith('ja')) lang = 'ja';
    else if (locale.startsWith('zh')) lang = 'zh';
    const candidates = [
        path.join(__dirname, 'locales', `${lang}.json`),
        path.join(getAppPath(), 'locales', `${lang}.json`),
        path.join(__dirname, 'locales', 'en.json'),
        path.join(getAppPath(), 'locales', 'en.json')
    ];
    for (const filePath of candidates) {
        try {
            mainI18nCache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
            return mainI18nCache;
        } catch {
            // try next
        }
    }
    mainI18nCache = { generate: { dialogTitle: 'SFTP Generator' } };
    return mainI18nCache;
}

function showGenerateError(message) {
    const i18n = getMainI18n();
    dialog.showErrorBox(i18n.generate?.dialogTitle || 'SFTP Generator', message);
}

ipcMain.handle('generate-sftp-json', async (event, { folderPath, config }) => {
    const i18n = getMainI18n();
    const g = i18n.generate || {};

    const fail = (message) => {
        showGenerateError(message);
        return { success: false, error: message };
    };

    const folder = (folderPath || '').trim();
    if (!folder) {
        return fail(g.missingRequired || 'Required fields are missing.');
    }

    let stat;
    try {
        stat = fs.statSync(folder);
    } catch {
        return fail(g.invalidFolder || 'Invalid folder path.');
    }
    if (!stat.isDirectory()) {
        return fail(g.invalidFolder || 'Invalid folder path.');
    }

    if (!config?.host?.trim()) {
        return fail(g.missingHost || g.missingRequired || 'Hostname is required.');
    }
    if (!config?.username?.trim()) {
        return fail(g.missingUsername || g.missingRequired || 'Username is required.');
    }

    const vscodePath = path.join(folder, '.vscode');
    const sftpJsonPath = path.join(vscodePath, 'sftp.json');

    try {
        if (!fs.existsSync(vscodePath)) {
            fs.mkdirSync(vscodePath, { recursive: true });
        }

        const sftpConfig = {
            name: "My Server",
            host: config.host.trim(),
            protocol: "ftp",
            port: 21,
            passive: true,
            username: config.username.trim(),
            password: config.password || '',
            remotePath: config.remotePath || '',
            uploadOnSave: config.uploadOnSave !== false,
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

        fs.writeFileSync(sftpJsonPath, JSON.stringify(sftpConfig, null, 4), 'utf8');
        return { success: true, path: sftpJsonPath };
    } catch (error) {
        console.error('generate-sftp-json error:', error);
        const message = (g.writeFailed || g.generateError || 'Failed: {error}')
            .replace('{error}', error.message);
        return fail(message);
    }
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

ipcMain.handle('about-info', () => {
    const logoPath = getAppsLogoPath();
    const showUpdateCheck = process.platform !== 'win32';
    return {
        appName: 'SFTP Generator',
        detail: buildAboutDetail(),
        logoUrl: logoPath ? `file://${logoPath}` : '',
        showUpdateCheck,
        labels: {
            ok: t('ok'),
            checkUpdatesBtn: t('checkUpdatesBtn'),
            openIntro: t('openIntro')
        }
    };
});

ipcMain.handle('check-for-updates', () => {
    checkForUpdatesManual();
});

ipcMain.handle('open-intro-url', () => {
    shell.openExternal(INTRO_URL);
});

ipcMain.handle('close-about-window', () => {
    closeAboutWindow();
}); 