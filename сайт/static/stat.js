// Счётчик времени на странице: без cookie и без адресов. Шлёт активные секунды,
// глубину прокрутки и время по разделам при закрытии или сворачивании вкладки.
// Уважает «Не отслеживать» (Do Not Track).
(function () {
  if (navigator.doNotTrack === '1' || window.doNotTrack === '1') return;
  if (document.cookie.indexOf('sfera_own=1') >= 0) return;
  var путь = location.pathname;
  try { путь = decodeURIComponent(путь); } catch (e) {}
  if (путь.indexOf('/управление') === 0 || путь.indexOf('/admin') === 0) return;
  var сессия = '';
  try {
    сессия = sessionStorage.getItem('sfera-s') || '';
    if (!сессия) { сессия = Math.random().toString(36).slice(2, 14); sessionStorage.setItem('sfera-s', сессия); }
  } catch (e) {}
  var секунд = 0, глубина = 0, разделы = {};
  function раздел() {
    var текущий = 'начало';
    var заголовки = document.querySelectorAll('h2[id], h3[id]');
    for (var i = 0; i < заголовки.length; i++) {
      if (заголовки[i].getBoundingClientRect().top <= window.innerHeight * 0.4) {
        текущий = (заголовки[i].textContent || '').replace(/[:,&=%+\s]+/g, ' ').trim().slice(0, 40) || 'начало';
      } else break;
    }
    return текущий;
  }
  function глубинаСейчас() {
    var всего = Math.max(document.documentElement.scrollHeight, 1);
    var г = Math.round((window.scrollY + window.innerHeight) * 100 / всего);
    if (г > глубина) глубина = Math.min(г, 100);
  }
  setInterval(function () {
    if (document.visibilityState !== 'visible' || !document.hasFocus() || секунд >= 7200) return;
    секунд++;
    глубинаСейчас();
    var р = раздел();
    if (разделы[р] || Object.keys(разделы).length < 12) разделы[р] = (разделы[р] || 0) + 1;
  }, 1000);
  window.addEventListener('scroll', глубинаСейчас, { passive: true });
  function отправить() {
    if (секунд < 1) return;
    глубинаСейчас();
    var список = Object.keys(разделы).sort(function (а, б) { return разделы[б] - разделы[а]; })
      .slice(0, 8).map(function (к) { return к + ':' + разделы[к]; }).join(',');
    var тело = 'п=' + encodeURIComponent(путь) + '&с=' + encodeURIComponent(сессия) + '&т=' + секунд +
      '&г=' + глубина + '&р=' + encodeURIComponent(список);
    try {
      navigator.sendBeacon('/статистика/время', new Blob([тело], { type: 'application/x-www-form-urlencoded' }));
    } catch (e) {}
    секунд = 0; разделы = {};
  }
  document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'hidden') отправить(); });
  window.addEventListener('pagehide', отправить);
})();
