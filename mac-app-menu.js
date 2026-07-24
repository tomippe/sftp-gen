const { app, Menu, dialog, shell } = require('electron');
const os = require('os');

const INTRO_URL = 'https://apps.tomippe.jp/sftp-gen/';
const FEEDBACK_URLS = {
    ja: 'https://airtable.com/appIpAuwoVRCxzjcr/shrJql8sZUaekKD6Y',
    en: 'https://airtable.com/appIpAuwoVRCxzjcr/shrWhPOixBEspTNwS',
    'zh-Hans': 'https://airtable.com/appIpAuwoVRCxzjcr/shrYSDAi2CVNPkCCs'
};

const MENU_LABELS = {
    ja: {
        about: 'SFTP Generator について…',
        feedback: 'フィードバックを送る…',
        checkUpdates: 'アップデートを確認…',
        intro: 'SFTP Generator Webサイト',
        help: 'ヘルプ',
        file: 'ファイル',
        ok: 'OK',
        checkUpdatesBtn: 'アップデートを確認',
        openIntro: 'Webサイトを開く',
        services: 'サービス',
        hide: 'SFTP Generator を隠す',
        hideOthers: 'ほかを隠す',
        unhide: 'すべてを表示',
        quit: 'SFTP Generator を終了',
        edit: '編集',
        undo: '元に戻す',
        redo: 'やり直す',
        cut: '切り取り',
        copy: 'コピー',
        paste: 'ペースト',
        selectAll: 'すべてを選択',
        versionLine: 'バージョン {version}',
        buildLine: 'ビルド {build}',
        copyright: 'Copyright © tomippe. All rights reserved.'
    },
    en: {
        about: 'About SFTP Generator',
        feedback: 'Send Feedback…',
        checkUpdates: 'Check for Updates…',
        intro: 'SFTP Generator Website',
        help: 'Help',
        file: 'File',
        ok: 'OK',
        checkUpdatesBtn: 'Check for Updates',
        openIntro: 'Open Website',
        services: 'Services',
        hide: 'Hide SFTP Generator',
        hideOthers: 'Hide Others',
        unhide: 'Show All',
        quit: 'Quit SFTP Generator',
        edit: 'Edit',
        undo: 'Undo',
        redo: 'Redo',
        cut: 'Cut',
        copy: 'Copy',
        paste: 'Paste',
        selectAll: 'Select All',
        versionLine: 'Version {version}',
        buildLine: 'Build {build}',
        copyright: 'Copyright © tomippe. All rights reserved.'
    },
    'zh-Hans': {
        about: '关于 SFTP Generator',
        feedback: '发送反馈…',
        checkUpdates: '检查更新…',
        intro: 'SFTP Generator 网站',
        help: '帮助',
        file: '文件',
        ok: 'OK',
        checkUpdatesBtn: '检查更新',
        openIntro: '打开网站',
        services: '服务',
        hide: '隐藏 SFTP Generator',
        hideOthers: '隐藏其他',
        unhide: '显示全部',
        quit: '退出 SFTP Generator',
        edit: '编辑',
        undo: '撤销',
        redo: '重做',
        cut: '剪切',
        copy: '拷贝',
        paste: '粘贴',
        selectAll: '全选',
        versionLine: '版本 {version}',
        buildLine: '构建 {build}',
        copyright: 'Copyright © tomippe. All rights reserved.'
    }
};

function menuLocale() {
    const locale = app.getLocale();
    if (MENU_LABELS[locale]) return locale;
    const lang = locale.split('-')[0];
    if (lang === 'zh') return 'zh-Hans';
    if (lang === 'ja') return 'ja';
    return 'en';
}

function t(key) {
    const labels = MENU_LABELS[menuLocale()] || MENU_LABELS.en;
    return labels[key] || MENU_LABELS.en[key];
}

function macOSDescription() {
    const release = os.release().split('.').map((n) => parseInt(n, 10));
    const version = `${release[0]}.${release[1]}.${release[2] || 0}`;
    try {
        const build = require('child_process')
            .execSync('sw_vers -buildVersion', { encoding: 'utf8' })
            .trim();
        return build ? `macOS ${version} (${build})` : `macOS ${version}`;
    } catch {
        return `macOS ${version}`;
    }
}

function windowsDescription() {
    const release = os.release();
    const arch = process.arch;
    const build = process.getSystemVersion?.() || release;
    return `Windows ${build} (${arch})`;
}

function platformDescription() {
    if (process.platform === 'darwin') return macOSDescription();
    if (process.platform === 'win32') return windowsDescription();
    return `${process.platform} ${os.release()} (${process.arch})`;
}

function feedbackURL() {
    const locale = menuLocale();
    const base = FEEDBACK_URLS[locale] || FEEDBACK_URLS.en;
    const params = new URLSearchParams({
        'prefill_App': 'SFTP Generator',
        'prefill_Version': app.getVersion(),
        'prefill_OS': platformDescription()
    });
    return `${base}?${params.toString()}`;
}

function showAbout(mainWindow, checkForUpdates) {
    const version = app.getVersion();
    const build = app.getBuild?.() || process.env.npm_package_version || version;
    const detail = [
        t('versionLine').replace('{version}', version),
        build !== version ? t('buildLine').replace('{build}', build) : null,
        '',
        t('copyright')
    ].filter(Boolean).join('\n');

    dialog.showMessageBox(mainWindow || undefined, {
        type: 'info',
        title: 'SFTP Generator',
        message: 'SFTP Generator',
        detail,
        buttons: [t('ok'), t('checkUpdatesBtn'), t('openIntro')],
        defaultId: 0,
        cancelId: 0,
        noLink: true
    }).then(({ response }) => {
        if (response === 1) checkForUpdates();
        if (response === 2) shell.openExternal(INTRO_URL);
    }).catch(() => {});
}

function setupApplicationMenu({ getMainWindow, checkForUpdates }) {
    if (process.platform !== 'darwin') return;

    const template = [{
        label: app.name,
        submenu: [
            {
                label: t('about'),
                click: () => showAbout(getMainWindow(), checkForUpdates)
            },
            { type: 'separator' },
            {
                label: t('feedback'),
                click: () => { shell.openExternal(feedbackURL()); }
            },
            {
                label: t('checkUpdates'),
                click: () => { checkForUpdates(); }
            },
            { type: 'separator' },
            { label: t('services'), role: 'services' },
            { type: 'separator' },
            { label: t('hide'), role: 'hide' },
            { label: t('hideOthers'), role: 'hideOthers' },
            { label: t('unhide'), role: 'unhide' },
            { type: 'separator' },
            { label: t('quit'), role: 'quit' }
        ]
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
        submenu: [{
            label: t('intro'),
            click: () => { shell.openExternal(INTRO_URL); }
        }]
    }];

    Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

module.exports = {
    setupApplicationMenu,
    showAbout,
    t,
    feedbackURL,
    INTRO_URL
};
