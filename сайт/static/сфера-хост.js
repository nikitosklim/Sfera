// Загрузчик программ Сферы на страницах сайта.
// <script src="/статика/сфера-хост.js" data-модуль="стат" data-запас="/статика/stat.js" defer></script>
// Берёт /статика/клиент/<модуль>.wasm (сервер собирает его из сайт/клиент/<модуль>.код), даёт программе
// мост к странице (см. стандартная_библиотека/браузер.код) и запускает главную().
// Если сборка недоступна, подключает запасной скрипт из data-запас, чтобы страница не осталась без логики.
(function () {
  'use strict';
  var скрипт = document.currentScript;
  var модули = ((скрипт && скрипт.getAttribute('data-модуль')) || '').split(/\s+/).filter(Boolean);
  var запасные = ((скрипт && скрипт.getAttribute('data-запас')) || '').split(/\s+/).filter(Boolean);

  // Общие помощники страниц: запросы к серверу, хеш пароля, «кто я». Ими пользуются и программы на Сфере (через мост ниже),
  // и ещё не переписанные скрипты страниц (window.Сфера).
  var С = window.Сфера = window.Сфера || {};
  function шестнадцатеричное(буфер) {
    return Array.prototype.map.call(new Uint8Array(буфер), function (б) { return ('0' + б.toString(16)).slice(-2); }).join('');
  }
  // PBKDF2: из пароля и имени получается 64 hex-символа. Имя служит солью, поэтому одинаковые пароли у разных людей дают разные хеши.
  С.хешПароля = function (имя, пароль) {
    if (!window.crypto || !window.crypto.subtle) {
      return Promise.reject(new Error('Браузер не поддерживает безопасный ввод пароля: откройте сайт по https.'));
    }
    var к = new TextEncoder();
    return crypto.subtle.importKey('raw', к.encode(пароль), 'PBKDF2', false, ['deriveBits']).then(function (ключ) {
      return crypto.subtle.deriveBits({ name: 'PBKDF2', salt: к.encode('sfera:' + имя.toLowerCase()), iterations: 150000, hash: 'SHA-256' }, ключ, 256);
    }).then(шестнадцатеричное);
  };
  С.отправить = function (путь, поля) {
    var тело = typeof поля === 'string' ? поля : new URLSearchParams(поля || {}).toString();
    return fetch(путь, { method: 'POST', headers: { 'X-Sfera': '1', 'Content-Type': 'application/x-www-form-urlencoded' }, body: тело })
      .then(function (о) { return о.json().catch(function () { return { ok: false, ошибка: 'Сервер ответил не так, как ожидалось' }; }); });
  };
  С.получить = function (путь) {
    return fetch(путь, { headers: { 'X-Sfera': '1' } })
      .then(function (о) { return о.json().catch(function () { return { ok: false }; }); });
  };
  С.кто = function () {
    if (!С._кто) С._кто = С.получить('/аккаунт/я').catch(function () { return { вошёл: false }; });
    return С._кто;
  };
  С.роли = { 'пользователь': 'пользователь', 'модератор': 'модератор', 'админ': 'администратор' };

  // Сборка архива пакета: tar + gzip прямо в браузере. Файлы читаются из выбранных пользователем File, манифест передаётся текстом.
  var МАКС_ПАКЕТА = 5 * 1024 * 1024;
  function байтыТекста(т) { return new TextEncoder().encode(т); }
  function писатьВ(буфер, смещение, текст) { буфер.set(байтыТекста(текст), смещение); }
  function заголовокTar(имя, размер) {
    var ш = new Uint8Array(512), имяБ = байтыТекста(имя);
    if (имяБ.length > 100) throw new Error('Имя файла «' + имя + '» слишком длинное');
    ш.set(имяБ, 0);
    писатьВ(ш, 100, '0000644\0'); писатьВ(ш, 108, '0000000\0'); писатьВ(ш, 116, '0000000\0');
    писатьВ(ш, 124, размер.toString(8).padStart(11, '0') + '\0');
    писатьВ(ш, 136, Math.floor(Date.now() / 1000).toString(8).padStart(11, '0') + '\0');
    писатьВ(ш, 148, '        '); писатьВ(ш, 156, '0'); писатьВ(ш, 257, 'ustar\0'); писатьВ(ш, 263, '00');
    var сумма = 0; for (var i = 0; i < 512; i++) сумма += ш[i];
    писатьВ(ш, 148, сумма.toString(8).padStart(6, '0') + '\0 ');
    return ш;
  }
  function собратьTar(записи) {
    var части = [], всего = 0;
    записи.forEach(function (з) {
      части.push(заголовокTar(з.имя, з.данные.length)); части.push(з.данные);
      var хвост = (512 - (з.данные.length % 512)) % 512; if (хвост) части.push(new Uint8Array(хвост));
    });
    части.push(new Uint8Array(1024));
    части.forEach(function (ч) { всего += ч.length; });
    var итог = new Uint8Array(всего), п = 0;
    части.forEach(function (ч) { итог.set(ч, п); п += ч.length; });
    return итог;
  }
  С.собратьАрхив = function (файлы, манифест) {
    if (!window.CompressionStream) return Promise.reject(new Error('Браузер не умеет сжимать архивы. Обновите его или загрузите готовый .tar.gz.'));
    return Promise.all(Array.prototype.map.call(файлы, function (ф) {
      return ф.arrayBuffer().then(function (б) { return { имя: ф.name, данные: new Uint8Array(б) }; });
    })).then(function (записи) {
      записи.unshift({ имя: 'пакет.сфера', данные: байтыТекста(манифест) });
      var сумма = 0; записи.forEach(function (з) { сумма += з.данные.length; });
      if (сумма > МАКС_ПАКЕТА) throw new Error('Файлы пакета больше 5 МБ.');
      return new Response(new Blob([собратьTar(записи)]).stream().pipeThrough(new CompressionStream('gzip'))).arrayBuffer();
    });
  };
  С.опубликовать = function (имя, версия, архив) {
    return fetch('/пакеты/публикация/' + encodeURIComponent(имя) + '/' + encodeURIComponent(версия), {
      method: 'PUT', headers: { 'X-Sfera': '1', 'Content-Type': 'application/gzip' }, body: архив
    }).then(function (о) { return о.json().catch(function () { return { ok: false, ошибка: 'Сервер ответил не так, как ожидалось' }; }); });
  };

  function запасной(номер) {
    var путь = запасные[номер];
    if (!путь) return;
    var с = document.createElement('script'); с.src = путь; document.head.appendChild(с);
  }
  if (!модули.length) return;
  модули.forEach(запустить);

  function запустить(модуль, номер) {

  var ручки = [null];          // ручка 0 = «ничего»
  var событие = 0;
  var память = null, экспорт = null;
  var кольцо = { начало: 0, размер: 0, где: 0 };
  var кодер = new TextEncoder(), декодер = new TextDecoder();

  function взять(о) { return о > 0 && о < ручки.length ? ручки[о] : undefined; }
  function выдать(значение) {
    if (значение === undefined || значение === null) return 0;
    ручки.push(значение); return ручки.length - 1;
  }
  function читатьТекст(адрес) {
    var б = new Uint8Array(память.buffer), конец = адрес;
    while (б[конец] !== 0) конец++;
    return декодер.decode(б.subarray(адрес, конец));
  }
  // Текст для программы кладём в кольцевой буфер внутри её памяти: строка живёт, пока не пройдёт круг в 64 КБ.
  function писатьТекст(текст) {
    var байты = кодер.encode(String(текст));
    if (байты.length > кольцо.размер - 2) байты = байты.subarray(0, кольцо.размер - 2);
    if (кольцо.где + байты.length + 1 > кольцо.размер) кольцо.где = 0;
    var адрес = кольцо.начало + кольцо.где;
    var б = new Uint8Array(память.buffer);
    б.set(байты, адрес); б[адрес + байты.length] = 0;
    кольцо.где += байты.length + 1;
    return адрес;
  }
  var результат = 0;
  function ждать(обещание, имя) {
    обещание.then(function (з) {
      var было = ручки.length; результат = выдать(з); вызвать(имя); результат = 0; ручки.length = было;
    });
    return 0;
  }
  function вызвать(имя) {
    var ф = экспорт[имя];
    if (typeof ф === 'function') { try { ф(); } catch (е) { if (!(е && е.выход !== undefined)) console.error('Сфера:', е); } }
    else console.error('Сфера: в программе нет функции «' + имя + '»');
  }

  var хост = {
    'х_глобал': function () { return выдать(window); },
    'х_св': function (о, имя) { var ц = взять(о); if (ц === undefined) return 0; var з; try { з = ц[читатьТекст(имя)]; } catch (е) { return 0; } return выдать(з); },
    'х_уст': function (о, имя, з) { var ц = взять(о); if (ц !== undefined) { try { ц[читатьТекст(имя)] = взять(з); } catch (е) {} } return 0; },
    'х_вызов': function (о, имя, а, б, в) {
      var ц = взять(о); if (ц === undefined) return 0;
      var арг = [взять(а), взять(б), взять(в)];
      while (арг.length && арг[арг.length - 1] === undefined) арг.pop();
      try { var ф = ц[читатьТекст(имя)]; return typeof ф === 'function' ? выдать(ф.apply(ц, арг)) : 0; } catch (е) { return 0; }
    },
    'х_текст': function (адрес) { return выдать(читатьТекст(адрес)); },
    'х_число': function (ч) { return выдать(ч); },
    'х_в_текст': function (о) { var з = взять(о); return писатьТекст(з === undefined ? '' : з); },
    'х_в_число': function (о) { var з = Number(взять(о)); return isNaN(з) ? 0 : з; },
    'х_истина': function (о) { return взять(о) ? 1 : 0; },
    'х_слушать': function (о, событиеИмя, обработчик) {
      var ц = взять(о), имя = читатьТекст(обработчик); if (!ц || !ц.addEventListener) return 0;
      ц.addEventListener(читатьТекст(событиеИмя), function (э) {
        var было = ручки.length, прежнее = событие;
        событие = выдать(э); вызвать(имя); событие = прежнее; ручки.length = было;
      });
      return 0;
    },
    'х_каждые': function (мс, обработчик) {
      var имя = читатьТекст(обработчик);
      setInterval(function () { var было = ручки.length; вызвать(имя); ручки.length = было; }, мс);
      return 0;
    },
    'х_событие': function () { return событие; },
    'х_маяк': function (адрес, тело) {
      try { navigator.sendBeacon(читатьТекст(адрес), new Blob([читатьТекст(тело)], { type: 'application/x-www-form-urlencoded' })); } catch (е) {}
      return 0;
    },
    // Запросы к серверу. Когда ответ готов, браузер вызывает функцию программы; ответ лежит в х_результат().
    'х_получить': function (адрес, обработчик) { return ждать(С.получить(читатьТекст(адрес)), читатьТекст(обработчик)); },
    'х_отправить': function (адрес, тело, обработчик) { return ждать(С.отправить(читатьТекст(адрес), читатьТекст(тело)), читатьТекст(обработчик)); },
    'х_текстом': function (адрес, обработчик) {
      return ждать(fetch(читатьТекст(адрес)).then(function (о) { return о.text(); }), читатьТекст(обработчик));
    },
    'х_хеш': function (имя, пароль, обработчик) {
      return ждать(С.хешПароля(читатьТекст(имя), читатьТекст(пароль)).then(function (х) { return { ok: true, хеш: х }; },
        function (е) { return { ok: false, ошибка: е.message }; }), читатьТекст(обработчик));
    },
    'х_архив': function (файлы, манифест, обработчик) {
      var ф = взять(файлы) || [];
      return ждать(С.собратьАрхив(ф, читатьТекст(манифест)).then(function (д) { return { ok: true, данные: д }; },
        function (е) { return { ok: false, ошибка: е.message }; }), читатьТекст(обработчик));
    },
    'х_опубликовать': function (имя, версия, данные, обработчик) {
      return ждать(С.опубликовать(читатьТекст(имя), читатьТекст(версия), взять(данные)).catch(function (е) { return { ok: false, ошибка: е.message }; }), читатьТекст(обработчик));
    },
    'х_результат': function () { return результат; },
    'х_когда': function (обещание, обработчик) { var п = взять(обещание); return п && п.then ? ждать(п, читатьТекст(обработчик)) : 0; },
    'х_метка': function () { return ручки.length; },
    'х_сбросить': function (м) { if (м > 0 && м <= ручки.length) ручки.length = м; return 0; }
  };

  var wasi = {
    fd_write: function (fd, iovs, n, пишем) {
      var v = new DataView(память.buffer), всего = 0, текст = '';
      for (var i = 0; i < n; i++) {
        var адрес = v.getUint32(iovs + i * 8, true), длина = v.getUint32(iovs + i * 8 + 4, true);
        текст += декодер.decode(new Uint8Array(память.buffer, адрес, длина)); всего += длина;
      }
      if (текст.trim()) console.log(текст.replace(/\n$/, ''));
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

  fetch('/статика/клиент/' + encodeURIComponent(модуль) + '.wasm', { cache: 'no-cache' })
    .then(function (о) {
      if (!о.ok) throw new Error('сборка недоступна (' + о.status + ')');
      return о.arrayBuffer();
    })
    .then(function (байты) { return WebAssembly.compile(байты); })
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
      var страниц = 1, старые = память.grow(страниц);
      кольцо.начало = старые * 65536; кольцо.размер = страниц * 65536; кольцо.где = 0;
      try { экспорт._start(); } catch (е) { if (!(е && е.выход !== undefined)) throw е; }
    })
    .catch(function (е) { console.warn('Сфера: ' + модуль + ' не запустился, включаю запасной скрипт.', е); запасной(номер); });
  }
})();
