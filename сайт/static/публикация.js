/* Публикация пакета со страницы сайта: собираем архив .tar.gz прямо в браузере и отправляем на сервер. */
document.addEventListener('DOMContentLoaded', function () {
  'use strict';
  var $ = function (id) { return document.getElementById(id); };
  var С = window.Сфера;
  if (!С || !$('пуб-форма')) return;
  var файлы = [];
  var МАКС = 5 * 1024 * 1024;

  function допустимоИмяВАрхиве(имя) {
    if (имя.indexOf('/') >= 0 || имя.indexOf('\\') >= 0 || имя.indexOf('..') >= 0 || имя[0] === '.') return false;
    if (имя === 'пакет.сфера' || имя === 'сфера.зависимости' || имя === 'LICENSE') return true;
    return /\.код$/.test(имя) || /\.md$/.test(имя);
  }

  function сообщить(текст, хорошо) {
    var э = $('пуб-сообщение'); э.textContent = текст; э.className = 'акк-сообщение' + (хорошо ? ' хорошо' : '');
  }

  function ключ(т, к) { var м = new RegExp('^' + к + '\\s*=\\s*(.*)$', 'm').exec(т); return м ? м[1].trim() : ''; }

  function показать() {
    var список = $('пуб-список'); список.textContent = '';
    файлы.forEach(function (ф) {
      var li = document.createElement('li');
      li.textContent = ф.name + ' (' + Math.max(1, Math.round(ф.size / 1024)) + ' КБ)' + (допустимоИмяВАрхиве(ф.name) || /\.tar\.gz$/.test(ф.name) ? '' : ' — такой файл в пакет не входит, он будет пропущен');
      список.appendChild(li);
    });
    $('пуб-дроп-текст').textContent = файлы.length ? 'Выбрано файлов: ' + файлы.length : 'Перетащите файлы сюда или нажмите, чтобы выбрать';
    // Подставить поля из пакет.сфера, если он среди файлов.
    var м = файлы.filter(function (ф) { return ф.name === 'пакет.сфера'; })[0];
    if (м) {
      м.text().then(function (т) {
        if (ключ(т, 'имя') && !$('пуб-имя').value) $('пуб-имя').value = ключ(т, 'имя');
        if (ключ(т, 'версия')) $('пуб-версия').value = ключ(т, 'версия');
        if (ключ(т, 'описание') && !$('пуб-описание').value) $('пуб-описание').value = ключ(т, 'описание');
        if (ключ(т, 'лицензия')) $('пуб-лицензия').value = ключ(т, 'лицензия');
      });
    }
  }

  function добавить(список) {
    файлы = Array.prototype.slice.call(список);
    показать();
  }

  $('пуб-файлы').addEventListener('change', function () { добавить(this.files); });
  var дроп = $('пуб-дроп');
  ['dragenter', 'dragover'].forEach(function (с) { дроп.addEventListener(с, function (e) { e.preventDefault(); дроп.classList.add('над'); }); });
  ['dragleave', 'drop'].forEach(function (с) { дроп.addEventListener(с, function (e) { e.preventDefault(); дроп.classList.remove('над'); }); });
  дроп.addEventListener('drop', function (e) { if (e.dataTransfer && e.dataTransfer.files.length) добавить(e.dataTransfer.files); });

  /* ---- tar + gzip ---- */
  function байты(с) { return new TextEncoder().encode(с); }
  function писать(буфер, смещение, текст) { var б = байты(текст); буфер.set(б, смещение); }
  function заголовокTar(имя, размер) {
    var ш = new Uint8Array(512), имяБ = байты(имя);
    if (имяБ.length > 100) throw new Error('Имя файла «' + имя + '» слишком длинное');
    ш.set(имяБ, 0);
    писать(ш, 100, '0000644\0'); писать(ш, 108, '0000000\0'); писать(ш, 116, '0000000\0');
    писать(ш, 124, размер.toString(8).padStart(11, '0') + '\0');
    писать(ш, 136, Math.floor(Date.now() / 1000).toString(8).padStart(11, '0') + '\0');
    писать(ш, 148, '        ');
    писать(ш, 156, '0');
    писать(ш, 257, 'ustar\0'); писать(ш, 263, '00');
    var сумма = 0; for (var i = 0; i < 512; i++) сумма += ш[i];
    писать(ш, 148, сумма.toString(8).padStart(6, '0') + '\0 ');
    return ш;
  }
  function собратьTar(записи) {
    var части = [], всего = 0;
    записи.forEach(function (з) {
      var г = заголовокTar(з.имя, з.данные.length); части.push(г); части.push(з.данные);
      var хвост = (512 - (з.данные.length % 512)) % 512; if (хвост) части.push(new Uint8Array(хвост));
    });
    части.push(new Uint8Array(1024));
    части.forEach(function (ч) { всего += ч.length; });
    var итог = new Uint8Array(всего), п = 0;
    части.forEach(function (ч) { итог.set(ч, п); п += ч.length; });
    return итог;
  }
  function сжать(данные) {
    if (!window.CompressionStream) return Promise.reject(new Error('Браузер не умеет сжимать архивы. Обновите его или загрузите готовый .tar.gz.'));
    return new Response(new Blob([данные]).stream().pipeThrough(new CompressionStream('gzip'))).arrayBuffer();
  }

  function отправить(имя, версия, тело) {
    return fetch('/пакеты/публикация/' + encodeURIComponent(имя) + '/' + encodeURIComponent(версия), {
      method: 'PUT', headers: { 'X-Sfera': '1', 'Content-Type': 'application/gzip' }, body: тело
    }).then(function (о) { return о.json().catch(function () { return { ok: false, ошибка: 'Сервер ответил не так, как ожидалось' }; }); });
  }

  $('пуб-кнопка').addEventListener('click', function () {
    var имя = $('пуб-имя').value.trim(), версия = $('пуб-версия').value.trim(), описание = $('пуб-описание').value.trim(), лицензия = $('пуб-лицензия').value.trim();
    if (!файлы.length) { сообщить('Выберите файлы пакета.'); return; }
    if (!имя) { сообщить('Укажите название пакета.'); return; }
    if (!/^\d+\.\d+\.\d+$/.test(версия)) { сообщить('Версия должна быть вида 1.0.0.'); return; }
    var готовый = файлы.filter(function (ф) { return /\.tar\.gz$/.test(ф.name); })[0];
    сообщить('Готовлю архив…', true);
    var подготовка;
    if (готовый) {
      if (готовый.size > МАКС) { сообщить('Архив больше 5 МБ.'); return; }
      подготовка = готовый.arrayBuffer();
    } else {
      if (!описание) { сообщить('Напишите описание пакета.'); return; }
      var нужные = файлы.filter(function (ф) { return ф.name !== 'пакет.сфера' && допустимоИмяВАрхиве(ф.name); });
      if (!нужные.some(function (ф) { return /\.код$/.test(ф.name); })) { сообщить('В пакете нужен хотя бы один файл .код.'); return; }
      var манифест = 'имя = ' + имя + '\nверсия = ' + версия + '\nописание = ' + описание.replace(/[\r\n]+/g, ' ') + '\nлицензия = ' + (лицензия || 'MIT') + '\n';
      подготовка = Promise.all(нужные.map(function (ф) { return ф.arrayBuffer().then(function (б) { return { имя: ф.name, данные: new Uint8Array(б) }; }); })).then(function (записи) {
        записи.unshift({ имя: 'пакет.сфера', данные: байты(манифест) });
        var сумма = 0; записи.forEach(function (з) { сумма += з.данные.length; });
        if (сумма > МАКС) throw new Error('Файлы пакета больше 5 МБ.');
        return сжать(собратьTar(записи));
      });
    }
    подготовка.then(function (архив) { сообщить('Отправляю…', true); return отправить(имя, версия, архив); }).then(function (о) {
      if (о.ok) { сообщить('Готово: «' + имя + '» ' + версия + ' опубликован. Пока он «непроверенный». Он появится в каталоге: /пакеты/' + имя, true); }
      else { сообщить(о.ошибка || 'Не получилось опубликовать.'); }
    }).catch(function (e) { сообщить(e.message); });
  });

  С.кто().then(function (я) {
    if (я && я.вошёл) { $('пуб-форма-блок').hidden = false; } else { $('пуб-гость').hidden = false; }
  });
});
