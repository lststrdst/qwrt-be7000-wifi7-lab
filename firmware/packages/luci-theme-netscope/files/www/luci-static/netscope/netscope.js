/* NETSCOPE theme enhancement only. No API calls, cookie access or form submit handlers. */
(function () {
  'use strict';
  function text(node, value) { node.textContent = value; return node; }
  function init() {
    if (!document.body.classList.contains('netscope')) return;
    var menu = document.getElementById('ns-settings-menu');
    var search = document.getElementById('ns-menu-search');
    var result = document.getElementById('ns-search-result');
    if (menu && search) {
      if (menu.dataset.nsReady) return;
      menu.dataset.nsReady = '1';
      var groups = Array.prototype.slice.call(menu.children);
      var shortcuts = [];
      function destination(a) {
        var href = a.getAttribute('href').trim();
        if (!href || href.startsWith('#') || a.origin !== location.origin) return null;
        // Different query parameters or fragment targets may mean different settings.
        return a.pathname.replace(/\/{2,}/g, '/').replace(/\/$/, '') + a.search + a.hash;
      }
      function hideDuplicate(a, reason) {
        var item = a.closest('li');
        if (!item) return;
        item.classList.add('ns-quick-duplicate');
        item.dataset.nsDuplicate = reason;
      }
      search.addEventListener('input', function () {
        var query = search.value.trim().toLocaleLowerCase();
        var matches = 0;
        menu.classList.toggle('ns-searching', !!query);
        groups.forEach(function (group) {
          if (group.classList.contains('ns-quick-duplicate')) return;
          var top = group.querySelector('a.menu, a.menu2');
          var items = Array.prototype.slice.call(group.querySelectorAll('.slide-menu > li'));
          var categoryMatches = top && (top.textContent + ' ' + (top.dataset.nsSearch || '')).toLocaleLowerCase().indexOf(query) !== -1;
          var visible = false;
          items.forEach(function (item) {
            if (item.classList.contains('ns-quick-duplicate')) return;
            var hit = !query || categoryMatches || (item.textContent + ' ' + (item.dataset.nsSearch || '')).toLocaleLowerCase().indexOf(query) !== -1;
            item.classList.toggle('ns-filter-hidden', !hit);
            if (hit) { visible = true; matches++; }
          });
          if (!items.length) { visible = !query || categoryMatches; if (visible) matches++; }
          group.classList.toggle('ns-filter-hidden', !visible);
        });
        shortcuts.forEach(function (item) {
          var hit = !query || item.search.indexOf(query) !== -1;
          item.link.classList.toggle('ns-filter-hidden', !hit);
          if (hit) matches++;
        });
        result.textContent = query ? (matches ? 'Найдено настроек: ' + matches : 'Подходящих настроек нет') : '';
      });
      search.addEventListener('keydown', function (event) {
        if (event.key === 'Escape') { search.value = ''; search.dispatchEvent(new Event('input')); }
      });
      var quick = document.getElementById('ns-quick');
      var russianMenu = {
        'Status':'Состояние','Overview':'Обзор','Firewall status':'Состояние межсетевого экрана','Routes':'Маршруты',
        'System Log':'Системный журнал','Kernel Log':'Журнал ядра','Processes':'Процессы','Realtime Graphs':'Графики в реальном времени',
        'Free Memory':'Освободить память','WireGuard Status':'Состояние WireGuard','Modem':'Модем','USB Mobile Data':'Мобильная сеть USB',
        'Signal Status':'Уровень сигнала','AT Tools':'Инструменты AT','System':'Система','Administration':'Администрирование',
        'TTYD Terminal':'Терминал TTYD','Software':'Пакеты','Startup':'Автозапуск','Scheduled Tasks':'Задания по расписанию',
        'Mount Points':'Точки монтирования','Disk Man':'Диски','LED Configuration':'Индикаторы','Backup / Flash Firmware':'Резервная копия и прошивка',
        'Scheduled Reboot':'Перезагрузка по расписанию','FileTransfer':'Передача файлов','Reboot':'Перезагрузка','Fan Control':'Управление вентилятором',
        'Services':'Службы','Internet Access Schedule Control':'Расписание доступа в интернет','Adblock DNS List':'Списки блокировки DNS',
        'Dynamic DNS':'Динамический DNS','IPTV RTP/UDP/RTSP':'IPTV RTP/UDP/RTSP','VPN Quick setup':'Быстрая настройка VPN',
        'Wake on LAN':'Пробуждение по сети','KMS Server':'Сервер KMS','CPU Freq':'Частота процессора','NAS':'Сетевое хранилище',
        'USB Printer Server':'Сервер USB-принтера','FTP Server':'Сервер FTP','Network Shares':'Сетевые папки','VPN':'VPN',
        'IPSec VPN Server':'Сервер IPSec VPN','OpenVPN Server':'Сервер OpenVPN','Network':'Сеть','Interfaces':'Интерфейсы',
        'Wireless':'Wi-Fi','DHCP and DNS':'DHCP и DNS','Hostnames':'Имена узлов','Static Routes':'Статические маршруты',
        'Firewall settings':'Настройки межсетевого экрана','Diagnostics':'Диагностика','ECM ACC Settings':'Настройки ускорения ECM',
        'Turbo ACC Center':'Центр ускорения Turbo ACC','Logout':'Выйти','Advanced':'Дополнительно',
        'Anonymous User':'Анонимный пользователь','Apply':'Применить','Base Setting':'Основные настройки','Changes':'Изменения',
        'Configuration':'Конфигурация','Connections':'Соединения','Custom Rules':'Пользовательские правила',
        'Edit Blacklist':'Изменить чёрный список','Edit Configuration':'Изменить конфигурацию','Edit Whitelist':'Изменить белый список',
        'Firewall':'Межсетевой экран','General Settings':'Основные настройки','Interface Info':'Сведения об интерфейсе',
        'L2TP Online Users':'Пользователи L2TP онлайн','Load':'Нагрузка','Log':'Журнал','Log Settings':'Настройки журнала',
        'Port Forwards':'Перенаправление портов','Query domains':'Проверка доменов','Revert':'Отменить изменения',
        'Save &#38; Apply':'Сохранить и применить','Save & Apply':'Сохранить и применить','Special Code':'Расширенная конфигурация',
        'Traffic':'Трафик','Traffic Rules':'Правила трафика','UPnP':'UPnP','Users Manager':'Управление пользователями',
        'View Logfile':'Просмотреть журнал','Virtual Users':'Виртуальные пользователи','XUPNP IPTV':'XUPNP IPTV','ZeroTier':'ZeroTier',
        'NETSCOPE':'NETSCOPE','AmneziaWG':'AmneziaWG'
      };
      Array.prototype.slice.call(menu.querySelectorAll('a')).forEach(function (a) {
        var original = a.textContent.trim();
        var source = (a.dataset.title || '').trim();
        var translated = russianMenu[original] || russianMenu[source];
        a.dataset.nsSearch = ((a.dataset.nsSearch || '') + ' ' + original + ' ' + source).trim();
        var item = a.closest('li');
        if (item) item.dataset.nsSearch = ((item.dataset.nsSearch || '') + ' ' + original + ' ' + source).trim();
        if (translated) a.textContent = translated;
      });
      // A category href="#" resolves to the current pathname too. It is a
      // disclosure control, never a page destination or shortcut source.
      var links = Array.prototype.slice.call(menu.querySelectorAll('a[href]')).filter(function (a) {
        return destination(a) !== null;
      });
      var choices = [
        ['Обзор', '/admin/status/overview'], ['Wi-Fi', '/admin/network/wireless'],
        ['Интерфейсы', '/admin/network/network'], ['AmneziaWG', '/admin/services/amneziawg'],
        ['NETSCOPE', '/admin/status/netscope'],
        ['Быстрая настройка VPN', '/admin/services/netscope_setup']
      ];
      choices.forEach(function (choice) {
        var original = links.find(function (a) { return a.pathname.replace(/\/$/, '').endsWith(choice[1]); });
        if (!quick || !original) return;
        var a = text(document.createElement('a'), choice[0]);
        a.href = original.pathname.replace(/\/{2,}/g, '/') + original.search;
        var current = location.pathname.replace(/\/$/, '') === original.pathname.replace(/\/$/, '');
        if (current) a.setAttribute('aria-current', 'page');
        a.addEventListener('click', function (event) {
          // Re-clicking the current section must not reload or reset observation.
          if (current && !event.ctrlKey && !event.metaKey && !event.shiftKey && event.button === 0) {
            event.preventDefault(); event.stopPropagation();
          }
        });
        quick.appendChild(a);
        shortcuts.push({link:a, search:(choice[0]+' '+original.textContent+' '+(original.dataset.nsSearch||'')+' '+original.closest('.slide').querySelector('a').textContent).toLocaleLowerCase()});
        // Keep the native route in the DOM for LuCI, but show each destination once.
        var key = destination(original);
        links.forEach(function (link) {
          if (destination(link) === key) {
            shortcuts[shortcuts.length - 1].search += ' ' + link.textContent.toLocaleLowerCase();
            hideDuplicate(link, 'quick-access');
          }
        });
      });
      // Only identical destinations are duplicates. Never merge by caption:
      // Firewall status/settings, Routes/Static Routes and WG/AWG are distinct.
      var seen = Object.create(null);
      links.forEach(function (a) {
        if (a.closest('.ns-quick-duplicate')) return;
        var key = destination(a);
        if (seen[key]) {
          var kept = seen[key].closest('li');
          kept.dataset.nsSearch = (kept.dataset.nsSearch || '') + ' ' + a.textContent;
          hideDuplicate(a, 'same-destination');
        }
        else seen[key] = a;
      });
      groups.forEach(function (group) {
        var items = Array.prototype.slice.call(group.querySelectorAll('.slide-menu > li'));
        if (items.length && items.every(function (item) { return item.classList.contains('ns-quick-duplicate'); })) {
          group.classList.add('ns-quick-duplicate');
          group.dataset.nsDuplicate = 'empty-category';
        }
      });
      if (location.pathname.replace(/\/$/, '').endsWith('/admin/status/wireguard')) {
        var wizard = shortcuts.find(function (item) { return item.link.pathname.endsWith('/admin/services/netscope_setup'); });
        var content = document.querySelector('#maincontent > .container');
        if (wizard && content) {
          var notice = text(document.createElement('p'), 'На этой странице показаны существующие интерфейсы WireGuard. Для подготовки новой конфигурации откройте ');
          notice.id = 'ns-wg-setup-hint'; notice.className = 'alert-message notice';
          var launch = text(document.createElement('a'), 'быструю настройку VPN'); launch.href = wizard.link.href;
          notice.appendChild(launch); content.insertBefore(notice, content.firstChild);
        }
      }
    }
    // Layout-only grouping. Keep native clock/actions and their handlers intact.
    if (document.body.classList.contains('logged-in')) {
      document.querySelectorAll('.cbi-value-field').forEach(function (field) {
        if (field.closest('#netscope-setup')) return;
        var inlineAction = Array.prototype.some.call(field.children, function (child) {
          return child.matches('button, input[type="button"], input[type="submit"]');
        });
        if (inlineAction) field.classList.add('ns-inline-actions');
      });
    }
    // Keep the stock LuCI password parser and CSRF form. This only adds a
    // nearby native submit control on the unusually long Administration page.
    if (document.body.classList.contains('logged-in') && location.pathname.replace(/\/$/,'').endsWith('/admin/system/admin')) {
      var pw1 = document.querySelector('input[name$=".pw1"]');
      var pw2 = document.querySelector('input[name$=".pw2"]');
      if (pw1 && pw2 && pw1.form === pw2.form && !document.getElementById('ns-password-save')) {
        var passwordSection = pw2.closest('.cbi-section-node') || pw2.closest('.cbi-section');
        if (passwordSection) {
          var passwordActions = document.createElement('div');
          passwordActions.id = 'ns-password-save';passwordActions.className = 'ns-password-save';
          var passwordSave = text(document.createElement('button'), 'Сохранить');
          passwordSave.type = 'submit';passwordSave.name = 'cbi.apply';passwordSave.value = '1';
          passwordSave.className = 'cbi-button cbi-button-apply';
          passwordActions.appendChild(passwordSave);passwordSection.appendChild(passwordActions);
        }
      }
    }
    // The original sysauth form and POST target remain intact.
    if (!document.body.classList.contains('logged-in')) {
      var password = document.querySelector('input[name="luci_password"]');
      var username = document.querySelector('input[name="luci_username"]');
      if (!password || !username || !password.form) return;
      var form = password.form;
      // Login-only: remove the legacy field-clear button, not account recovery.
      form.querySelectorAll('input[type="reset"],button[type="reset"]').forEach(function (button) { button.remove(); });
      form.classList.add('ns-login-form');
      document.body.classList.add('ns-login');
      [[username, 'username', 'ns-username', 'Имя пользователя'], [password, 'current-password', 'ns-password', 'Пароль']].forEach(function (row) {
        row[0].setAttribute('autocomplete', row[1]);
        if (!row[0].id) row[0].id = row[2];
        var field = row[0].closest('.cbi-value');
        var label = field && field.querySelector('label');
        if (label) { label.htmlFor = row[0].id; label.textContent = row[3]; }
      });
      var heading = form.querySelector('h2');
      var description = form.querySelector('.cbi-map-descr');
      if (heading) heading.textContent = 'Добро пожаловать домой.';
      if (description) description.textContent = 'Войдите, чтобы управлять роутером.';
      var submit = form.querySelector('input[type="submit"]');
      if (submit) { submit.value = 'Войти'; submit.parentElement.classList.add('ns-login-actions'); }
      var error = form.querySelector('.errorbox');
      if (error) error.setAttribute('role', 'alert');
      var note = text(document.createElement('p'), 'Используйте учётную запись администратора роутера.');
      note.className = 'ns-login-note'; form.appendChild(note);
      if (location.protocol !== 'https:') {
        var warning = text(document.createElement('p'), 'Соединение HTTP · входите только из доверенной локальной сети или через VPN.');
        warning.className = 'ns-http-note'; form.appendChild(warning);
      }
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init, { once: true });
  else init();
})();
