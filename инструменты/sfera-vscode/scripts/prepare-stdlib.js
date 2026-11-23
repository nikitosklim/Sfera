'use strict';
// Кладёт стандартную библиотеку Сферы внутрь расширения. Маркетплейс VS Code не принимает пакеты
// с русскими именами файлов (он заменяет их на «?», и разные файлы «склеиваются»), поэтому вся
// библиотека упаковывается в ОДИН файл с латинским именем — stdlib.json. При запуске расширение
// разворачивает его в папку пользователя уже с настоящими именами.
// Запускается перед упаковкой (vscode:prepublish) и вручную: npm run prepare-stdlib
const fs = require('fs');
const path = require('path');

const откуда = path.join(__dirname, '..', '..', '..', 'стандартная_библиотека');
const куда = path.join(__dirname, '..', 'stdlib.json');

if (!fs.existsSync(откуда)) {
  if (fs.existsSync(куда)) { console.log('Исходной стандартной библиотеки рядом нет — оставляю имеющийся stdlib.json.'); process.exit(0); }
  console.error('Не найдена папка стандартная_библиотека: ' + откуда);
  process.exit(1);
}
const файлы = {};
(function собрать(папка, префикс) {
  for (const з of fs.readdirSync(папка, { withFileTypes: true }).sort((а, б) => а.name.localeCompare(б.name))) {
    if (з.isDirectory()) собрать(path.join(папка, з.name), префикс + з.name + '/');
    else if (з.name.endsWith('.код')) файлы[префикс + з.name] = fs.readFileSync(path.join(папка, з.name), 'utf8');
  }
})(откуда, '');
fs.writeFileSync(куда, JSON.stringify({ версия: require('../package.json').version, файлы }));
console.log(`Стандартная библиотека: ${Object.keys(файлы).length} файлов → stdlib.json`);
