const { app, BrowserWindow, ipcMain, dialog, clipboard, nativeImage } = require('electron');
const path = require('path');
const fs = require('fs');
const { promisify } = require('util');
const { exec } = require('child_process');
const xml2js = require('xml2js');

console.log('Application starting...');
console.log('Current directory:', __dirname);
console.log('Resource path:', process.resourcesPath);

let mainWindow = null;
let defaultBasePath;

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
        mainWindow = new BrowserWindow(WINDOW_CONFIG);
        console.log('Window created successfully');

        const indexPath = path.join(getAppPath(), 'index.html');
        console.log('Loading index.html from:', indexPath);
        
        mainWindow.loadFile(indexPath).catch(error => {
            console.error('Error loading index.html:', error);
        });

        mainWindow.on('closed', () => {
            mainWindow = null;
            app.quit();
        });
    } catch (error) {
        console.error('Error creating window:', error);
    }
}

app.whenReady().then(() => {
    createWindow();
    
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

// STEファイルを解析する関数
async function parseSteFile(filePath) {
    try {
        console.log('Reading STE file:', filePath);
        const fileContent = fs.readFileSync(filePath, 'utf-8');
        const parser = new xml2js.Parser();
        
        const result = await parser.parseStringPromise(fileContent);
        console.log('Parsed XML:', result);

        const site = result.site;
        const localinfo = site.localinfo[0].$;
        const serverinfo = site.serverlist[0].server[0].$;

        // Macのパス形式を変換
        let localroot = localinfo.localroot
            .replace(/:/g, '/')
            .replace(/^(\d{3}-WEB)/, '/Volumes/$1');
        
        // 末尾のスラッシュを削除
        if (localroot.endsWith('/')) {
            localroot = localroot.slice(0, -1);
        }

        const config = {
            folderPath: localroot,
            host: serverinfo.host || '',
            username: serverinfo.user || '',
            remotePath: serverinfo.remoteroot || ''
        };

        console.log('Parsed config:', config);
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
    const cursorPath = '/Applications/Cursor.app';
    const vscodePath = '/Applications/Visual Studio Code.app';

    if (fs.existsSync(cursorPath)) {
        return 'Cursor';
    } else if (fs.existsSync(vscodePath)) {
        return 'VSCode';
    } else {
        throw new Error('エディタがインストールされていません。');
    }
}

// フォルダをエディタで開く関数
async function openInEditor(folderPath, checkOnly = false) {
    try {
        const cursorPath = '/Applications/Cursor.app';
        const vscodePath = '/Applications/Visual Studio Code.app';

        if (checkOnly) {
            return await getEditorName();
        }

        if (fs.existsSync(cursorPath)) {
            exec(`open -a "${cursorPath}" "${folderPath}"`);
            return 'Cursor';
        } else if (fs.existsSync(vscodePath)) {
            exec(`open -a "${vscodePath}" "${folderPath}"`);
            return 'VSCode';
        } else {
            throw new Error('エディタがインストールされていません。');
        }
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