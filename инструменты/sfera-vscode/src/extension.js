// Расширение «Сфера» для VS Code.
//
// Две независимые части:
//  1. Подсказки (автодополнение, параметры вызова, переход к определению, справка) делает
//     встроенный движок (src/движок.js). Ему не нужны внешние программы — он работает сразу
//     после установки расширения, читает стандартную библиотеку из папки stdlib/ внутри
//     расширения и подхватывает подключённые файлы проекта.
//  2. Ошибки в реальном времени показывает языковой сервер сфера_lsp. Он вшит в расширение
//     (папка bin/ для вашей платформы). Если его нет, подсказки всё равно работают.
const vscode = require('vscode');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Движок } = require('./engine.js');
const подсказки = require('./hints.json');

let клиент;
let вызовов = 0;
// Подсказки запрашиваются при каждой набранной букве: так они появляются сами, даже если редактор
// не считает кириллицу «словом» и не запускает быстрые подсказки.
const БУКВЫ = 'абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯabcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_'.split('');
let движок;
const кэшКонтекстов = new Map();

const ВИДЫ = {
  'переменная': vscode.CompletionItemKind.Variable,
  'параметр': vscode.CompletionItemKind.Variable,
  'функция': vscode.CompletionItemKind.Function,
  'метод': vscode.CompletionItemKind.Method,
  'поле': vscode.CompletionItemKind.Field,
  'структура': vscode.CompletionItemKind.Struct,
  'контракт': vscode.CompletionItemKind.Interface,
  'константа': vscode.CompletionItemKind.Constant,
  'модуль': vscode.CompletionItemKind.Module,
  'ключевое': vscode.CompletionItemKind.Keyword,
  'тип': vscode.CompletionItemKind.Class
};

function исполняемое(имя) {
  return имя + (process.platform === 'win32' ? '.exe' : '');
}

function существует(п) {
  try { return fs.statSync(п).isFile(); } catch (e) { return false; }
}

// ---------- стандартная библиотека ----------

// Библиотека лежит в пакете одним файлом stdlib.json (маркетплейс не принимает русские имена файлов),
// а при запуске разворачивается в папку расширения для пользователя — уже с настоящими именами.
function развернутьСтандартнуюБиблиотеку(context, журнал) {
  try {
    const пакет = path.join(context.extensionPath, 'stdlib.json');
    if (!fs.existsSync(пакет)) return null;
    const версия = require('../package.json').version;
    const основа = context.globalStorageUri && context.globalStorageUri.fsPath
      ? context.globalStorageUri.fsPath
      : path.join(os.tmpdir(), 'sfera-vscode');
    const папка = path.join(основа, 'stdlib-' + версия);
    const метка = path.join(папка, '.готово');
    if (!fs.existsSync(метка)) {
      const данные = JSON.parse(fs.readFileSync(пакет, 'utf8'));
      fs.rmSync(папка, { recursive: true, force: true });
      for (const [имя, текст] of Object.entries(данные.файлы)) {
        const путь = path.join(папка, ...имя.split('/'));
        fs.mkdirSync(path.dirname(путь), { recursive: true });
        fs.writeFileSync(путь, текст, 'utf8');
      }
      fs.writeFileSync(метка, версия);
    }
    return папка;
  } catch (e) {
    журнал.appendLine('Не удалось развернуть стандартную библиотеку: ' + (e && e.message ? e.message : e));
    return null;
  }
}

function путиСтандартнойБиблиотеки(context, настройки, журнал) {
  const дом = os.homedir();
  const пути = [
    (настройки.get('stdlibPath') || '').trim(),
    развернутьСтандартнуюБиблиотеку(context, журнал), // вшитая — версия совпадает с расширением
    path.join(context.extensionPath, '..', '..', 'стандартная_библиотека'), // запуск из репозитория (F5)
    process.env.SFERA_STDLIB || '',
    path.join(дом, '.sfera', 'lib', 'sfera', 'стандартная_библиотека'),
    '/usr/local/lib/sfera/стандартная_библиотека',
    path.join(process.env.LOCALAPPDATA || '', 'Сфера', 'lib', 'sfera', 'стандартная_библиотека')
  ];
  return пути.filter(п => п && fs.existsSync(п));
}

// ---------- контекст документа ----------

function контекстДокумента(документ) {
  const ключ = документ.uri.toString();
  const к = кэшКонтекстов.get(ключ);
  // Контекст переиспользуется, пока документ не менялся (и недолго после — чтобы не разбирать файл
  // на каждый запрос подряд); подключённые файлы проверяются по времени изменения заново.
  if (к && к.версия === документ.version && Date.now() - к.время < 1500) return к.контекст;
  const папка = vscode.workspace.getWorkspaceFolder(документ.uri);
  const путь = документ.uri.scheme === 'file' ? документ.uri.fsPath : null;
  const корень = папка ? папка.uri.fsPath : (путь ? path.dirname(путь) : null);
  const контекст = движок.контекст(документ.getText(), путь, корень);
  кэшКонтекстов.set(ключ, { версия: документ.version, время: Date.now(), контекст });
  return контекст;
}

// Куда вставить «подключить имя;»: после последнего подключить, иначе после шапки из комментариев.
function правкаПодключения(документ, имя) {
  const строки = документ.getText().split('\n');
  let последняя = -1;
  for (let i = 0; i < строки.length; i++) if (/^\s*подключить\s/u.test(строки[i])) последняя = i;
  if (последняя >= 0) return vscode.TextEdit.insert(new vscode.Position(последняя + 1, 0), `подключить ${имя};\n`);
  let i = 0;
  while (i < строки.length && (/^\s*\/\//.test(строки[i]) || !строки[i].trim())) i++;
  // перед первым «настоящим» кодом оставляем пустую строку
  return vscode.TextEdit.insert(new vscode.Position(i, 0), `подключить ${имя};\n\n`);
}

function создатьЭлемент(документ, позиция, э, настройки) {
  const метка = э.подключить ? { label: э.метка, description: `из «${э.подключить}»` } : э.метка;
  const элемент = new vscode.CompletionItem(метка, ВИДЫ[э.вид] || vscode.CompletionItemKind.Text);
  // Заменяемый диапазон задаём сами (не полагаемся на определение слова редактором, которое для кириллицы ненадёжно).
  const начало = документ.lineAt(позиция.line).text.slice(0, позиция.character).search(/[A-Za-z0-9_\u0400-\u04FF]*$/);
  элемент.range = new vscode.Range(new vscode.Position(позиция.line, начало < 0 ? позиция.character : начало), позиция);
  элемент.detail = э.деталь;
  if (э.док) элемент.documentation = new vscode.MarkdownString(э.док.replace(/\n/g, '  \n'));
  элемент.sortText = э.сортировка || '5' + э.метка;
  элемент.filterText = э.метка;
  if (э.вставка) {
    const следующий = документ.lineAt(позиция.line).text.charAt(позиция.character);
    if (следующий !== '(') элемент.insertText = new vscode.SnippetString(э.вставка);
  }
  if (э.подключить) элемент.additionalTextEdits = [правкаПодключения(документ, э.подключить)];
  return элемент;
}

// ---------- языковой сервер ----------

function найтиСервер(context, настройки) {
  const заданный = (настройки.get('serverPath') || '').trim();
  if (заданный) return заданный;
  const вшитый = path.join(context.extensionPath, 'bin', исполняемое('sfera_lsp')); // вшитый сервер (имя латиницей)
  if (существует(вшитый)) return вшитый;
  const имя = исполняемое('сфера_lsp');
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
    const п = path.join(м, имя);
    if (существует(п)) return п;
  }
  return null;
}

function запуститьСервер(context, настройки, журнал) {
  if (!настройки.get('enableLanguageServer', true)) return;
  const путь = найтиСервер(context, настройки);
  if (!путь) {
    журнал.appendLine('Языковой сервер сфера_lsp не найден — подсказки работают, проверка ошибок в реальном времени недоступна.');
    return;
  }
  try { fs.chmodSync(путь, 0o755); } catch (e) { /* на Windows и в только-для-чтения не нужно */ }
  const { LanguageClient } = require('vscode-languageclient/node');
  const сервер = { command: путь, args: [] };
  // Подсказки, справку и переход к определению делает встроенный движок (он видит подключённые файлы),
  // поэтому от сервера используем только диагностику — иначе подсказки дублировались бы.
  const молчать = () => undefined;
  клиент = new LanguageClient(
    'sfera',
    'Сфера',
    { run: сервер, debug: сервер },
    {
      documentSelector: [{ scheme: 'file', language: 'sfera' }, { scheme: 'untitled', language: 'sfera' }],
      outputChannel: журнал,
      middleware: {
        provideCompletionItem: молчать,
        provideHover: молчать,
        provideDefinition: молчать,
        provideSignatureHelp: молчать
      }
    }
  );
  клиент.start().then(
    () => журнал.appendLine('Языковой сервер запущен: ' + путь),
    (e) => журнал.appendLine('Не удалось запустить языковой сервер «' + путь + '»: ' + (e && e.message ? e.message : e))
  );
}

// ---------- активация ----------

function activate(context) {
  const настройки = vscode.workspace.getConfiguration('sfera');
  const журнал = vscode.window.createOutputChannel('Сфера');
  context.subscriptions.push(журнал);

  движок = new Движок({ подсказки, стдлибПути: путиСтандартнойБиблиотеки(context, настройки, журнал) });
  журнал.appendLine('Стандартная библиотека: ' + движок.проект.стдлибПути.join(', '));

  const язык = { language: 'sfera' };

  context.subscriptions.push(vscode.languages.registerCompletionItemProvider(язык, {
    provideCompletionItems(документ, позиция, токен, контекст) {
      const н = vscode.workspace.getConfiguration('sfera');
      const л = документ.lineAt(позиция.line).text.slice(0, позиция.character);
      if (вызовов < 25) {
        вызовов++;
        журнал.appendLine('[подсказки] запрос #' + вызовов + ', вид=' + (контекст ? контекст.triggerKind : '?') + ', перед курсором: «' + л.slice(-20) + '»');
      }
      // триггер «пробел» нужен только после «подключить »
      if (/\s$/.test(л) && !/^\s*подключить\s+$/u.test(л)) return undefined;
      const к = контекстДокумента(документ);
      let элементы = движок.дополнить(к, позиция.line, позиция.character);
      if (!н.get('suggestFromUnimported', true)) элементы = элементы.filter(э => !э.подключить);
      return элементы.map(э => создатьЭлемент(документ, позиция, э, н));
    }
  }, '.', ' ', ...БУКВЫ));

  context.subscriptions.push(vscode.languages.registerSignatureHelpProvider(язык, {
    provideSignatureHelp(документ, позиция) {
      const р = движок.подсказкаПараметров(контекстДокумента(документ), позиция.line, позиция.character);
      if (!р) return undefined;
      const сиг = new vscode.SignatureInformation(р.метка, р.док ? new vscode.MarkdownString(р.док) : undefined);
      сиг.parameters = р.параметры.map(п => new vscode.ParameterInformation(п));
      const помощь = new vscode.SignatureHelp();
      помощь.signatures = [сиг];
      помощь.activeSignature = 0;
      помощь.activeParameter = р.активный;
      return помощь;
    }
  }, '(', ','));

  context.subscriptions.push(vscode.languages.registerDefinitionProvider(язык, {
    provideDefinition(документ, позиция) {
      const о = движок.определить(контекстДокумента(документ), позиция.line, позиция.character);
      if (!о || !о.путь) return undefined;
      return new vscode.Location(vscode.Uri.file(о.путь), new vscode.Position(о.строка, Math.max(0, о.столбец || 0)));
    }
  }));

  context.subscriptions.push(vscode.languages.registerHoverProvider(язык, {
    provideHover(документ, позиция) {
      const с = движок.справка(контекстДокумента(документ), позиция.line, позиция.character);
      if (!с) return undefined;
      const md = new vscode.MarkdownString();
      md.appendCodeblock(с.заголовок, 'sfera');
      if (с.текст) md.appendMarkdown(с.текст.replace(/\n/g, '  \n'));
      return new vscode.Hover(md);
    }
  }));

  context.subscriptions.push(vscode.workspace.onDidCloseTextDocument(д => кэшКонтекстов.delete(д.uri.toString())));

  try {
    запуститьСервер(context, настройки, журнал);
  } catch (e) {
    // Сервер — дополнение (ошибки в реальном времени); его сбой не должен ломать подсказки.
    журнал.appendLine('Языковой сервер не запущен: ' + (e && e.message ? e.message : e));
  }
}

function deactivate() {
  return клиент ? клиент.stop() : undefined;
}

module.exports = { activate, deactivate };
