/* Шапка сайта: ссылки, которые не поместились по ширине, уходят в меню «Ещё».
   Справа всегда остаются «Ещё», «Скачать» и профиль. Без скрипта шапка просто показывает все ссылки. */
(function () {
  'use strict';
  var нав = document.getElementById('шапка-нав');
  var кнопка = document.getElementById('шапка-ещё-кнопка');
  var меню = document.getElementById('шапка-ещё-меню');
  var лишние = document.getElementById('шапка-лишние');
  var действия = document.querySelector('.header-actions');
  if (!нав || !кнопка || !меню || !лишние) return;

  var ссылки = Array.prototype.slice.call(нав.querySelectorAll('a'));
  var копии = ссылки.map(function (а) {
    var к = а.cloneNode(true);
    к.hidden = true;
    лишние.appendChild(к);
    return к;
  });
  var черта = document.createElement('div');
  черта.className = 'ещё-черта';
  черта.hidden = true;
  лишние.appendChild(черта);

  function подогнать() {
    ссылки.forEach(function (а) { а.hidden = false; });
    копии.forEach(function (к) { к.hidden = true; });
    var i = ссылки.length;
    while (i > 0 && нав.scrollWidth > нав.clientWidth + 1) {
      i--;
      ссылки[i].hidden = true;
      копии[i].hidden = false;
    }
    черта.hidden = i === ссылки.length;
  }

  function закрыть() { меню.hidden = true; кнопка.setAttribute('aria-expanded', 'false'); }
  кнопка.addEventListener('click', function (с) {
    с.stopPropagation();
    var открыто = меню.hidden;
    меню.hidden = !открыто;
    кнопка.setAttribute('aria-expanded', открыто ? 'true' : 'false');
  });
  document.addEventListener('click', function (с) { if (!меню.contains(с.target)) закрыть(); });
  document.addEventListener('keydown', function (с) { if (с.key === 'Escape') { закрыть(); кнопка.focus(); } });

  // «Модерация» для модераторов добавляет скрипт аккаунта прямо в шапку: переносим её в «Ещё».
  function забратьМодерацию() {
    if (!действия) return;
    var м = действия.querySelector('a[href="/пакеты/модерация"]');
    if (м && м.parentNode === действия) {
      м.className = '';
      m_вставить(м);
    }
  }
  function m_вставить(м) {
    меню.insertBefore(м, меню.lastElementChild);
  }
  if (действия && window.MutationObserver) {
    new MutationObserver(забратьМодерацию).observe(действия, { childList: true });
  }

  подогнать();
  if (window.ResizeObserver) {
    new ResizeObserver(подогнать).observe(document.querySelector('.site-header .wrap'));
  } else {
    window.addEventListener('resize', подогнать);
  }
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(подогнать);
  window.addEventListener('load', подогнать);

  // Боковое меню документации на узких экранах свёрнуто.
  var док = document.querySelector('details.док-меню');
  if (док && window.innerWidth < 900) док.removeAttribute('open');
})();
