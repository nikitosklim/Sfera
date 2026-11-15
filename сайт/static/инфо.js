// Кнопки «инфо»: в тексте материала пишется «{{инфо: подробности}}»,
// скрипт прячет подробности и показывает кнопку, которая их раскрывает.
(function () {
  function обработать(элемент) {
    var html = элемент.innerHTML;
    if (html.indexOf('{{инфо:') === -1) return;
    элемент.innerHTML = html.replace(/\{\{инфо:\s*([\s\S]*?)\}\}/g, function (_, подробно) {
      return ' <button type="button" class="инфо-кнопка" aria-expanded="false">инфо</button>' +
             '<span class="инфо-текст" hidden>' + подробно + '</span>';
    });
  }
  function запуск() {
    var места = document.querySelectorAll('li, p');
    for (var i = 0; i < места.length; i++) обработать(места[i]);
    document.addEventListener('click', function (e) {
      var к = e.target.closest ? e.target.closest('.инфо-кнопка') : null;
      if (!к) return;
      var т = к.nextElementSibling;
      var открыто = к.getAttribute('aria-expanded') === 'true';
      к.setAttribute('aria-expanded', открыто ? 'false' : 'true');
      к.textContent = открыто ? 'инфо' : 'скрыть';
      if (т) т.hidden = открыто;
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', запуск);
  else запуск();
})();
