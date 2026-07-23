const { contextBridge, ipcRenderer } = require('electron');

console.log('Preload script starting...');

process.on('uncaughtException', (error) => {
    console.error('Preload uncaught exception:', error);
});

process.on('unhandledRejection', (reason, promise) => {
    console.error('Preload unhandled rejection:', reason);
});

const listeners = new Set();

try {
    console.log('Setting up context bridge...');
    
    contextBridge.exposeInMainWorld('electronAPI', {
        selectSteFile: () => ipcRenderer.invoke('select-ste-file'),
        selectDirectory: () => ipcRenderer.invoke('select-directory'),
        generateSftpJson: (config) => ipcRenderer.invoke('generate-sftp-json', config),
        openInEditor: (folderPath, checkOnly) => ipcRenderer.invoke('openInEditor', folderPath, checkOnly),
        getSystemLocale: () => ipcRenderer.invoke('get-system-locale'),
        onSteFileOpened: (callback) => {
            const handler = (_event, payload) => callback(payload);
            ipcRenderer.on('ste-file-opened', handler);
            return () => ipcRenderer.removeListener('ste-file-opened', handler);
        },
        takePendingSteOpen: () => ipcRenderer.invoke('take-pending-ste-open')
    });

    contextBridge.exposeInMainWorld('ipcRenderer', {
        invoke: (channel, ...args) => ipcRenderer.invoke(channel, ...args)
    });

    console.log('Context bridge setup complete with electronAPI object');
} catch (error) {
    console.error('Error in preload script:', error);
}

window.addEventListener('unload', () => {
    listeners.forEach(cleanup => cleanup());
    listeners.clear();
}); 