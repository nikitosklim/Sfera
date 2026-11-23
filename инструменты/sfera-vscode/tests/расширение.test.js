'use strict';
// Проверка «склейки» расширения: подставляем поддельный модуль vscode и вызываем настоящие провайдеры.
const assert = require('assert');
const Module = require('module');
const path = require('path');
const fs = require('fs');
const os = require('os');

const зарегистрировано = {};
class Позиция { constructor(line, character) { this.line = line; this.character = character; } }
class Диапазон {}
const vscode = {
  CompletionItemKind: { Variable: 1, Function: 2, Method: 3, Field: 4, Struct: 5, Interface: 6, Constant: 7, Module: 8, Keyword: 9, Class: 10, Text: 0 },
  CompletionItem: class { constructor(label, kind) { this.label = label; this.kind = kind; } },
  SnippetString: class { constructor(v) { this.value = v; } },
  MarkdownString: class { constructor() { this.v = ''; } appendCodeblock(t) { this.v += t; return this; } appendMarkdown(t) { this.v += t; return this; } },
  SignatureInformation: class { constructor(label, documentation) { this.label = label; this.documentation = documentation; } },
  ParameterInformation: class { constructor(label) { this.label = label; } },
  SignatureHelp: class {},
  Location: class { constructor(uri, pos) { this.uri = uri; this.pos = pos; } },
  Hover: class { constructor(c) { this.contents = c; } },
  Position: Позиция, Range: Диапазон,
  TextEdit: { insert: (pos, text) => ({ pos, text }) },
  Uri: { file: (p) => ({ fsPath: p, scheme: 'file', toString: () => 'file://' + p }) },
  window: { createOutputChannel: () => ({ appendLine() {}, dispose() {} }), showWarningMessage: () => Promise.resolve() },
  workspace: {
    getConfiguration: () => ({ get: (k, д) => (k === 'enableLanguageServer' ? false : (д !== undefined ? д : '')) }),
    getWorkspaceFolder: () => null,
    onDidCloseTextDocument: () => ({ dispose() {} })
  },
  languages: {
    registerCompletionItemProvider: (_, п) => { зарегистрировано.дополнение = п; return { dispose() {} }; },
    registerSignatureHelpProvider: (_, п) => { зарегистрировано.параметры = п; return { dispose() {} }; },
    registerDefinitionProvider: (_, п) => { зарегистрировано.определение = п; return { dispose() {} }; },
    registerHoverProvider: (_, п) => { зарегистрировано.справка = п; return { dispose() {} }; }
  }
};
const загрузить = Module._load;
Module._load = function (запрос, ...остальное) { return запрос === 'vscode' ? vscode : загрузить.call(this, запрос, ...остальное); };

const расширение = require('../src/extension.js');
const корень = path.join(__dirname, '..');
const хранилище = fs.mkdtempSync(path.join(os.tmpdir(), 'сфера-хранилище-'));
расширение.activate({ extensionPath: корень, globalStorageUri: { fsPath: хранилище }, subscriptions: [] });
assert.ok(fs.existsSync(path.join(хранилище, 'stdlib-' + require('../package.json').version, 'хеш.код')), 'библиотека не развернулась из stdlib.json');
assert.ok(зарегистрировано.дополнение && зарегистрировано.параметры && зарегистрировано.определение && зарегистрировано.справка, 'не все провайдеры зарегистрированы');

let версия = 0;
function документ(текстСКурсором) {
  const индекс = текстСКурсором.indexOf('|');
  const текст = текстСКурсором.replace('|', '');
  const до = текст.slice(0, индекс).split('\n');
  const строки = текст.split('\n');
  const файл = path.join(os.tmpdir(), 'главная.код');
  return {
    д: { uri: vscode.Uri.file(файл), version: ++версия, getText: () => текст, lineAt: (н) => ({ text: строки[н] }) },
    п: new Позиция(до.length - 1, до[до.length - 1].length)
  };
}

{
  const { д, п } = документ('подключить хеш;\nфункция главная(): целое\n    бах2|\nконец\n');
  const эл = зарегистрировано.дополнение.provideCompletionItems(д, п);
  const э = эл.find(х => (х.label.label || х.label) === 'бах256');
  assert.ok(э, 'бах256 нет в списке');
  assert.ok(э.insertText && э.insertText.value.startsWith('бах256('), 'нет сниппета с параметрами');
}
{
  const { д, п } = документ('функция главная(): целое\n    бах2|\nконец\n');
  const э = зарегистрировано.дополнение.provideCompletionItems(д, п).find(х => (х.label.label || х.label) === 'бах256');
  assert.ok(э && э.additionalTextEdits && /подключить хеш;/.test(э.additionalTextEdits[0].text), 'нет автоподключения');
}
{
  const { д, п } = документ('функция главная(): целое\n    Список из целых л = Список из целых();\n    л.|\nконец\n');
  const м = зарегистрировано.дополнение.provideCompletionItems(д, п).map(х => х.label);
  assert.ok(м.includes('добавить') && м.length === 6, м.join());
}
{
  const { д, п } = документ('функция главная(): целое\n    вывести(|);\nконец\n');
  assert.strictEqual(зарегистрировано.параметры.provideSignatureHelp(д, п).signatures[0].label, 'вывести(значение)');
}
{
  const { д, п } = документ('подключить |\n');
  assert.ok(зарегистрировано.дополнение.provideCompletionItems(д, п).some(х => х.label === 'сеть'));
}
console.log('расширение: все проверки пройдены');
