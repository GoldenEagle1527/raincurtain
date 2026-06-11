import 'package:flutter/material.dart';
import '../../main.dart' show sandboxServerPort;

/// 将 Color 转换为 CSS hex 格式
String _toHex(Color color) {
  return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}

/// 生成主题注入 JS 脚本
/// 注入全局 CSS 变量、字体、Material Icons、滚动条样式
String generateThemeJS(ThemeData theme) {
  final colorScheme = theme.colorScheme;
  final isLight = theme.brightness == Brightness.light;
  final successColor = isLight ? '#2E7D32' : '#81C784';
  final errorColor = isLight ? _toHex(colorScheme.error) : '#B44A4A';
  final elevation = isLight
      ? '0 1px 2px rgba(0,0,0,.3), 0 1px 3px 1px rgba(0,0,0,.15)'
      : '0 1px 2px rgba(0,0,0,.6), 0 1px 3px 1px rgba(0,0,0,.4)';

  return '''
(function() {
  // 注入全局字体和 Material Icons 字体 (使用本地字体文件)
  function _injectFontStyles() {
    var fontStyleEl = document.getElementById('raincurtain-material-icons-fonts');
    if (!fontStyleEl) {
      fontStyleEl = document.createElement('style');
      fontStyleEl.id = 'raincurtain-material-icons-fonts';
      fontStyleEl.textContent = `
        @font-face {
          font-family: 'NotoSerifSC';
          font-style: normal;
          font-weight: 200 900;
          src: url('http://localhost:$sandboxServerPort/__raincurtain_fonts__/NotoSerifSC-VariableFont_wght.ttf') format('truetype');
        }
        
        @font-face {
          font-family: 'Material Icons';
          font-style: normal;
          font-weight: 400;
          src: url('http://localhost:$sandboxServerPort/__raincurtain_fonts__/MaterialIcons-Regular.ttf') format('truetype');
        }
        
        @font-face {
          font-family: 'Material Icons Outlined';
          font-style: normal;
          font-weight: 400;
          src: url('http://localhost:$sandboxServerPort/__raincurtain_fonts__/MaterialIconsOutlined-Regular.otf') format('opentype');
        }
        
        @font-face {
          font-family: 'Material Icons Rounded';
          font-style: normal;
          font-weight: 400;
          src: url('http://localhost:$sandboxServerPort/__raincurtain_fonts__/MaterialIconsRounded-Regular.otf') format('opentype');
        }
        
        @font-face {
          font-family: 'Material Icons Sharp';
          font-style: normal;
          font-weight: 400;
          src: url('http://localhost:$sandboxServerPort/__raincurtain_fonts__/MaterialIconsSharp-Regular.otf') format('opentype');
        }
        
        @font-face {
          font-family: 'Material Icons Two Tone';
          font-style: normal;
          font-weight: 400;
          src: url('http://localhost:$sandboxServerPort/__raincurtain_fonts__/MaterialIconsTwoTone-Regular.otf') format('opentype');
        }
      `;
      var parent = document.head || document.documentElement;
      if (parent) {
        parent.appendChild(fontStyleEl);
      }
    }
  }
  
  // 立即尝试注入字体样式
  var _fontParent = document.head || document.documentElement;
  if (_fontParent) {
    _injectFontStyles();
  } else {
    // DOM 未就绪，监听直到可用
    var _fontObs = new MutationObserver(function() {
      if (document.head || document.documentElement) {
        _fontObs.disconnect();
        _injectFontStyles();
      }
    });
    _fontObs.observe(document, { childList: true, subtree: true });
  }
  
  var cssText = `
    :root {
      --md-primary: ${_toHex(colorScheme.primary)};
      --md-on-primary: ${_toHex(colorScheme.onPrimary)};
      --md-primary-container: ${_toHex(colorScheme.primaryContainer)};
      --md-on-primary-container: ${_toHex(colorScheme.onPrimaryContainer)};
      --md-surface: ${_toHex(colorScheme.surface)};
      --md-surface-container: ${_toHex(colorScheme.surfaceContainer)};
      --md-surface-container-high: ${_toHex(colorScheme.surfaceContainerHigh)};
      --md-on-surface: ${_toHex(colorScheme.onSurface)};
      --md-on-surface-variant: ${_toHex(colorScheme.onSurfaceVariant)};
      --md-outline-variant: ${_toHex(colorScheme.outlineVariant)};
      --md-error: $errorColor;
      --md-success: $successColor;

      --md-radius-button: 20px;
      --md-radius-card: 12px;
      --md-elevation-1: $elevation;
      --md-font: 'NotoSerifSC', 'Noto Serif SC', serif, system-ui;
      
      /* Material Icons 字体族 */
      --md-font-material-icons: 'Material Icons';
      --md-font-material-icons-outlined: 'Material Icons Outlined';
      --md-font-material-icons-rounded: 'Material Icons Rounded';
      --md-font-material-icons-sharp: 'Material Icons Sharp';
      --md-font-material-icons-two-tone: 'Material Icons Two Tone';
      
      /* 滚动条样式变量 */
      --md-scrollbar-width: 8px;
      --md-scrollbar-height: 8px;
      --md-scrollbar-track-bg: ${_toHex(colorScheme.surfaceContainer)};
      --md-scrollbar-track-radius: 4px;
      --md-scrollbar-thumb-bg: ${_toHex(colorScheme.outlineVariant)};
      --md-scrollbar-thumb-hover-bg: ${_toHex(colorScheme.onSurfaceVariant)};
      --md-scrollbar-thumb-radius: 4px;
    }
    html, body {
      margin: 0; padding: 0;
      box-sizing: border-box;
      font-family: var(--md-font);
      background-color: var(--md-surface);
      color: var(--md-on-surface);
    }
    *, *::before, *::after {
      box-sizing: inherit;
    }
    
    /* Material Icons 基础样式类 */
    .material-icons {
      font-family: var(--md-font-material-icons);
      font-weight: normal;
      font-style: normal;
      font-size: 24px;
      line-height: 1;
      letter-spacing: normal;
      text-transform: none;
      display: inline-block;
      white-space: nowrap;
      word-wrap: normal;
      direction: ltr;
      -webkit-font-smoothing: antialiased;
      text-rendering: optimizeLegibility;
      -moz-osx-font-smoothing: grayscale;
      font-feature-settings: 'liga';
    }
    
    .material-icons-outlined {
      font-family: var(--md-font-material-icons-outlined);
      font-weight: normal;
      font-style: normal;
      font-size: 24px;
      line-height: 1;
      letter-spacing: normal;
      text-transform: none;
      display: inline-block;
      white-space: nowrap;
      word-wrap: normal;
      direction: ltr;
      -webkit-font-smoothing: antialiased;
      text-rendering: optimizeLegibility;
      -moz-osx-font-smoothing: grayscale;
      font-feature-settings: 'liga';
    }
    
    .material-icons-rounded {
      font-family: var(--md-font-material-icons-rounded);
      font-weight: normal;
      font-style: normal;
      font-size: 24px;
      line-height: 1;
      letter-spacing: normal;
      text-transform: none;
      display: inline-block;
      white-space: nowrap;
      word-wrap: normal;
      direction: ltr;
      -webkit-font-smoothing: antialiased;
      text-rendering: optimizeLegibility;
      -moz-osx-font-smoothing: grayscale;
      font-feature-settings: 'liga';
    }
    
    .material-icons-sharp {
      font-family: var(--md-font-material-icons-sharp);
      font-weight: normal;
      font-style: normal;
      font-size: 24px;
      line-height: 1;
      letter-spacing: normal;
      text-transform: none;
      display: inline-block;
      white-space: nowrap;
      word-wrap: normal;
      direction: ltr;
      -webkit-font-smoothing: antialiased;
      text-rendering: optimizeLegibility;
      -moz-osx-font-smoothing: grayscale;
      font-feature-settings: 'liga';
    }
    
    .material-icons-two-tone {
      font-family: var(--md-font-material-icons-two-tone);
      font-weight: normal;
      font-style: normal;
      font-size: 24px;
      line-height: 1;
      letter-spacing: normal;
      text-transform: none;
      display: inline-block;
      white-space: nowrap;
      word-wrap: normal;
      direction: ltr;
      -webkit-font-smoothing: antialiased;
      text-rendering: optimizeLegibility;
      -moz-osx-font-smoothing: grayscale;
      font-feature-settings: 'liga';
    }
    
    /* 滚动条样式 - Webkit 浏览器 */
    ::-webkit-scrollbar {
      width: var(--md-scrollbar-width);
      height: var(--md-scrollbar-height);
    }
    ::-webkit-scrollbar-track {
      background: var(--md-scrollbar-track-bg);
      border-radius: var(--md-scrollbar-track-radius);
    }
    ::-webkit-scrollbar-thumb {
      background: var(--md-scrollbar-thumb-bg);
      border-radius: var(--md-scrollbar-thumb-radius);
      transition: background 0.2s ease;
    }
    ::-webkit-scrollbar-thumb:hover {
      background: var(--md-scrollbar-thumb-hover-bg);
    }
    
    /* 滚动条样式 - Firefox */
    * {
      scrollbar-width: thin;
      scrollbar-color: var(--md-scrollbar-thumb-bg) var(--md-scrollbar-track-bg);
    }
    
    /* 自定义下拉弹出框（MD3 规范） */
    .raincurtain-dropdown-menu {
      position: absolute;
      z-index: 100000;
      background-color: var(--md-surface-container-high);
      border: 1px solid var(--md-outline-variant);
      border-radius: 8px;
      box-shadow: 0px 4px 8px 3px rgba(0, 0, 0, 0.15), 0px 1px 3px 0px rgba(0, 0, 0, 0.3);
      overflow-y: auto;
      overflow-x: hidden;
      max-height: 280px;
      box-sizing: border-box;
      padding: 4px 0;
      margin: 0;
      list-style: none;
      
      /* 动画属性 */
      opacity: 0;
      transform: scale(0.95) translateY(-8px);
      transition: opacity 0.15s cubic-bezier(0, 0, 0.2, 1), transform 0.15s cubic-bezier(0, 0, 0.2, 1);
      pointer-events: none;
      display: none;
    }
    
    .raincurtain-dropdown-menu.show {
      display: block;
    }
    
    .raincurtain-dropdown-menu.visible {
      opacity: 1;
      transform: scale(1) translateY(0);
      pointer-events: auto;
    }
    
    .raincurtain-dropdown-item {
      font-family: var(--md-font);
      font-size: 14px;
      line-height: 20px;
      padding: 10px 16px;
      margin: 2px 6px;
      border-radius: 6px;
      color: var(--md-on-surface);
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: space-between;
      user-select: none;
      transition: background-color 0.15s ease, color 0.15s ease;
    }
    
    .raincurtain-dropdown-item:hover {
      background-color: color-mix(in srgb, var(--md-on-surface) 8%, transparent);
    }
    
    .raincurtain-dropdown-item.selected {
      background-color: var(--md-primary-container);
      color: var(--md-on-primary-container);
      font-weight: 500;
    }
    
    .raincurtain-dropdown-item.selected:hover {
      background-color: color-mix(in srgb, var(--md-on-primary-container) 8%, var(--md-primary-container));
    }
    
    .raincurtain-dropdown-item.disabled {
      opacity: 0.38;
      pointer-events: none;
      cursor: not-allowed;
    }
    
    .raincurtain-dropdown-item-check {
      width: 16px;
      height: 16px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 12px;
      font-weight: bold;
      opacity: 0;
      transition: opacity 0.1s ease;
      color: var(--md-primary);
    }
    
    .raincurtain-dropdown-item.selected .raincurtain-dropdown-item-check {
      opacity: 1;
      color: var(--md-on-primary-container);
    }
    
    /* 原生 select 处于弹出状态时的辅助样式类 */
    select.raincurtain-select-open {
      outline: none;
    }
  `;

  function _applyTheme() {
    var el = document.getElementById('raincurtain-theme-style');
    if (!el) {
      el = document.createElement('style');
      el.id = 'raincurtain-theme-style';
    }
    el.textContent = cssText;
    // 若尚未插入 DOM 则插入
    if (!el.parentNode) {
      var parent = document.head || document.documentElement;
      if (parent) {
        parent.prepend(el);  // 插入最前端，方便被插件覆盖
      }
    }
  }

  // 立即尝试插入（如果挂载点已就绪）
  var _parent = document.head || document.documentElement;
  if (_parent) {
    _applyTheme();
  } else {
    // AT_DOCUMENT_START 阶段 DOM 完全为空，监听直到 <html>/<head> 出现
    var _obs = new MutationObserver(function() {
      if (document.head || document.documentElement) {
        _obs.disconnect();
        _applyTheme();
      }
    });
    _obs.observe(document, { childList: true, subtree: true });
  }

  // ===== 拦截原生 select 弹出列表并显示自定义 MD3 下拉浮层 =====
  function _setupSelectInterceptor() {
    var activeMenu = null;
    var activeSelect = null;
    var transitionTimeout = null;

    function getOrCreateMenu() {
      var menu = document.getElementById('raincurtain-global-dropdown');
      if (!menu) {
        menu = document.createElement('ul');
        menu.id = 'raincurtain-global-dropdown';
        menu.className = 'raincurtain-dropdown-menu';
        document.body.appendChild(menu);
      }
      return menu;
    }

    function closeMenu() {
      if (activeMenu) {
        var menu = activeMenu;
        var select = activeSelect;
        
        menu.classList.remove('visible');
        if (select) {
          select.classList.remove('raincurtain-select-open');
        }
        
        if (transitionTimeout) clearTimeout(transitionTimeout);
        
        transitionTimeout = setTimeout(function() {
          menu.classList.remove('show');
        }, 150);
        
        activeMenu = null;
        activeSelect = null;
      }
    }

    function handleSelectClick(e) {
      var select = e.target;
      if (!select || select.tagName !== 'SELECT') return;

      if (select.disabled) {
        e.preventDefault();
        return;
      }

      e.preventDefault();

      if (activeSelect === select) {
        closeMenu();
        return;
      }

      closeMenu();

      activeSelect = select;
      select.classList.add('raincurtain-select-open');

      var menu = getOrCreateMenu();
      menu.innerHTML = '';

      var options = select.options;
      for (var i = 0; i < options.length; i++) {
        var opt = options[i];
        var li = document.createElement('li');
        li.className = 'raincurtain-dropdown-item';
        if (opt.disabled) li.classList.add('disabled');
        if (opt.selected) li.classList.add('selected');

        var textSpan = document.createElement('span');
        textSpan.textContent = opt.text;
        li.appendChild(textSpan);

        var checkSpan = document.createElement('span');
        checkSpan.className = 'raincurtain-dropdown-item-check';
        checkSpan.textContent = '✓';
        li.appendChild(checkSpan);

        (function(index) {
          li.addEventListener('click', function(itemEvent) {
            itemEvent.stopPropagation();
            if (select.selectedIndex !== index) {
              select.selectedIndex = index;
              select.dispatchEvent(new Event('input', { bubbles: true }));
              select.dispatchEvent(new Event('change', { bubbles: true }));
            }
            closeMenu();
          });
        })(i);

        menu.appendChild(li);
      }

      var rect = select.getBoundingClientRect();
      var scrollTop = window.pageYOffset || document.documentElement.scrollTop;
      var scrollLeft = window.pageXOffset || document.documentElement.scrollLeft;

      var top = rect.bottom + scrollTop;
      var left = rect.left + scrollLeft;
      var width = rect.width;

      if (width < 120) {
        width = 120;
      }

      if (transitionTimeout) clearTimeout(transitionTimeout);
      menu.style.display = 'block';
      menu.classList.add('show');
      menu.classList.remove('visible');
      menu.style.left = '0px';
      menu.style.top = '0px';
      menu.style.width = width + 'px';

      var menuHeight = menu.offsetHeight;
      var windowHeight = window.innerHeight;

      if (rect.bottom + menuHeight > windowHeight && rect.top > menuHeight) {
        top = rect.top + scrollTop - menuHeight - 4;
        menu.style.transformOrigin = 'bottom left';
      } else {
        top = rect.bottom + scrollTop + 4;
        menu.style.transformOrigin = 'top left';
      }

      var windowWidth = window.innerWidth;
      if (rect.left + width > windowWidth) {
        left = windowWidth - width - 8;
      }
      if (left < 8) left = 8;

      menu.style.left = left + 'px';
      menu.style.top = top + 'px';

      requestAnimationFrame(function() {
        menu.classList.add('visible');
        activeMenu = menu;
      });
    }

    document.addEventListener('mousedown', handleSelectClick, true);
    document.addEventListener('touchstart', handleSelectClick, true);

    document.addEventListener('click', function(e) {
      if (activeMenu && !activeMenu.contains(e.target) && e.target !== activeSelect) {
        closeMenu();
      }
    }, true);

    window.addEventListener('scroll', function(e) {
      var menu = document.getElementById('raincurtain-global-dropdown');
      if (menu && menu.contains(e.target)) {
        return;
      }
      closeMenu();
    }, true);
    window.addEventListener('resize', closeMenu);
  }

  if (!window.__raincurtainSelectIntercepted) {
    window.__raincurtainSelectIntercepted = true;
    _setupSelectInterceptor();
  }
})();
''';
}
