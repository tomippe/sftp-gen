/**
 * electron-builder afterPack — app-update.yml を同梱（electron-updater 用）
 */
const fs = require('fs-extra');
const path = require('path');

const UPDATE_FEED = {
    provider: 'generic',
    url: 'https://apps.tomippe.jp/sftp-gen/'
};

function writeAppUpdateYml(resourcesDir) {
    const yaml = `provider: ${UPDATE_FEED.provider}\nurl: ${UPDATE_FEED.url}\n`;
    fs.mkdirSync(resourcesDir, { recursive: true });
    fs.writeFileSync(path.join(resourcesDir, 'app-update.yml'), yaml, 'utf8');
}

exports.default = async function afterPack(context) {
    if (context.electronPlatformName !== 'darwin') return;

    const appName = `${context.packager.appInfo.productFilename}.app`;
    const resourcesDir = path.join(context.appOutDir, appName, 'Contents', 'Resources');
    writeAppUpdateYml(resourcesDir);
    console.log('  ✓ app-update.yml を同梱しました');
};

module.exports.writeAppUpdateYml = writeAppUpdateYml;
