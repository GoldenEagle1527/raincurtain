/// 注入 JS：修复 Windows WebView2 滚轮事件问题
const String scrollFixJS = r"""
(function() {
  if (window.__raincurtain_scroll_fix_applied__) return;
  window.__raincurtain_scroll_fix_applied__ = true;

  var SCROLL_STEP = 100;

  document.addEventListener('wheel', function(e) {
    // 检查事件目标是否在声明了 data-raincurtain-wheel-capture 的元素内
    // 如果是,则跳过 scrollFix,让组件自行处理滚轮事件
    var el = e.target;
    while (el) {
      if (el.dataset && el.dataset.raincurtainWheelCapture !== undefined) {
        return;
      }
      el = el.parentElement;
    }

    var target = e.target;
    var scrollable = null;

    // 向上查找第一个可滚动的父元素
    while (target && target !== document.body) {
      var style = window.getComputedStyle(target);
      var overflowY = style.overflowY;
      var canScroll = (overflowY === 'auto' || overflowY === 'scroll');
      if (canScroll && target.scrollHeight > target.clientHeight) {
        scrollable = target;
        break;
      }
      target = target.parentElement;
    }

    if (!scrollable) {
      var root = document.documentElement;
      if (root.scrollHeight > root.clientHeight) {
        scrollable = root;
      }
    }

    if (!scrollable) return;

    e.preventDefault();
    e.stopPropagation();

    var delta = e.deltaY > 0 ? SCROLL_STEP : -SCROLL_STEP;
    scrollable.scrollBy({ top: delta, behavior: 'auto' });
  }, { passive: false, capture: true });
})();
""";
