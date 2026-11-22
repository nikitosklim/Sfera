// Решения упражнений: блок кода с пометкой «решение» (в разметке
// «```сфера решение») прячется под кнопку «Показать решение», чтобы
// сначала можно было попробовать самому.
(function () {
  function запуск() {
    var блоки = document.querySelectorAll('pre > code.решение');
    for (var i = 0; i < блоки.length; i++) {
      var pre = блоки[i].parentNode;
      if (!pre.parentNode || pre.parentNode.classList.contains('решение-блок')) continue;
      var d = document.createElement('details');
      d.className = 'решение-блок';
      var s = document.createElement('summary');
      s.textContent = 'Показать решение';
      d.appendChild(s);
      pre.parentNode.insertBefore(d, pre);
      d.appendChild(pre);
      d.addEventListener('toggle', function (e) {
        var сам = e.target;
        сам.firstChild.textContent = сам.open ? 'Скрыть решение' : 'Показать решение';
      });
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', запуск);
  else запуск();
})();
