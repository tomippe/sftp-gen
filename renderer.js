document.addEventListener('DOMContentLoaded', () => {
    // 要素の取得
    const importSteBtn = document.getElementById('importSteBtn');
    const selectFolderBtn = document.getElementById('selectFolderBtn');
    const generateBtn = document.getElementById('generateBtn');
    const folderPathInput = document.getElementById('folderPath');
    const hostInput = document.getElementById('host');
    const usernameInput = document.getElementById('username');
    const passwordInput = document.getElementById('password');
    const remotePathInput = document.getElementById('remotePath');
    const uploadOnSaveCheckbox = document.getElementById('uploadOnSave');
    const statusMessage = document.getElementById('statusMessage');

    // STEファイルインポートボタンのハンドラー
    importSteBtn.addEventListener('click', async () => {
        const result = await window.ipcRenderer.invoke('select-ste-file');            
        if (!result || !result.success) {
            if (result && result.error) {
                statusMessage.textContent = result.error;
            }
            return;
        }
        const config = result.config;
        folderPathInput.value = config.folderPath;
        hostInput.value = config.host;
        usernameInput.value = config.username;
        remotePathInput.value = config.remotePath;            
        // フォームの入力状態を更新
        updateFormState();        
    });

    // フォルダ選択ボタンのハンドラー
    selectFolderBtn.addEventListener('click', async () => {
        const path = await window.ipcRenderer.invoke('select-directory');
        if (path) {
            folderPathInput.value = path;
            updateFormState();
        }
    });

    // 設定ファイル生成ボタンのハンドラー
    generateBtn.addEventListener('click', async () => {
        try {
            const config = {
                folderPath: folderPathInput.value,
                config: {
                    host: hostInput.value,
                    username: usernameInput.value,
                    password: passwordInput.value,
                    remotePath: remotePathInput.value,
                    uploadOnSave: uploadOnSaveCheckbox.checked
                }
            };

            await window.ipcRenderer.invoke('generate-sftp-json', config);
            
            // まずエディタ名を取得（checkOnly = true）
            const editor = await window.ipcRenderer.invoke('openInEditor', config.folderPath, true);
            statusMessage.textContent = `生成に成功しました。${editor}で開きます。`;
            
            // 1秒後に実際にエディタを開く（checkOnly = false）
            setTimeout(async () => {
                await window.ipcRenderer.invoke('openInEditor', config.folderPath, false);
            }, 1000);
        } catch (error) {
            console.error('設定ファイル生成エラー:', error);
            statusMessage.textContent = '設定ファイルの生成に失敗しました: ' + error.message;
        }
    });

    // フォームの入力状態を監視して生成ボタンの有効/無効を切り替え
    function updateFormState() {
        const isValid = folderPathInput.value && 
                       hostInput.value && 
                       usernameInput.value;
        generateBtn.disabled = !isValid;
        statusMessage.textContent = '';
    }

    // 入力フィールドの変更を監視
    [hostInput, usernameInput, passwordInput, remotePathInput].forEach(input => {
        input.addEventListener('input', updateFormState);
    });

    // 初期状態の設定
    updateFormState();
});

// パスをクリップボードにコピーする関数
async function copyPath(elementId) {
    try {
        const input = document.getElementById(elementId);
        const result = await window.electronAPI.writeToClipboard(input.value);
        
        if (result.success) {
            const button = document.querySelector(`button[onclick="copyPath('${elementId}')"]`);
            const originalText = button.textContent;
            button.textContent = 'コピーしました！';
            button.classList.add('copied');
            
            setTimeout(() => {
                button.textContent = originalText;
                button.classList.remove('copied');
            }, 2000);
        }
    } catch (error) {
        console.error('コピーエラー:', error);
    }
} 