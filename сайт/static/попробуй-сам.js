// «Попробуй сам»: блок кода с языком «попробуй» превращается в маленькую площадку:
// редактор, кнопка «Запустить» и поле вывода. Работает так же, как страница «Попробовать».
(function () {
  var подгружен = false, очередь = [];
  function подгрузить(потом) {
    if (window.запуститьСферу) { потом(); return; }
    очередь.push(потом);
    if (подгружен) return;
    подгружен = true;
    var с = document.createElement('script');
    с.src = '/статика/sfera-wasm.js';
    с.onload = function () { var q = очередь; очередь = []; q.forEach(function (f) { f(); }); };
    с.onerror = function () { подгружен = false; очередь = []; };
    document.head.appendChild(с);
  }
  function создать(код) {
    var pre = код.parentNode;
    var исходник = код.textContent.replace(/\s+$/, '') + '\n';
    var нужен_ввод = исходник.indexOf('прочитать_строку') !== -1;
    var к = document.createElement('div');
    к.className = 'попробуй';
    к.innerHTML =
      '<div class="попробуй-шапка"><b>Попробуй сам</b><span>Поменяйте код и нажмите «Запустить»</span></div>' +
      '<textarea class="попробуй-код" spellcheck="false" autocapitalize="off" autocomplete="off" aria-label="Код программы" rows="8"></textarea>' +
      (нужен_ввод ? '<label class="попробуй-ввод">Ввод для программы (каждая строка — отдельный ответ)<textarea spellcheck="false" rows="2" aria-label="Ввод"></textarea></label>' : '') +
      '<div class="попробуй-кнопки"><button type="button" class="button попробуй-запуск">Запустить</button> ' +
      '<button type="button" class="button secondary попробуй-сброс">Вернуть как было</button> <span class="muted попробуй-статус"></span></div>' +
      '<pre class="попробуй-вывод" aria-live="polite">Нажмите «Запустить», и здесь появится результат.</pre>';
    var поле = к.querySelector('.попробуй-код');
    var ввод = к.querySelector('.попробуй-ввод textarea');
    var запуск = к.querySelector('.попробуй-запуск');
    var вывод = к.querySelector('.попробуй-вывод');
    var статус = к.querySelector('.попробуй-статус');
    поле.value = исходник;
    поле.rows = Math.min(18, Math.max(6, исходник.split('\n').length));
    поле.addEventListener('keydown', function (e) {
      if (e.key === 'Tab') { e.preventDefault(); поле.setRangeText('    ', поле.selectionStart, поле.selectionEnd, 'end'); }
      if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); запуск.click(); }
    });
    к.querySelector('.попробуй-сброс').onclick = function () { поле.value = исходник; };
    function готово() { запуск.disabled = false; }
    запуск.onclick = function () {
      вывод.textContent = ''; вывод.className = 'попробуй-вывод'; запуск.disabled = true; статус.textContent = 'Собираю…';
      подгрузить(function () {
        window.запуститьСферу(поле.value, ((ввод && ввод.value) || '').replace(/\r?\n?$/, '\n'), {
          статус: function (т) { статус.textContent = т; },
          вывод: function (т) { вывод.textContent += т; },
          ошибка: function (т) { вывод.className = 'попробуй-вывод ошибка'; вывод.textContent += (вывод.textContent ? '\n' : '') + т; статус.textContent = 'Не получилось'; готово(); },
          конец: function (c) { статус.textContent = c === 0 ? 'Готово' : 'Программа завершилась с кодом ' + c; if (!вывод.textContent) вывод.textContent = '(программа ничего не вывела)'; готово(); }
        });
      });
    };
    var место = (pre.parentNode.classList && pre.parentNode.classList.contains('код-блок')) ? pre.parentNode : pre;
    место.parentNode.replaceChild(к, место);
  }
  function запуск() {
    var все = document.querySelectorAll('code.язык-попробуй');
    for (var i = 0; i < все.length; i++) создать(все[i]);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', запуск); else запуск();
})();
