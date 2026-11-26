// Карусель главных карточек на главной: средняя крупнее, боковые уходят под неё (как обложки в Cover Flow).
(function () {
  'use strict';
  var окно = document.querySelector('[data-лента]');
  if (!окно) return;
  var путь = окно.querySelector('.лента-путь');
  var карточки = Array.prototype.slice.call(путь.children);
  var точки = окно.querySelector('.лента-точки');
  var кнопки = [];
  var тек = 0;
  var пауза = false;
  var тихо = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  var всего = карточки.length;

  function разница(и) {
    var д = и - тек;
    if (д > всего / 2) д -= всего;
    if (д < -всего / 2) д += всего;
    return д;
  }
  function нарисовать() {
    карточки.forEach(function (к, и) {
      var д = разница(и);
      var а = Math.min(Math.abs(д), 2);
      к.style.setProperty('--d', Math.max(-2, Math.min(2, д)));
      к.style.setProperty('--a', а);
      if (д === 0) к.setAttribute('data-центр', ''); else к.removeAttribute('data-центр');
      if (а > 1) к.setAttribute('data-далеко', ''); else к.removeAttribute('data-далеко');
      к.setAttribute('aria-hidden', д === 0 ? 'false' : 'true');
      к.tabIndex = -1;
      Array.prototype.forEach.call(к.querySelectorAll('a'), function (а2) { а2.tabIndex = д === 0 ? 0 : -1; });
    });
    кнопки.forEach(function (б, и) { б.setAttribute('aria-selected', и === тек ? 'true' : 'false'); });
  }
  function показать(и) {
    тек = ((и % всего) + всего) % всего;
    нарисовать();
  }
  карточки.forEach(function (к, и) {
    var б = document.createElement('button');
    б.type = 'button';
    б.className = 'лента-точка';
    б.setAttribute('role', 'tab');
    б.setAttribute('aria-label', 'Карточка ' + (и + 1));
    б.addEventListener('click', function () { показать(и); });
    точки.appendChild(б);
    кнопки.push(б);
    к.addEventListener('click', function (с) {
      if (и !== тек) { с.preventDefault(); показать(и); }
    });
  });
  Array.prototype.forEach.call(окно.querySelectorAll('[data-шаг]'), function (б) {
    б.addEventListener('click', function () { показать(тек + Number(б.getAttribute('data-шаг'))); });
  });
  var старт = null;
  путь.addEventListener('pointerdown', function (с) { старт = с.clientX; });
  путь.addEventListener('pointerup', function (с) {
    if (старт === null) return;
    var сдвиг = с.clientX - старт;
    старт = null;
    if (Math.abs(сдвиг) > 40) показать(тек + (сдвиг < 0 ? 1 : -1));
  });
  окно.addEventListener('mouseenter', function () { пауза = true; });
  окно.addEventListener('mouseleave', function () { пауза = false; });
  окно.addEventListener('focusin', function () { пауза = true; });
  окно.addEventListener('focusout', function () { пауза = false; });
  if (!тихо) {
    setInterval(function () { if (!пауза && !document.hidden) показать(тек + 1); }, 7000);
  }
  нарисовать();
})();
