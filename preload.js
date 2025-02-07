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
        selectFolder: () => ipcRenderer.invoke('select-folder'),
        selectSteFile: () => ipcRenderer.invoke('select-ste-file'),
        generateSftpJson: (config) => ipcRenderer.invoke('generate-sftp-json', config),
        openInEditor: (folderPath, editor) => ipcRenderer.invoke('openInEditor', folderPath, editor)
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