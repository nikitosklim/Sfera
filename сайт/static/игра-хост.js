// игра-хост.js — загрузчик игр на Сфере для браузера (холст, клавиши, мышь, звук, рекорды).
// Страница: <canvas id="игра"></canvas> и <script src="игра-хост.js" data-wasm="игра.wasm"></script>
// Игру собирают так: сфера игра.код -c --целевая-платформа wasm32-wasi --wasm-хост
(function () {
  'use strict';
  var скрипт = document.currentScript;
  var путь = (скрипт && скрипт.getAttribute('data-wasm')) || 'игра.wasm';
  var холстЭл = document.getElementById('игра') || document.querySelector('canvas');
  if (!холстЭл) { холстЭл = document.createElement('canvas'); холстЭл.id = 'игра'; document.body.appendChild(холстЭл); }
  var к2 = холстЭл.getContext('2d');
  var память = null, экспорт = null;
  var декодер = new TextDecoder();
  var начало = performance.now();

  function текст(адрес) {
    var б = new Uint8Array(память.buffer), конец = адрес;
    while (б[конец] !== 0) конец++;
    return декодер.decode(б.subarray(адрес, конец));
  }
  function ц(к, з, с) { return 'rgb(' + (к & 255) + ',' + (з & 255) + ',' + (с & 255) + ')'; }

  // ---- ввод
  var имена = { 'влево': 'ArrowLeft', 'вправо': 'ArrowRight', 'вверх': 'ArrowUp', 'вниз': 'ArrowDown',
    'пробел': 'Space', 'ввод': 'Enter', 'escape': 'Escape' };
  function код(имя) {
    var н = String(имя).toLowerCase();
    if (имена[н]) return имена[н];
    if (/^[a-z]$/.test(н)) return 'Key' + н.toUpperCase();
    if (/^[0-9]$/.test(н)) return 'Digit' + н;
    return имя;
  }
  var зажато = {}, нажато = {}, мышьХ = 0, мышьУ = 0, мышьЗажата = 0, мышьНажата = 0;
  window.addEventListener('keydown', function (э) {
    if (!зажато[э.code]) нажато[э.code] = 1;
    зажато[э.code] = 1;
    if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Space'].indexOf(э.code) >= 0) э.preventDefault();
  });
  window.addEventListener('keyup', function (э) { зажато[э.code] = 0; });
  window.addEventListener('blur', function () { зажато = {}; мышьЗажата = 0; });
  function позиция(э) {
    var р = холстЭл.getBoundingClientRect();
    мышьХ = Math.round((э.clientX - р.left) * холстЭл.width / р.width);
    мышьУ = Math.round((э.clientY - р.top) * холстЭл.height / р.height);
  }
  холстЭл.addEventListener('pointermove', позиция);
  холстЭл.addEventListener('pointerdown', function (э) { позиция(э); мышьЗажата = 1; мышьНажата = 1; });
  window.addEventListener('pointerup', function () { мышьЗажата = 0; });

  // ---- сеть (WebSocket)
  var сокет = null, входящие = [], кольцо = { начало: 0, размер: 0, где: 0 }, кодер = new TextEncoder();
  function писатьТекст(т) {
    var б = кодер.encode(String(т));
    if (!кольцо.размер) return 0;
    if (б.length > кольцо.размер - 2) б = б.subarray(0, кольцо.размер - 2);
    if (кольцо.где + б.length + 1 > кольцо.размер) кольцо.где = 0;
    var а = кольцо.начало + кольцо.где;
    var м = new Uint8Array(память.buffer);
    м.set(б, а); м[а + б.length] = 0;
    кольцо.где += б.length + 1;
    return а;
  }

  // ---- звук
  var аудио = null;
  function звук(частота, мс) {
    try {
      аудио = аудио || new (window.AudioContext || window.webkitAudioContext)();
      var о = аудио.createOscillator(), г = аудио.createGain();
      о.type = 'square'; о.frequency.value = частота; г.gain.value = 0.05;
      о.connect(г); г.connect(аудио.destination); о.start(); о.stop(аудио.currentTime + мс / 1000);
    } catch (е) {}
  }

  var хост = {
    'и_холст': function (ш, в) { холстЭл.width = ш; холстЭл.height = в; return 0; },
    'и_цвет': function (к, з, с) { к2.fillStyle = к2.strokeStyle = ц(к, з, с); return 0; },
    'и_очистить': function (к, з, с) { var было = к2.fillStyle; к2.fillStyle = ц(к, з, с); к2.fillRect(0, 0, холстЭл.width, холстЭл.height); к2.fillStyle = было; return 0; },
    'и_прямоугольник': function (х, у, ш, в) { к2.fillRect(х, у, ш, в); return 0; },
    'и_круг': function (х, у, р) { к2.beginPath(); к2.arc(х, у, Math.max(0, р), 0, Math.PI * 2); к2.fill(); return 0; },
    'и_линия': function (х1, у1, х2, у2, т) { к2.lineWidth = т > 0 ? т : 1; к2.beginPath(); к2.moveTo(х1, у1); к2.lineTo(х2, у2); к2.stroke(); return 0; },
    'и_надпись': function (что, х, у, размер) { к2.font = (размер > 0 ? размер : 16) + 'px sans-serif'; к2.textBaseline = 'top'; к2.fillText(текст(что), х, у); return 0; },
    'и_клавиша': function (имя) { return зажато[код(текст(имя))] ? 1 : 0; },
    'и_клавиша_нажата': function (имя) { return нажато[код(текст(имя))] ? 1 : 0; },
    'и_мышь_х': function () { return мышьХ; },
    'и_мышь_у': function () { return мышьУ; },
    'и_мышь_кнопка': function () { return мышьЗажата; },
    'и_мышь_нажата': function () { return мышьНажата; },
    'и_запустить': function (имя) {
      var н = текст(имя);
      function кадр() {
        var ф = экспорт[н];
        if (typeof ф !== 'function') { console.error('Сфера: в программе нет функции «' + н + '»'); return; }
        try { ф(); } catch (е) { if (!(е && е.выход !== undefined)) { console.error('Сфера:', е); return; } }
        нажато = {}; мышьНажата = 0;
        requestAnimationFrame(кадр);
      }
      requestAnimationFrame(кадр);
      return 0;
    },
    'и_случайное': function (до) { return до > 0 ? Math.floor(Math.random() * до) : 0; },
    'и_звук': function (ч, мс) { звук(ч, мс); return 0; },
    'и_сохранить': function (имя, з) { try { localStorage.setItem('сфера-игра:' + текст(имя), String(з)); } catch (е) {} return 0; },
    'и_взять': function (имя) { try { return parseInt(localStorage.getItem('сфера-игра:' + текст(имя)), 10) || 0; } catch (е) { return 0; } },
    'и_сокет_открыть': function (адрес) {
      try {
        входящие = [];
        сокет = new WebSocket(текст(адрес));
        сокет.onmessage = function (э) { if (typeof э.data === 'string') { входящие.push(э.data); if (входящие.length > 500) входящие.shift(); } };
      } catch (е) { сокет = null; }
      return 0;
    },
    'и_сокет_состояние': function () { return !сокет ? 0 : сокет.readyState === 0 ? 1 : сокет.readyState === 1 ? 2 : 3; },
    'и_сокет_отправить': function (т) { if (сокет && сокет.readyState === 1) { сокет.send(текст(т)); return 1; } return 0; },
    'и_сокет_есть': function () { return входящие.length; },
    'и_сокет_взять': function () { return писатьТекст(входящие.length ? входящие.shift() : ''); },
    'и_сокет_закрыть': function () { if (сокет) { try { сокет.close(); } catch (е) {} } return 0; },
    'и_время': function () { return Math.round(performance.now() - начало) | 0; }
  };

  var wasi = {
    fd_write: function (fd, iovs, n, пишем) {
      var v = new DataView(память.buffer), всего = 0, т = '';
      for (var i = 0; i < n; i++) {
        var а = v.getUint32(iovs + i * 8, true), д = v.getUint32(iovs + i * 8 + 4, true);
        т += декодер.decode(new Uint8Array(память.buffer, а, д)); всего += д;
      }
      if (т.trim()) console.log(т.replace(/\n$/, ''));
      v.setUint32(пишем, всего, true); return 0;
    },
    fd_fdstat_get: function (fd, p) { var v = new DataView(память.buffer); v.setUint8(p, 2); v.setUint16(p + 2, 0, true); v.setBigUint64(p + 8, 0n, true); v.setBigUint64(p + 16, 0n, true); return 0; },
    args_sizes_get: function (a, b) { var v = new DataView(память.buffer); v.setUint32(a, 0, true); v.setUint32(b, 0, true); return 0; },
    args_get: function () { return 0; },
    environ_get: function () { return 0; },
    environ_sizes_get: function (a, b) { var v = new DataView(память.buffer); v.setUint32(a, 0, true); v.setUint32(b, 0, true); return 0; },
    clock_time_get: function (id, точность, пишем) { new DataView(память.buffer).setBigUint64(пишем, BigInt(Math.round(Date.now() * 1e6)), true); return 0; },
    random_get: function (p, n) { crypto.getRandomValues(new Uint8Array(память.buffer, p, n)); return 0; },
    proc_exit: function (код) { throw { выход: код }; }
  };

  fetch(путь, { cache: 'no-cache' })
    .then(function (о) { if (!о.ok) throw new Error('не найден ' + путь + ' (' + о.status + ')'); return о.arrayBuffer(); })
    .then(function (б) { return WebAssembly.compile(б); })
    .then(function (м) {
      var импорты = { env: {}, wasi_snapshot_preview1: {} };
      WebAssembly.Module.imports(м).forEach(function (и) {
        if (и.module === 'env') импорты.env[и.name] = хост[и.name] || function () { return 0; };
        else импорты.wasi_snapshot_preview1[и.name] = wasi[и.name] || function () { return 52; };
      });
      return WebAssembly.instantiate(м, импорты);
    })
    .then(function (э) {
      экспорт = э.exports; память = экспорт.memory;
      var старые = память.grow(1);
      кольцо.начало = старые * 65536; кольцо.размер = 65536; кольцо.где = 0;
      try { экспорт._start(); } catch (е) { if (!(е && е.выход !== undefined)) throw е; }
    })
    .catch(function (е) { console.error('Сфера: игра не запустилась —', е); });
})();
