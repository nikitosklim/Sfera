// Фильтр карточек статей по тегам.
(function () {
  var кнопки = document.querySelectorAll('.фильтр-тегов button');
  var карточки = document.querySelectorAll('.статья');
  Array.prototype.forEach.call(кнопки, function (к) {
    к.addEventListener('click', function () {
      var тег = к.getAttribute('data-тег');
      Array.prototype.forEach.call(кнопки, function (б) { б.classList.toggle('активный', б === к); });
      Array.prototype.forEach.call(карточки, function (с) {
        с.hidden = !!тег && (с.getAttribute('data-теги') || '').indexOf(',' + тег + ',') < 0;
      });
    });
  });
})();
