// Подсветка пункта слева («Содержание», меню управления) по месту на странице.
(function () {
  'use strict';
  var группы = [];
  function собрать(селектор) {
    var ссылки = Array.prototype.slice.call(document.querySelectorAll(селектор));
    var пары = [];
    ссылки.forEach(function (a) {
      var h = a.getAttribute('href') || '';
      if (h.charAt(0) !== '#' || h.length < 2) return;
      var id; try { id = decodeURIComponent(h.slice(1)); } catch (e) { id = h.slice(1); }
      var цель = document.getElementById(id);
      if (цель) пары.push({ a: a, цель: цель });
    });
    if (пары.length) группы.push(пары);
  }
  function обновить() {
    var порог = 120, низ = window.innerHeight + window.pageYOffset >= document.documentElement.scrollHeight - 4;
    группы.forEach(function (пары) {
      var выбран = null;
      for (var i = 0; i < пары.length; i++) {
        if (пары[i].цель.getBoundingClientRect().top <= порог) выбран = пары[i];
      }
      if (низ) выбран = пары[пары.length - 1];
      if (!выбран) выбран = пары[0];
      пары.forEach(function (п) {
        var вкл = п === выбран;
        if (п.a.classList.contains('текущая') !== вкл) {
          п.a.classList.toggle('текущая', вкл);
          if (вкл) п.a.setAttribute('aria-current', 'location'); else п.a.removeAttribute('aria-current');
          if (вкл) прокрутить_список(п.a);
        }
      });
    });
  }
  // Если список слева длиннее экрана и сам прокручивается — держим активный пункт на виду.
  function прокрутить_список(a) {
    var к = a.closest('.toc, .док-темы');
    if (!к || к.scrollHeight <= к.clientHeight) return;
    var r = a.getBoundingClientRect(), kr = к.getBoundingClientRect();
    if (r.top < kr.top + 8) к.scrollTop -= kr.top + 8 - r.top;
    else if (r.bottom > kr.bottom - 8) к.scrollTop += r.bottom - kr.bottom + 8;
  }
  var ждём = false;
  function при_прокрутке() {
    if (ждём) return;
    ждём = true;
    window.requestAnimationFrame(function () { ждём = false; обновить(); });
  }
  function старт() {
    собрать('.toc a');
    собрать('.док-темы a');
    собрать('.админ-меню > a');
    if (!группы.length) return;
    window.addEventListener('scroll', при_прокрутке, { passive: true });
    window.addEventListener('resize', при_прокрутке);
    обновить();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', старт); else старт();
})();
