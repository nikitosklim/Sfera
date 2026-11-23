'use strict';
// Читает из stdin список файлов пакета (npx @vscode/vsce ls) и падает, если есть имена не из ASCII:
// маркетплейс такие имена портит (Item has already been added...).
let текст = '';
process.stdin.on('data', д => (текст += д));
process.stdin.on('end', () => {
  const строки = текст.split(/\r?\n/).filter(с => с.trim());
  if (строки.length < 10) {
    console.error('Список файлов пакета пуст или слишком короткий — проверка не выполнена.');
    process.exit(1);
  }
  const плохие = текст.split(/\r?\n/).filter(с => /[^\x00-\x7F]/.test(с));
  if (плохие.length) {
    console.error('В пакете есть файлы с не-ASCII именами (маркетплейс их не принимает):\n  ' + плохие.join('\n  '));
    process.exit(1);
  }
  console.log('Имена файлов в пакете: только ASCII — ок');
});
