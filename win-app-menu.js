const { Menu, shell } = require('electron');
const { t, showAbout, feedbackURL, INTRO_URL } = require('./mac-app-menu');

/**
 * Windows 向けアプリケーションメニュー。
 * Mac 版と同じ意図: について / フィードバック / 更新確認 / Web サイト、編集ショートカット、終了。
 */
function setupWindowsApplicationMenu({ getMainWindow, checkForUpdates }) {
    if (process.platform !== 'win32') return;

    const template = [{
        label: t('file'),
        submenu: [{
            label: t('quit'),
            role: 'quit'
        }]
    }, {
        label: t('edit'),
        submenu: [
            { label: t('undo'), role: 'undo' },
            { label: t('redo'), role: 'redo' },
            { type: 'separator' },
            { label: t('cut'), role: 'cut' },
            { label: t('copy'), role: 'copy' },
            { label: t('paste'), role: 'paste' },
            { label: t('selectAll'), role: 'selectAll' }
        ]
    }, {
        label: t('help'),
        submenu: [
            {
                label: t('about'),
                click: () => showAbout(getMainWindow(), checkForUpdates)
            },
            {
                label: t('feedback'),
                click: () => { shell.openExternal(feedbackURL()); }
            },
            {
                label: t('checkUpdates'),
                click: () => { checkForUpdates(); }
            },
            { type: 'separator' },
            {
                label: t('intro'),
                click: () => { shell.openExternal(INTRO_URL); }
            }
        ]
    }];

    Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

module.exports = {
    setupWindowsApplicationMenu
};
