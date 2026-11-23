'use strict';
// Кладёт стандартную библиотеку Сферы внутрь расширения (папка stdlib/), чтобы подсказки по
// библиотекам работали сразу после установки из маркетплейса. Запускается перед упаковкой
// (vscode:prepublish) и вручную: npm run prepare-stdlib
const fs = require('fs');
const path = require('path');

const откуда = path.join(__dirname, '..', '..', '..', 'стандартная_библиотека');
const куда = path.join(__dirname, '..', 'stdlib');

if (!fs.existsSync(откуда)) {
  if (fs.existsSync(куда)) { console.log('Исходной стандартной библиотеки рядом нет — оставляю имеющуюся stdlib/.'); process.exit(0); }
  console.error('Не найдена папка стандартная_библиотека: ' + откуда);
  process.exit(1);
}
fs.rmSync(куда, { recursive: true, force: true });
fs.mkdirSync(куда, { recursive: true });
let n = 0;
(function копировать(из, в) {
  for (const з of fs.readdirSync(из, { withFileTypes: true })) {
    const а = path.join(из, з.name), б = path.join(в, з.name);
    if (з.isDirectory()) { fs.mkdirSync(б, { recursive: true }); копировать(а, б); }
    else if (з.name.endsWith('.код')) { fs.copyFileSync(а, б); n++; }
  }
})(откуда, куда);
console.log(`Стандартная библиотека скопирована: ${n} файлов → stdlib/`);
