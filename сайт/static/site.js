/* Общие компоненты сайта: вкладки с боковым списком и всплывающие «облачка». Без библиотек. */
(function () {
  'use strict';

  /* ---------- вкладки: <div data-вкладки> кнопки [data-вкладка="id"], панели [data-панель="id"] ---------- */
  function вкладки(корень) {
    var кнопки = [].slice.call(корень.querySelectorAll('[data-вкладка]'));
    var панели = [].slice.call(корень.querySelectorAll('[data-панель]'));
    function показать(id, фокус) {
      кнопки.forEach(function (к) {
        var активна = к.getAttribute('data-вкладка') === id;
        к.setAttribute('aria-selected', активна ? 'true' : 'false');
        к.tabIndex = активна ? 0 : -1;
        if (активна && фокус) к.focus();
      });
      панели.forEach(function (п) { п.hidden = п.getAttribute('data-панель') !== id; });
    }
    кнопки.forEach(function (к, i) {
      к.addEventListener('click', function () { показать(к.getAttribute('data-вкладка')); });
      к.addEventListener('keydown', function (e) {
        var сдвиг = e.key === 'ArrowDown' || e.key === 'ArrowRight' ? 1 : e.key === 'ArrowUp' || e.key === 'ArrowLeft' ? -1 : 0;
        if (!сдвиг) return;
        e.preventDefault();
        var следующая = кнопки[(i + сдвиг + кнопки.length) % кнопки.length];
        показать(следующая.getAttribute('data-вкладка'), true);
      });
    });
    var первая = кнопки.filter(function (к) { return к.getAttribute('aria-selected') === 'true'; })[0] || кнопки[0];
    if (первая) показать(первая.getAttribute('data-вкладка'));
  }
  document.querySelectorAll('[data-вкладки]').forEach(вкладки);

  /* ---------- облачко: на телефоне выезжает снизу, на компьютере по центру ---------- */
  var подложка = null, предыдущийФокус = null;
  function закрыть() {
    if (!подложка) return;
    подложка.remove(); подложка = null;
    document.body.classList.remove('облако-открыто');
    document.removeEventListener('keydown', клавиши);
    if (предыдущийФокус && предыдущийФокус.focus) предыдущийФокус.focus();
  }
  function клавиши(e) {
    if (e.key === 'Escape') { закрыть(); return; }
    if (e.key !== 'Tab' || !подложка) return;
    var фокусируемые = подложка.querySelectorAll('a[href],button,input,select,textarea,[tabindex]:not([tabindex="-1"])');
    if (!фокусируемые.length) return;
    var первый = фокусируемые[0], последний = фокусируемые[фокусируемые.length - 1];
    if (e.shiftKey && document.activeElement === первый) { e.preventDefault(); последний.focus(); }
    else if (!e.shiftKey && document.activeElement === последний) { e.preventDefault(); первый.focus(); }
  }
  /* открыть(заголовок, узелИлиHtml): html должен быть доверенным (у нас — только своя разметка или экранированный текст) */
  function открыть(заголовок, содержимое) {
    закрыть();
    предыдущийФокус = document.activeElement;
    подложка = document.createElement('div');
    подложка.className = 'облако-фон';
    var окно = document.createElement('div');
    окно.className = 'облако';
    окно.setAttribute('role', 'dialog');
    окно.setAttribute('aria-modal', 'true');
    окно.setAttribute('aria-label', заголовок);
    var шапка = document.createElement('div');
    шапка.className = 'облако-шапка';
    var h = document.createElement('h2'); h.textContent = заголовок;
    var крестик = document.createElement('button');
    крестик.type = 'button'; крестик.className = 'облако-закрыть'; крестик.setAttribute('aria-label', 'Закрыть'); крестик.textContent = '×';
    крестик.addEventListener('click', закрыть);
    шапка.appendChild(h); шапка.appendChild(крестик);
    var тело = document.createElement('div');
    тело.className = 'облако-тело';
    if (typeof содержимое === 'string') тело.innerHTML = содержимое; else if (содержимое) тело.appendChild(содержимое);
    окно.appendChild(шапка); окно.appendChild(тело);
    подложка.appendChild(окно);
    подложка.addEventListener('mousedown', function (e) { if (e.target === подложка) закрыть(); });
    document.body.appendChild(подложка);
    document.body.classList.add('облако-открыто');
    document.addEventListener('keydown', клавиши);
    крестик.focus();
  }
  window.Облако = { открыть: открыть, закрыть: закрыть };

  /* Кнопка с data-облако="id" открывает содержимое элемента <template id="id"> (заголовок берётся из data-заголовок). */
  document.addEventListener('click', function (e) {
    var к = e.target.closest && e.target.closest('[data-облако]');
    if (!к) return;
    var шаблон = document.getElementById(к.getAttribute('data-облако'));
    if (!шаблон) return;
    e.preventDefault();
    var узел = шаблон.content ? шаблон.content.cloneNode(true) : null;
    открыть(к.getAttribute('data-заголовок') || к.textContent.trim(), узел);
  });
})();
