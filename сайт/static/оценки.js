/* Звёзды, комментарии и модерация пакетов. */
(function () {
  'use strict';
  var С = window.Сфера || (window.Сфера = {});
  function э(т, к, текст) { var e = document.createElement(т); if (к) e.className = к; if (текст != null) e.textContent = текст; return e; }
  function дата(с) { var н = parseInt(с, 10); return isNaN(н) ? '' : new Date(н * 1000).toLocaleString('ru-RU'); }
  var ярлык = { 'проверен': 'проверен', 'нежелательный': 'нежелательный', 'непроверен': 'непроверенный' };

  function ждать(ф) { if (С.получить) ф(); else setTimeout(function () { ждать(ф); }, 50); }

  /* ---- страница пакета ---- */
  var секция = document.getElementById('оценки');
  if (секция) ждать(function () { пакет(секция); });

  function пакет(корень) {
    var имя = корень.getAttribute('data-пакет');
    function загрузить() {
      С.получить('/оценки/пакет/' + encodeURIComponent(имя)).then(рисовать);
    }
    function рисовать(д) {
      корень.textContent = '';
      if (!д || !д.ok) { return; }
      var мод = д.роль === 'модератор' || д.роль === 'админ';
      корень.appendChild(э('h3', null, 'Оценки и комментарии'));
      var строка = э('p', 'оценки-строка');
      var зв = э('button', 'button small ' + (д.моя ? '' : 'secondary'), (д.моя ? '★ ' : '☆ ') + д.звёзды);
      зв.type = 'button'; зв.title = д.вошёл ? 'Поставить или снять звезду' : 'Войдите, чтобы поставить звезду';
      зв.onclick = function () {
        if (!д.вошёл) { location.href = '/аккаунт'; return; }
        С.отправить('/оценки/звезда', { имя: имя }).then(function (о) { if (!о.ok) сообщ(о.ошибка); загрузить(); });
      };
      строка.appendChild(зв);
      var ст = э('span', 'метка-статуса статус-' + д.статус, ярлык[д.статус] || д.статус);
      строка.appendChild(ст);
      корень.appendChild(строка);

      if (мод) {
        var п = э('p', 'оценки-мод');
        п.appendChild(э('span', 'muted', 'Модерация: '));
        [['проверен', 'Проверен'], ['нежелательный', 'Нежелательный'], ['непроверен', 'Непроверенный']].forEach(function (в) {
          var к = э('button', 'button small secondary', в[1]); к.type = 'button';
          к.onclick = function () { С.отправить('/оценки/статус', { имя: имя, статус: в[0] }).then(function (о) { if (!о.ok) сообщ(о.ошибка); загрузить(); }); };
          п.appendChild(к);
        });
        if (д.роль === 'админ') {
          var у = э('button', 'button small опасно', 'Удалить пакет'); у.type = 'button';
          у.onclick = function () {
            if (!confirm('Удалить пакет «' + имя + '» со всеми версиями и комментариями? Это нельзя отменить.')) return;
            С.отправить('/оценки/пакет/удалить', { имя: имя }).then(function (о) { if (о.ok) location.href = '/пакеты'; else сообщ(о.ошибка); });
          };
          п.appendChild(у);
        }
        корень.appendChild(п);
      }

      var список = э('div', 'комментарии');
      if (!д.комментарии.length) список.appendChild(э('p', 'muted', 'Комментариев пока нет. Если вы пробовали пакет, расскажите, как он работает.'));
      д.комментарии.forEach(function (к) {
        var б = э('div', 'комментарий');
        var ш = э('div', 'комментарий-шапка');
        ш.appendChild(э('b', null, к.автор));
        ш.appendChild(э('span', 'muted', ' ' + дата(к.время)));
        if (д.вошёл && (к.автор === д.вошёл || мод)) {
          var х = э('button', 'комментарий-удалить', 'удалить'); х.type = 'button';
          х.onclick = function () { С.отправить('/оценки/комментарий/удалить', { номер: к.номер }).then(function (о) { if (!о.ok) сообщ(о.ошибка); загрузить(); }); };
          ш.appendChild(х);
        }
        б.appendChild(ш); б.appendChild(э('p', null, к.текст)); список.appendChild(б);
      });
      корень.appendChild(список);

      if (д.вошёл) {
        var ф = э('form', 'комментарий-форма');
        var т = document.createElement('textarea'); т.maxLength = 1000; т.rows = 3; т.placeholder = 'Ваш комментарий (до 1000 знаков). Если пакет опасен или ведёт себя странно, напишите об этом.';
        var к = э('button', 'button small', 'Отправить'); к.type = 'submit';
        ф.appendChild(т); ф.appendChild(к);
        ф.onsubmit = function (с) {
          с.preventDefault();
          if (!т.value.trim()) return;
          С.отправить('/оценки/комментарий', { имя: имя, текст: т.value }).then(function (о) { if (о.ok) загрузить(); else сообщ(о.ошибка); });
        };
        корень.appendChild(ф);
      } else {
        var г = э('p', 'muted'); г.appendChild(document.createTextNode('Чтобы ставить звёзды и писать комментарии, '));
        var а = э('a', null, 'войдите в аккаунт'); а.href = '/аккаунт'; г.appendChild(а); г.appendChild(document.createTextNode('.'));
        корень.appendChild(г);
      }
      корень.appendChild(э('p', 'акк-сообщение', '')).id = 'оценки-сообщение';
    }
    function сообщ(т) { var м = document.getElementById('оценки-сообщение'); if (м) м.textContent = т || ''; }
    загрузить();
  }

  /* ---- страница модерации ---- */
  var таблица = document.getElementById('мод-таблица');
  if (таблица) ждать(function () { модерация(таблица); });

  function модерация(т) {
    var фильтр = 'все', данные = [], роль = '';
    function сообщ(х) { document.getElementById('мод-сообщение').textContent = х || ''; }
    function рисовать() {
      т.textContent = '';
      var шапка = э('tr');
      ['Пакет', 'Автор', 'Статус', '★', '💬', ''].forEach(function (з) { шапка.appendChild(э('th', null, з)); });
      т.appendChild(шапка);
      var есть = false;
      данные.forEach(function (п) {
        if (фильтр !== 'все' && п.статус !== фильтр) return;
        есть = true;
        var р = э('tr');
        var я1 = э('td'); var а = э('a', null, п.имя); а.href = '/пакеты/' + encodeURIComponent(п.имя); я1.appendChild(а);
        я1.appendChild(э('br')); я1.appendChild(э('span', 'muted', п.версия + ' · ' + дата(п.время))); р.appendChild(я1);
        р.appendChild(э('td', null, п.автор));
        var я3 = э('td'); я3.appendChild(э('span', 'метка-статуса статус-' + п.статус, ярлык[п.статус] || п.статус)); р.appendChild(я3);
        р.appendChild(э('td', null, String(п.звёзды)));
        р.appendChild(э('td', null, String(п.комментарии)));
        var я6 = э('td', 'действия');
        [['проверен', '✓'], ['нежелательный', '⚠'], ['непроверен', '↺']].forEach(function (в) {
          var к = э('button', 'button small secondary', в[1]); к.type = 'button';
          к.title = { 'проверен': 'Отметить «проверен»', 'нежелательный': 'Отметить «нежелательный»', 'непроверен': 'Вернуть «непроверенный»' }[в[0]];
          к.onclick = function () { С.отправить('/оценки/статус', { имя: п.имя, статус: в[0] }).then(function (о) { if (о.ok) загрузить(); else сообщ(о.ошибка); }); };
          я6.appendChild(к);
        });
        if (роль === 'админ') {
          var у = э('button', 'button small опасно', '🗑'); у.type = 'button'; у.title = 'Удалить пакет';
          у.onclick = function () {
            if (!confirm('Удалить пакет «' + п.имя + '» совсем?')) return;
            С.отправить('/оценки/пакет/удалить', { имя: п.имя }).then(function (о) { if (о.ok) загрузить(); else сообщ(о.ошибка); });
          };
          я6.appendChild(у);
        }
        р.appendChild(я6); т.appendChild(р);
      });
      if (!есть) { var р2 = э('tr'); var я = э('td', 'muted', 'Здесь пока пусто.'); я.colSpan = 6; р2.appendChild(я); т.appendChild(р2); }
    }
    function загрузить() {
      С.получить('/оценки/модерация').then(function (д) {
        if (!Array.isArray(д)) return;
        данные = д; рисовать();
      });
    }
    Array.prototype.forEach.call(document.querySelectorAll('[data-фильтр]'), function (к) {
      к.onclick = function () { фильтр = к.getAttribute('data-фильтр'); рисовать(); };
    });
    С.кто().then(function (я) {
      if (!я || !я.вошёл || (я.роль !== 'модератор' && я.роль !== 'админ')) { document.getElementById('мод-запрет').hidden = false; return; }
      роль = я.роль; document.getElementById('мод-блок').hidden = false; загрузить();
    });
  }
})();
