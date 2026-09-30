// about.html の CSP は script-src 'self' のため、インラインスクリプトは実行されない。
(async () => {
    const info = await window.aboutAPI.getInfo();
    document.getElementById('logo').src = info.logoUrl;
    document.getElementById('appName').textContent = info.appName;
    document.getElementById('detail').textContent = info.detail;
    document.getElementById('introBtn').textContent = info.labels.openIntro;
    document.getElementById('okBtn').textContent = info.labels.ok;
    document.getElementById('logo').addEventListener('click', () => window.aboutAPI.openIntro());
    if (info.showUpdateCheck) {
        document.getElementById('updateBtn').textContent = info.labels.checkUpdatesBtn;
        document.getElementById('updateBtn').addEventListener('click', () => window.aboutAPI.checkUpdates());
    } else {
        document.getElementById('updateBtn').hidden = true;
    }
    document.getElementById('okBtn').addEventListener('click', () => window.aboutAPI.close());
})();
