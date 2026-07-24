const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('aboutAPI', {
    getInfo: () => ipcRenderer.invoke('about-info'),
    checkUpdates: () => ipcRenderer.invoke('check-for-updates'),
    openIntro: () => ipcRenderer.invoke('open-intro-url'),
    close: () => ipcRenderer.invoke('close-about-window')
});
