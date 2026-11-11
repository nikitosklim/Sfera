// Расширение «Сфера» для VS Code: подключает языковой сервер сфера_lsp.
const vscode = require('vscode');
const { LanguageClient } = require('vscode-languageclient/node');
const fs = require('fs');
const os = require('os');
const path = require('path');
const подсказки = require('./подсказки.json');

let клиент;
let серверЗапущен = false;

// Где искать сфера_lsp, если путь не задан: VS Code, запущенный из Dock или меню, не видит PATH из терминала.
function найтиСервер() {
  const exe = process.platform === 'win32' ? '.exe' : '';
  const дом = os.homedir();
  const места = [
    path.join(дом, '.sfera', 'bin'),
    path.join(дом, 'Applications', 'Панель Сферы.app', 'Contents', 'Resources', 'bin'),
    '/Applications/Панель Сферы.app/Contents/Resources/bin',
    '/usr/local/bin',
    '/opt/homebrew/bin',
    path.join(process.env.LOCALAPPDATA || '', 'Сфера', 'bin')
  ];
  for (const м of места) {
    const п = path.join(м, 'сфера_lsp' + exe);
    try { if (fs.existsSync(п)) return п; } catch (e) { /* ищем дальше */ }
  }
  return 'сфера_lsp';
}

// Запасное автодополнение: ключевые слова, типы и функции библиотеки подсказываются, даже если языковой сервер не запустился.
function запасноеДополнение() {
  const виды = { 'КлючевоеСлово': vscode.CompletionItemKind.Keyword, 'Тип': vscode.CompletionItemKind.Class, 'Функция': vscode.CompletionItemKind.Function };
  const элементы = подсказки.map(п => {
    const э = new vscode.CompletionItem(п.имя, виды[п.вид] || vscode.CompletionItemKind.Text);
    э.detail = п.деталь;
    if (п.док) э.documentation = п.док;
    return э;
  });
  return { provideCompletionItems: () => (серверЗапущен ? [] : элементы) };
}

function activate(context) {
  const настройки = vscode.workspace.getConfiguration('sfera');
  context.subscriptions.push(vscode.languages.registerCompletionItemProvider({ language: 'sfera' }, запасноеДополнение()));
  if (!настройки.get('enableLanguageServer', true)) return;

  const путь = (настройки.get('serverPath') || '').trim() || найтиСервер();
  const сервер = { command: путь, args: [] };
  клиент = new LanguageClient(
    'sfera',
    'Сфера',
    { run: сервер, debug: сервер },
    { documentSelector: [{ scheme: 'file', language: 'sfera' }, { scheme: 'untitled', language: 'sfera' }] }
  );

  клиент.start().then(() => { серверЗапущен = true; }).catch(() => {
    vscode.window.showWarningMessage(
      'Сфера: не удалось запустить языковой сервер «' + путь + '». Подсветка работает, но ошибки и подсказки отключены. ' +
      'Укажите путь к сфера_lsp в настройках (sfera.serverPath) или добавьте его в PATH.',
      'Открыть настройки'
    ).then(выбор => {
      if (выбор) vscode.commands.executeCommand('workbench.action.openSettings', 'sfera.serverPath');
    });
  });
  context.subscriptions.push({ dispose: () => клиент && клиент.stop() });
}

function deactivate() {
  return клиент ? клиент.stop() : undefined;
}

module.exports = { activate, deactivate };
