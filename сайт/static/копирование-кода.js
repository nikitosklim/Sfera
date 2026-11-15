// Кнопка «Копировать» у каждого блока кода на страницах сайта (документация, уроки, пакеты).
(function () {
  'use strict';
  function текстБлока(pre) {
    return pre.innerText.replace(/\n$/, '');
  }
  function скопировать(текст) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(текст);
    }
    return new Promise(function (ok, err) {
      var поле = document.createElement('textarea');
      поле.value = текст;
      поле.setAttribute('readonly', '');
      поле.style.cssText = 'position:fixed;left:-9999px;top:0';
      document.body.appendChild(поле);
      поле.select();
      try { document.execCommand('copy') ? ok() : err(); } catch (e) { err(e); }
      document.body.removeChild(поле);
    });
  }
  function добавить(pre) {
    if (pre.dataset.копия || pre.closest('.код-блок') || pre.closest('.codewin')) return;
    pre.dataset.копия = '1';
    var обёртка = document.createElement('div');
    обёртка.className = 'код-блок';
    pre.parentNode.insertBefore(обёртка, pre);
    обёртка.appendChild(pre);
    var кнопка = document.createElement('button');
    кнопка.type = 'button';
    кнопка.className = 'копировать';
    кнопка.textContent = 'Копировать';
    кнопка.setAttribute('aria-label', 'Скопировать код');
    var таймер = 0;
    кнопка.addEventListener('click', function () {
      скопировать(текстБлока(pre)).then(function () {
        кнопка.textContent = 'Скопировано';
      }, function () {
        кнопка.textContent = 'Не вышло: выделите код вручную';
      }).then(function () {
        clearTimeout(таймер);
        таймер = setTimeout(function () { кнопка.textContent = 'Копировать'; }, 2000);
      });
    });
    обёртка.appendChild(кнопка);
  }
  function все() {
    Array.prototype.forEach.call(document.querySelectorAll('pre'), добавить);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', все); else все();
})();
