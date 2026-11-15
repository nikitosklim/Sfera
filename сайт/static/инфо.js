// Кнопки «инфо»: в тексте материала пишется «{{инфо: подробности}}»,
// скрипт прячет подробности и показывает кнопку, которая их раскрывает.
(function () {
  function обработать(элемент) {
    var html = элемент.innerHTML;
    if (html.indexOf('{{инфо:') === -1 && html.indexOf('{{ответ:') === -1) return;
    html = html.replace(/\{\{ответ:\s*([\s\S]*?)\}\}/g, function (_, подробно) {
      return ' <button type="button" class="инфо-кнопка" data-открыть="показать ответ" data-закрыть="скрыть ответ" aria-expanded="false">показать ответ</button>' +
             '<span class="инфо-текст" hidden>' + подробно + '</span>';
    });
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
      к.textContent = открыто ? (к.getAttribute('data-открыть') || 'инфо') : (к.getAttribute('data-закрыть') || 'скрыть');
      if (т) т.hidden = открыто;
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', запуск);
  else запуск();
})();
