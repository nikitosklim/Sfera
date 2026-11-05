// Расширение «Сфера» для VS Code: подключает языковой сервер сфера_lsp.
const vscode = require('vscode');
const { LanguageClient } = require('vscode-languageclient/node');

let клиент;

function activate(context) {
  const настройки = vscode.workspace.getConfiguration('sfera');
  if (!настройки.get('enableLanguageServer', true)) return;

  const путь = (настройки.get('serverPath') || '').trim() || 'сфера_lsp';
  const сервер = { command: путь, args: [] };
  клиент = new LanguageClient(
    'sfera',
    'Сфера',
    { run: сервер, debug: сервер },
    { documentSelector: [{ scheme: 'file', language: 'sfera' }, { scheme: 'untitled', language: 'sfera' }] }
  );

  клиент.start().catch(() => {
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
