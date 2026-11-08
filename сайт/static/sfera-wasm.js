// Запуск программ Сферы в браузере. Сервер собирает код в WebAssembly (POST /площадка/собрать),
// а выполняет его этот загрузчик в отдельном потоке (Web Worker): зависшая программа не повесит страницу.
// Позже этот загрузчик заменим на программу на самой Сфере.
(function () {
  var воркер = function () {
    self.onmessage = function (e) {
      var байты = e.data.wasm, ввод = new TextEncoder().encode(e.data.ввод || ''), позВвода = 0;
      var память = null, кодировать = new TextEncoder(), декод = new TextDecoder();
      var выходКод = 0;
      function порция(текст, поток) { self.postMessage({ вывод: текст, поток: поток }); }
      function view() { return new DataView(память.buffer); }
      var wasi = {
        fd_write: function (fd, iovs, n, пишем) {
          var v = view(), всего = 0, части = '';
          for (var i = 0; i < n; i++) {
            var адрес = v.getUint32(iovs + i * 8, true), длина = v.getUint32(iovs + i * 8 + 4, true);
            части += декод.decode(new Uint8Array(память.buffer, адрес, длина), { stream: true });
            всего += длина;
          }
          if (fd === 1 || fd === 2) порция(части, fd);
          v.setUint32(пишем, всего, true); return 0;
        },
        fd_read: function (fd, iovs, n, читаем) {
          var v = view(), всего = 0;
          if (fd !== 0) { v.setUint32(читаем, 0, true); return 8; }
          for (var i = 0; i < n; i++) {
            var адрес = v.getUint32(iovs + i * 8, true), длина = v.getUint32(iovs + i * 8 + 4, true);
            var сколько = Math.min(длина, ввод.length - позВвода);
            new Uint8Array(память.buffer, адрес, сколько).set(ввод.subarray(позВвода, позВвода + сколько));
            позВвода += сколько; всего += сколько;
            if (сколько < длина) break;
          }
          v.setUint32(читаем, всего, true); return 0;
        },
        fd_close: function () { return 0; },
        fd_seek: function () { return 70; },
        fd_fdstat_get: function (fd, p) { var v = view(); v.setUint8(p, fd < 3 ? 2 : 4); v.setUint16(p + 2, 0, true); v.setBigUint64(p + 8, 0n, true); v.setBigUint64(p + 16, 0n, true); return 0; },
        fd_fdstat_set_flags: function () { return 0; },
        fd_prestat_get: function () { return 8; },
        fd_prestat_dir_name: function () { return 8; },
        path_open: function () { return 44; },
        path_filestat_get: function () { return 44; },
        path_unlink_file: function () { return 44; },
        path_rename: function () { return 44; },
        path_create_directory: function () { return 44; },
        args_sizes_get: function (a, b) { var v = view(); v.setUint32(a, 0, true); v.setUint32(b, 0, true); return 0; },
        args_get: function () { return 0; },
        environ_sizes_get: function (a, b) { var v = view(); v.setUint32(a, 0, true); v.setUint32(b, 0, true); return 0; },
        environ_get: function () { return 0; },
        clock_time_get: function (id, точность, пишем) { view().setBigUint64(пишем, BigInt(Math.round((id === 0 ? Date.now() : performance.now() + performance.timeOrigin) * 1e6)), true); return 0; },
        clock_res_get: function (id, пишем) { view().setBigUint64(пишем, 1000000n, true); return 0; },
        random_get: function (p, n) { crypto.getRandomValues(new Uint8Array(память.buffer, p, n)); return 0; },
        sched_yield: function () { return 0; },
        poll_oneoff: function () { return 58; },
        proc_exit: function (код) { выходКод = код; throw { выход: код }; }
      };
      WebAssembly.instantiate(байты, { wasi_snapshot_preview1: wasi }).then(function (р) {
        память = р.instance.exports.memory;
        try { р.instance.exports._start(); } catch (е) {
          if (!(е && typeof е.выход === 'number')) { self.postMessage({ ошибка: String(е && е.message || е) }); return; }
        }
        self.postMessage({ конец: выходКод });
      }).catch(function (е) { self.postMessage({ ошибка: String(е && е.message || е) }); });
    };
  };

  var рабочий = null;
  window.запуститьСферу = function (исходник, ввод, обратные) {
    // обратные: статус(текст), вывод(текст, поток), ошибка(текст), конец(код)
    if (рабочий) { рабочий.terminate(); рабочий = null; }
    обратные.статус('Собираю…');
    fetch('/площадка/собрать', { method: 'POST', headers: { 'Content-Type': 'text/plain; charset=utf-8' }, body: исходник })
      .then(function (р) {
        var тип = р.headers.get('Content-Type') || '';
        if (тип.indexOf('application/wasm') === 0) return р.arrayBuffer();
        return р.json().then(function (о) { throw new Error(о['ошибка'] || ('Ошибка ' + р.status)); });
      })
      .then(function (wasm) {
        обратные.статус('Работает…');
        var блоб = new Blob(['(' + воркер.toString() + ')()'], { type: 'text/javascript' });
        рабочий = new Worker(URL.createObjectURL(блоб));
        var таймер = setTimeout(function () { if (рабочий) { рабочий.terminate(); рабочий = null; обратные.ошибка('Программа работала дольше 10 секунд, остановили.'); } }, 10000);
        рабочий.onmessage = function (e) {
          var д = e.data;
          if (д.вывод !== undefined) обратные.вывод(д.вывод, д.поток);
          else if (д.ошибка) { clearTimeout(таймер); обратные.ошибка(д.ошибка); if (рабочий) { рабочий.terminate(); рабочий = null; } }
          else if (д.конец !== undefined) { clearTimeout(таймер); обратные.конец(д.конец); if (рабочий) { рабочий.terminate(); рабочий = null; } }
        };
        рабочий.postMessage({ wasm: wasm, ввод: ввод }, [wasm]);
      })
      .catch(function (е) { обратные.ошибка(е.message); });
  };
  window.остановитьСферу = function () { if (рабочий) { рабочий.terminate(); рабочий = null; } };
})();
