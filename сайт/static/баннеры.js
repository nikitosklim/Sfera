// Карусель главных карточек на главной странице: стрелки, точки, смена раз в несколько секунд.
(function () {
  'use strict';
  var окно = document.querySelector('[data-лента]');
  if (!окно) return;
  var путь = окно.querySelector('.лента-путь');
  var карточки = путь.children;
  var точки = окно.querySelector('.лента-точки');
  var кнопки = [];
  var пауза = false;
  var тихо = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;

  function номер() {
    return Math.round(путь.scrollLeft / путь.clientWidth);
  }
  function показать(и) {
    var всего = карточки.length;
    и = (и + всего) % всего;
    путь.scrollTo({ left: и * путь.clientWidth, behavior: тихо ? 'auto' : 'smooth' });
  }
  function отметить() {
    var т = номер();
    for (var k = 0; k < кнопки.length; k++) кнопки[k].setAttribute('aria-selected', k === т ? 'true' : 'false');
  }
  for (var и = 0; и < карточки.length; и++) {
    (function (н) {
      var б = document.createElement('button');
      б.type = 'button';
      б.className = 'лента-точка';
      б.setAttribute('role', 'tab');
      б.setAttribute('aria-label', 'Карточка ' + (н + 1));
      б.addEventListener('click', function () { показать(н); });
      точки.appendChild(б);
      кнопки.push(б);
    })(и);
  }
  окно.querySelectorAll('[data-шаг]').forEach(function (б) {
    б.addEventListener('click', function () { показать(номер() + Number(б.getAttribute('data-шаг'))); });
  });
  путь.addEventListener('scroll', отметить, { passive: true });
  окно.addEventListener('mouseenter', function () { пауза = true; });
  окно.addEventListener('mouseleave', function () { пауза = false; });
  окно.addEventListener('focusin', function () { пауза = true; });
  окно.addEventListener('focusout', function () { пауза = false; });
  if (!тихо) {
    setInterval(function () { if (!пауза && !document.hidden) показать(номер() + 1); }, 7000);
  }
  отметить();
})();
