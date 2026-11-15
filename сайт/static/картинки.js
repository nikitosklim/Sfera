// Картинки уроков: подпись под рисунком и заглушка, если файла ещё нет.
(function () {
  function хеш(с) { var h = 7; for (var i = 0; i < с.length; i++) h = (h * 31 + с.charCodeAt(i)) % 360; return h; }
  function заглушка(имя, подпись) {
    var т = хеш(имя);
    var кружки = '';
    for (var i = 0; i < 5; i++) {
      var х = 60 + ((т * (i + 3)) % 520), у = 30 + ((т * (i + 5)) % 150), р = 18 + ((т + i * 17) % 44);
      кружки += '<circle cx="' + х + '" cy="' + у + '" r="' + р + '" fill="hsl(' + ((т + i * 40) % 360) + ',70%,65%)" opacity=".35"/>';
    }
    var д = document.createElement('div');
    д.className = 'картинка-заглушка';
    д.setAttribute('role', 'img');
    д.setAttribute('aria-label', подпись || 'Картинка');
    д.innerHTML = '<svg viewBox="0 0 640 220" aria-hidden="true">' + кружки +
      '<circle cx="320" cy="96" r="46" fill="none" stroke="currentColor" stroke-width="2" opacity=".6"/>' +
      '<ellipse cx="320" cy="96" rx="46" ry="16" fill="none" stroke="currentColor" stroke-width="1.5" opacity=".45"/></svg>' +
      '<span class="картинка-имя"></span>';
    д.querySelector('.картинка-имя').textContent = 'Здесь будет картинка: ' + имя;
    return д;
  }
  function оформить(img) {
    if (img.closest('figure')) return;
    var имя = decodeURIComponent((img.getAttribute('src') || '').split('/').pop());
    var подпись = img.getAttribute('alt') || '';
    var фигура = document.createElement('figure');
    фигура.className = 'картинка';
    img.parentNode.insertBefore(фигура, img);
    фигура.appendChild(img);
    if (подпись) { var п = document.createElement('figcaption'); п.textContent = подпись; фигура.appendChild(п); }
    var подменить = function () { if (img.parentNode === фигура) фигура.replaceChild(заглушка(имя, подпись), img); };
    img.addEventListener('error', подменить);
    if (img.complete && img.naturalWidth === 0) подменить();
  }
  function запуск() {
    var все = document.querySelectorAll('img[src^="/статика/уроки/"]');
    for (var i = 0; i < все.length; i++) оформить(все[i]);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', запуск); else запуск();
})();
