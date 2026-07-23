// 言語データを保持する変数
let i18n = {};

// システムロケールを取得する関数
async function getSystemLocale() {
    try {
        const locale = await window.electronAPI.getSystemLocale();
        const supportedLocales = ['ja', 'en', 'zh'];
        const lang = locale.split('-')[0].toLowerCase();
        
        if (supportedLocales.includes(lang)) {
            return lang;
        }
        return 'en';
    } catch (error) {
        return 'en';
    }
}

// 言語ファイルを読み込む関数
async function loadLanguageFile(forceLang = null) {
    try {
        const systemLocale = await getSystemLocale();
        const lang = forceLang || systemLocale;
        
        const langPath = `locales/${lang}.json`;
        const response = await fetch(langPath);
        if (response.ok) {
            i18n = await response.json();
        } else {
            const fallbackResponse = await fetch('locales/en.json');
            i18n = await fallbackResponse.json();
        }
        
        updateUILabels();
    } catch (error) {
        try {
            const fallbackResponse = await fetch('locales/en.json');
            i18n = await fallbackResponse.json();
            updateUILabels();
        } catch (fallbackError) {
            console.error('Failed to load language file:', fallbackError);
        }
    }
}

// UIラベルを更新する関数
function updateUILabels() {
    // タイトルの更新
    document.title = i18n.title;

    // インポートボタン
    document.getElementById('importSteBtn').textContent = i18n.importSte;

    // 各フォームフィールドのラベルとプレースホルダー
    updateField('host', i18n.host);
    updateField('username', i18n.username);
    updateField('password', i18n.password);
    updateField('remotePath', i18n.remotePath);
    updateField('folderPath', i18n.folder);

    // フォルダ選択ボタン
    document.getElementById('selectFolderBtn').textContent = i18n.folder.selectButton;

    // チェックボックスのラベル
    document.querySelector('label[for="uploadOnSave"]').textContent = i18n.uploadOnSave.label;

    // 生成ボタン
    document.getElementById('generateBtn').textContent = i18n.generate.button;
}

// フィールドの更新ヘルパー関数
function updateField(id, data) {
    const label = document.querySelector(`label[for="${id}"]`) || 
                 document.querySelector(`#${id}`).previousElementSibling;
    const input = document.getElementById(id);
    
    if (label) label.textContent = data.label;
    if (input) input.placeholder = data.placeholder;
}

// デバッグ用の言語切り替え関数をグローバルに公開
window.setLanguage = async (lang) => {
    await loadLanguageFile(lang);
};

// 初期化
document.addEventListener('DOMContentLoaded', async () => {
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
    const togglePassword = document.getElementById('togglePassword');

    function applySteConfig(config) {
        folderPathInput.value = config.folderPath;
        hostInput.value = config.host;
        usernameInput.value = config.username;
        passwordInput.value = config.password;
        remotePathInput.value = config.remotePath;
        updateFormState();
    }

    function applySteOpenResult(result) {
        if (result && result.success) {
            applySteConfig(result.config);
        } else if (result && result.error) {
            statusMessage.textContent = i18n.generate.generateError.replace('{error}', result.error);
        }
    }

    window.electronAPI.onSteFileOpened(applySteOpenResult);

    try {
        await loadLanguageFile();
    } catch (error) {
        console.error('Initialization error:', error);
    }

    applySteOpenResult(await window.electronAPI.takePendingSteOpen());

    // STEファイルインポートボタンのハンドラー
    importSteBtn.addEventListener('click', async () => {
        try {
            const result = await window.electronAPI.selectSteFile();
            if (result.success) {
                applySteConfig(result.config);
            }
        } catch (error) {
            console.error(i18n.clipboard.error, error);
            statusMessage.textContent = i18n.generate.generateError.replace('{error}', error.message);
        }
    });

    // フォルダ選択ボタンのハンドラー
    selectFolderBtn.addEventListener('click', async () => {
        try {
            const result = await window.electronAPI.selectDirectory();
            if (result) {
                folderPathInput.value = result;
                updateFormState();
            }
        } catch (error) {
            console.error(i18n.clipboard.error, error);
            statusMessage.textContent = i18n.generate.generateError.replace('{error}', error.message);
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

            await window.electronAPI.generateSftpJson(config);
            
            // まずエディタ名を取得（checkOnly = true）
            const editor = await window.electronAPI.openInEditor(config.folderPath, true);
            statusMessage.textContent = i18n.generate.successWithEditor.replace('{editor}', editor);
            
            // 1秒後に実際にエディタを開く（checkOnly = false）
            setTimeout(async () => {
                await window.electronAPI.openInEditor(config.folderPath, false);
            }, 1000);
        } catch (error) {
            console.error(i18n.clipboard.error, error);
            statusMessage.textContent = i18n.generate.generateError.replace('{error}', error.message);
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

    togglePassword.addEventListener('click', () => {
        // パスワードの表示/非表示を切り替え
        const type = passwordInput.type === 'password' ? 'text' : 'password';
        passwordInput.type = type;
        
        // アイコンの切り替え
        togglePassword.querySelector('use').setAttribute('href', 
            type === 'password' ? '#icon-eye' : '#icon-eye-slash'
        );
    });
}); 