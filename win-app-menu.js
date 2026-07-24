const { Menu, shell } = require('electron');
const { t, showAbout, feedbackURL, INTRO_URL } = require('./mac-app-menu');

/**
 * Windows 向けアプリケーションメニュー（Store 配布 — 更新確認なし）。
 */
function setupWindowsApplicationMenu({ getMainWindow }) {
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
                click: () => showAbout(getMainWindow())
            },
            {
                label: t('feedback'),
                click: () => { shell.openExternal(feedbackURL()); }
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
