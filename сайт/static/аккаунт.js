/* Аккаунты: вход, регистрация, профиль и ссылка в шапке сайта. Пароль хешируется здесь и на сервер не уходит. */
(function () {
  'use strict';
  var $ = function (id) { return document.getElementById(id); };

  function шестнадцатеричное(буфер) {
    return Array.prototype.map.call(new Uint8Array(буфер), function (б) { return ('0' + б.toString(16)).slice(-2); }).join('');
  }

  window.Сфера = window.Сфера || {};
  var С = window.Сфера;

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
    var тело = new URLSearchParams(поля || {}).toString();
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

  // Ссылка в шапке: «Войти» или имя вошедшего.
  var шапка = $('шапка-аккаунт');
  if (шапка) {
    С.кто().then(function (я) {
      if (я && я.вошёл) { шапка.textContent = я.имя; шапка.title = 'Профиль: ' + (С.роли[я.роль] || я.роль); }
    });
  }

  /* ---- страница «Аккаунт» ---- */
  var гость = $('акк-гость'), профиль = $('акк-профиль');
  if (!гость || !профиль) return;

  function сообщить(где, текст, хорошо) {
    var э = $(где); if (!э) return;
    э.textContent = текст; э.className = 'акк-сообщение' + (хорошо ? ' хорошо' : '');
  }

  function показатьПрофиль(я) {
    гость.hidden = true; профиль.hidden = false;
    $('акк-имя').textContent = я.имя;
    $('акк-роль').textContent = С.роли[я.роль] || я.роль;
    $('акк-роль').className = 'роль-метка роль-' + я.роль;
    С.получить('/аккаунт/токен').then(function (о) { if (о.ok) { $('акк-токен').value = о.токен; } });
    fetch('/пакеты/реестр.txt').then(function (о) { return о.text(); }).then(function (т) {
      var мои = {}, порядок = [];
      т.split('\n').forEach(function (с) {
        if (!с.trim() || с.trim()[0] === '#') return;
        var п = с.split('|').map(function (x) { return x.trim(); });
        if (п[5] === я.имя) { if (!мои[п[0]]) { мои[п[0]] = []; порядок.push(п[0]); } мои[п[0]].push(п[1]); }
      });
      var список = $('акк-пакеты');
      список.textContent = '';
      if (!порядок.length) { список.innerHTML = '<li class="muted">Вы пока ничего не публиковали.</li>'; return; }
      порядок.forEach(function (имя) {
        var li = document.createElement('li'), a = document.createElement('a');
        a.href = '/пакеты/' + encodeURIComponent(имя); a.textContent = имя;
        li.appendChild(a); li.appendChild(document.createTextNode(' — версии: ' + мои[имя].join(', ')));
        список.appendChild(li);
      });
    });
  }

  function показатьГостя() { гость.hidden = false; профиль.hidden = true; }

  С.кто().then(function (я) { if (я && я.вошёл) показатьПрофиль(я); else показатьГостя(); });

  function войтиИлиЗарегистрироваться(путь, имяПоля, паролеПоле, сообщениеГде) {
    var имя = $(имяПоля).value.trim(), пароль = $(паролеПоле).value;
    if (имя.length < 3) { сообщить(сообщениеГде, 'Имя: не короче трёх знаков.'); return; }
    if (пароль.length < 8) { сообщить(сообщениеГде, 'Пароль: не короче восьми знаков.'); return; }
    if (путь === '/аккаунт/регистрация' && пароль !== $('рег-пароль2').value) { сообщить(сообщениеГде, 'Пароли не совпадают.'); return; }
    сообщить(сообщениеГде, 'Проверяю…', true);
    С.хешПароля(имя, пароль).then(function (хеш) { return С.отправить(путь, { имя: имя, пароль: хеш }); }).then(function (о) {
      if (о.ok) { С._кто = null; location.reload(); } else { сообщить(сообщениеГде, о.ошибка || 'Не получилось.'); }
    }).catch(function (e) { сообщить(сообщениеГде, e.message); });
  }

  $('вход-форма').addEventListener('submit', function (e) { e.preventDefault(); войтиИлиЗарегистрироваться('/аккаунт/вход', 'вход-имя', 'вход-пароль', 'вход-сообщение'); });
  $('рег-форма').addEventListener('submit', function (e) { e.preventDefault(); войтиИлиЗарегистрироваться('/аккаунт/регистрация', 'рег-имя', 'рег-пароль', 'рег-сообщение'); });
  $('акк-выход').addEventListener('click', function () { С.отправить('/аккаунт/выход').then(function () { С._кто = null; location.href = '/аккаунт'; }); });
  $('токен-показать').addEventListener('click', function () {
    var п = $('акк-токен'); п.type = п.type === 'password' ? 'text' : 'password';
    this.textContent = п.type === 'password' ? 'Показать' : 'Скрыть';
  });
  $('токен-копия').addEventListener('click', function () {
    var п = $('акк-токен'); if (navigator.clipboard) navigator.clipboard.writeText(п.value).then(function () { сообщить('токен-сообщение', 'Скопировано.', true); });
  });
  $('токен-новый').addEventListener('click', function () {
    if (!confirm('Выдать новый токен? Старый перестанет работать, в терминале придётся снова выполнить «сфера войти».')) return;
    С.отправить('/аккаунт/токен/новый').then(function (о) {
      if (о.ok) { $('акк-токен').value = о.токен; сообщить('токен-сообщение', 'Выдан новый токен.', true); } else сообщить('токен-сообщение', о.ошибка || 'Не получилось.');
    });
  });
  Array.prototype.forEach.call(document.querySelectorAll('[data-вкладка]'), function (к) {
    к.addEventListener('click', function () {
      var ц = к.getAttribute('data-вкладка');
      $('вход-форма').hidden = ц !== 'вход'; $('рег-форма').hidden = ц !== 'рег';
      Array.prototype.forEach.call(document.querySelectorAll('[data-вкладка]'), function (д) { д.classList.toggle('secondary', д !== к); });
    });
  });
})();
