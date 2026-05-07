# 插件代码架构参考

本文档提供 Rain Curtain 插件开发的架构模式、代码骨架和正反对比示例。以下示例基于一个中等复杂度的插件场景，**仅作为参考而非固定模板**。实际拆分粒度应根据插件复杂度灵活调整——简单插件可合并职责领域，复杂插件应按子模块进一步细分。

---

## 一、文件拆分示例

以一个中等复杂度插件（画廊浏览 + 详情弹窗 + 收藏功能）为场景，展示一种可行的文件组织方式。更复杂的插件可能需要将 `api.js` 拆分为 `api/wallpaper.js` 和 `api/favorites.js`，或将 `ui.js` 拆分为 `ui/gallery.js` 和 `ui/detail.js` 等。

### 插件目录结构

```
my-plugin/
├── manifest.yml
├── index.html
├── styles/
│   └── theme.css
└── scripts/
    ├── utils.js        # 纯工具函数（无依赖）
    ├── state.js        # 集中状态管理（依赖 utils）
    ├── api.js          # 数据层：API 调用 + 持久化（依赖 state）
    ├── ui.js           # UI 层：DOM 创建 + 渲染（依赖 state, utils）
    └── app.js          # 入口：初始化 + 事件绑定 + 模块协调（依赖全部）
```

### index.html 中的加载顺序

```html
<!-- 按依赖顺序加载：无依赖 → 被依赖 → 依赖方 → 入口 -->
<script src="scripts/utils.js"></script>
<script src="scripts/state.js"></script>
<script src="scripts/api.js"></script>
<script src="scripts/ui.js"></script>
<script src="scripts/app.js"></script>
```

或使用 ES Module：

```html
<script type="module" src="scripts/app.js"></script>
```

---

## 二、各层代码骨架

### utils.js — 纯工具函数

该文件中的所有函数必须是纯函数：无副作用、不依赖外部状态、不操作 DOM。

```javascript
// scripts/utils.js
'use strict';

var Utils = (function () {

  var BING_BASE = 'https://www.bing.com';

  /**
   * 格式化日期字符串 "20260505" → "2026年05月05日"
   */
  function formatDate(dateStr) {
    if (!dateStr || dateStr.length !== 8) return dateStr || '';
    return dateStr.slice(0, 4) + '年'
         + dateStr.slice(4, 6) + '月'
         + dateStr.slice(6, 8) + '日';
  }

  /**
   * 构建必应图片完整 URL
   * @param {string} urlbase - 图片 urlbase 字段
   * @param {'thumb'|'hd'|'uhd'} quality - 图片质量等级
   * @returns {string} 完整图片 URL
   */
  function buildImageUrl(urlbase, quality) {
    var suffixMap = {
      uhd: '_UHD.jpg',
      hd: '_1920x1080.jpg',
      thumb: '_800x480.jpg',
    };
    return BING_BASE + urlbase + (suffixMap[quality] || suffixMap.thumb);
  }

  /**
   * HTML 转义，防止 XSS
   */
  function escapeHtml(text) {
    var div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  /**
   * 生成下载文件名
   */
  function buildFileName(startdate, urlbase) {
    var date = startdate || 'bing';
    var name = urlbase ? urlbase.split('.')[1] : 'wallpaper';
    return 'bing_' + date + '_' + (name || 'wallpaper') + '.jpg';
  }

  return {
    BING_BASE: BING_BASE,
    formatDate: formatDate,
    buildImageUrl: buildImageUrl,
    escapeHtml: escapeHtml,
    buildFileName: buildFileName,
  };

})();
```

**要点：**
- 所有函数接受参数、返回结果，不访问任何外部变量
- 常量定义在此模块中并导出
- 不依赖 DOM、不依赖 state、不依赖 RainCurtain API

---

### state.js — 集中状态管理

该文件负责定义应用状态和状态变更方法。禁止在此文件中操作 DOM 或调用 API。

```javascript
// scripts/state.js
'use strict';

var AppState = (function () {

  var state = {
    galleryImages: [],
    favorites: [],
    currentTab: 'gallery',
    currentIdx: 0,
    isLoading: false,
    hasMore: true,
    detailIndex: -1,
    detailSource: 'gallery',
  };

  /** 获取当前状态的只读快照 */
  function get() {
    return state;
  }

  /** 追加画廊图片（自动去重） */
  function appendGalleryImages(newImages) {
    var existing = {};
    state.galleryImages.forEach(function (img) {
      existing[img.urlbase] = true;
    });
    var unique = newImages.filter(function (img) {
      return !existing[img.urlbase];
    });
    state.galleryImages = state.galleryImages.concat(unique);
    return unique;
  }

  /** 推进分页偏移量 */
  function advancePage(pageSize) {
    state.currentIdx += pageSize;
  }

  /** 设置加载状态 */
  function setLoading(loading) {
    state.isLoading = loading;
  }

  /** 标记已无更多数据 */
  function setNoMore() {
    state.hasMore = false;
  }

  /** 检查图片是否已收藏 */
  function isFavorited(img) {
    return state.favorites.some(function (f) {
      return f.urlbase === img.urlbase;
    });
  }

  /** 添加收藏，返回 true */
  function addFavorite(img) {
    state.favorites.unshift({
      url: img.url,
      urlbase: img.urlbase,
      title: img.title,
      copyright: img.copyright,
      startdate: img.startdate,
    });
    return true;
  }

  /** 移除收藏，返回 true；若未找到返回 false */
  function removeFavorite(img) {
    var idx = state.favorites.findIndex(function (f) {
      return f.urlbase === img.urlbase;
    });
    if (idx < 0) return false;
    state.favorites.splice(idx, 1);
    return true;
  }

  /** 设置收藏列表（初始化加载时使用） */
  function setFavorites(favs) {
    state.favorites = favs || [];
  }

  /** 切换当前 Tab */
  function switchTab(tab) {
    state.currentTab = tab;
  }

  /** 设置详情弹窗状态 */
  function setDetail(index, source) {
    state.detailIndex = index;
    state.detailSource = source || 'gallery';
  }

  /** 清除详情弹窗状态 */
  function clearDetail() {
    state.detailIndex = -1;
  }

  /** 获取详情弹窗对应的图片列表 */
  function getDetailList() {
    return state.detailSource === 'favorites'
      ? state.favorites
      : state.galleryImages;
  }

  return {
    get: get,
    appendGalleryImages: appendGalleryImages,
    advancePage: advancePage,
    setLoading: setLoading,
    setNoMore: setNoMore,
    isFavorited: isFavorited,
    addFavorite: addFavorite,
    removeFavorite: removeFavorite,
    setFavorites: setFavorites,
    switchTab: switchTab,
    setDetail: setDetail,
    clearDetail: clearDetail,
    getDetailList: getDetailList,
  };

})();
```

**要点：**
- 状态变更只能通过导出的方法，禁止外部直接 `state.xxx = ...`
- 每个方法职责单一，名称清晰描述行为
- 不包含任何 DOM 操作、API 调用或副作用

---

### api.js — 数据层

该文件负责所有外部数据交互：API 调用和 RainCurtain.storage 持久化读写。禁止操作 DOM。

```javascript
// scripts/api.js
'use strict';

var Api = (function () {

  var API_URL = Utils.BING_BASE + '/HPImageArchive.aspx';
  var PAGE_SIZE = 8;

  /**
   * 从必应 API 获取壁纸列表
   * @param {number} idx - 分页偏移量
   * @param {string} market - 市场代码
   * @returns {Promise<Array>} 图片数据数组
   */
  async function fetchWallpapers(idx, market) {
    var url = API_URL
      + '?format=js&idx=' + idx
      + '&n=' + PAGE_SIZE
      + '&mkt=' + encodeURIComponent(market);
    var response = await fetch(url);
    if (!response.ok) throw new Error('API request failed: ' + response.status);
    var data = await response.json();
    return data.images || [];
  }

  /** 从存储加载收藏列表 */
  async function loadFavorites() {
    var data = await RainCurtain.storage.get('favorites');
    return data || [];
  }

  /** 保存收藏列表到存储 */
  async function saveFavorites(favorites) {
    await RainCurtain.storage.set('favorites', favorites);
  }

  /** 读取 market 输入配置 */
  async function loadMarketConfig() {
    var market = await RainCurtain.storage.get('input_market');
    return (market && typeof market === 'string') ? market : 'zh-CN';
  }

  /** 写出 selected_wallpaper 输出 */
  async function emitSelectedWallpaper(img) {
    if (!img) return;
    await RainCurtain.storage.set('output_selected_wallpaper', {
      title: img.title || '',
      copyright: img.copyright || '',
      date: img.startdate || '',
      url: Utils.BING_BASE + (img.url || img.urlbase + '_1920x1080.jpg'),
    });
  }

  /** 写出 favorites 输出 */
  async function emitFavorites(favorites) {
    await RainCurtain.storage.set('output_favorites', favorites);
  }

  return {
    PAGE_SIZE: PAGE_SIZE,
    fetchWallpapers: fetchWallpapers,
    loadFavorites: loadFavorites,
    saveFavorites: saveFavorites,
    loadMarketConfig: loadMarketConfig,
    emitSelectedWallpaper: emitSelectedWallpaper,
    emitFavorites: emitFavorites,
  };

})();
```

**要点：**
- 所有函数返回 Promise，调用方负责 try/catch
- 不操作 DOM、不修改 state（由调用方在 app.js 中协调）
- 常量（如 PAGE_SIZE）定义在此模块并导出

---

### ui.js — UI 层

该文件负责所有 DOM 创建、查询和更新。禁止调用 API 或修改应用状态。

```javascript
// scripts/ui.js
'use strict';

var UI = (function () {

  // DOM 引用集中管理（模块内部，不暴露给外部）
  var elements = {
    galleryWaterfall: document.getElementById('waterfall-gallery'),
    favoritesWaterfall: document.getElementById('waterfall-favorites'),
    loadSentinel: document.getElementById('load-sentinel'),
    loadEnd: document.getElementById('load-end'),
    tabGallery: document.getElementById('tab-gallery'),
    tabFavorites: document.getElementById('tab-favorites'),
    emptyFavorites: document.getElementById('empty-favorites'),
    favCount: document.getElementById('fav-count'),
    detailOverlay: document.getElementById('detail-overlay'),
    detailImg: document.getElementById('detail-img'),
    detailTitle: document.getElementById('detail-title'),
    detailCopyright: document.getElementById('detail-copyright'),
    detailDate: document.getElementById('detail-date'),
    detailFavBtn: document.getElementById('detail-fav-btn'),
    detailExportBtn: document.getElementById('detail-export-btn'),
    toastContainer: document.getElementById('toast-container'),
  };

  // ---------- Toast ----------

  var TOAST_DURATION = 2000;
  var TOAST_FADE_OUT = 300;

  function showToast(message) {
    var toast = document.createElement('div');
    toast.className = 'toast';
    toast.textContent = message;
    elements.toastContainer.appendChild(toast);

    requestAnimationFrame(function () {
      toast.classList.add('show');
    });

    setTimeout(function () {
      toast.classList.remove('show');
      setTimeout(function () {
        if (toast.parentNode) toast.parentNode.removeChild(toast);
      }, TOAST_FADE_OUT);
    }, TOAST_DURATION);
  }

  // ---------- 卡片创建 ----------

  /**
   * 创建单个壁纸卡片 DOM 元素
   * @param {object} img - 图片数据
   * @param {boolean} isFav - 是否已收藏
   * @param {Function} onClick - 点击回调
   * @returns {HTMLElement} 卡片元素
   */
  function createCard(img, isFav, onClick) {
    var item = document.createElement('div');
    item.className = 'waterfall-item';

    // 收藏图标
    var favIcon = document.createElement('div');
    favIcon.className = isFav ? 'card-fav-icon is-fav' : 'card-fav-icon';
    var heart = document.createElement('span');
    heart.className = 'material-icons';
    heart.textContent = 'favorite';
    favIcon.appendChild(heart);
    item.appendChild(favIcon);

    // 图片
    var image = document.createElement('img');
    image.src = Utils.buildImageUrl(img.urlbase, 'thumb');
    image.alt = img.title || '';
    image.loading = 'lazy';
    item.appendChild(image);

    // 信息
    var info = document.createElement('div');
    info.className = 'card-info';

    var title = document.createElement('div');
    title.className = 'card-title';
    title.textContent = img.title || '';
    info.appendChild(title);

    var date = document.createElement('div');
    date.className = 'card-date';
    date.textContent = Utils.formatDate(img.startdate);
    info.appendChild(date);

    item.appendChild(info);

    // 事件绑定
    item.addEventListener('click', function () {
      onClick(img);
    });

    return item;
  }

  /**
   * 批量渲染卡片到容器
   * @param {Array} images - 图片数据数组
   * @param {HTMLElement} container - 目标容器
   * @param {Function} isFavFn - 检查是否收藏的函数
   * @param {Function} onClickFn - 卡片点击回调
   */
  function renderCards(images, container, isFavFn, onClickFn) {
    images.forEach(function (img) {
      var card = createCard(img, isFavFn(img), onClickFn);
      container.appendChild(card);
    });
  }

  /** 将卡片渲染到画廊容器 */
  function renderGalleryCards(images, isFavFn, onClickFn) {
    renderCards(images, elements.galleryWaterfall, isFavFn, onClickFn);
  }

  /** 清空并重新渲染收藏页 */
  function renderFavoritesPage(favorites, isFavFn, onClickFn) {
    elements.favoritesWaterfall.innerHTML = '';
    if (favorites.length === 0) {
      elements.emptyFavorites.style.display = '';
      return;
    }
    elements.emptyFavorites.style.display = 'none';
    renderCards(favorites, elements.favoritesWaterfall, isFavFn, onClickFn);
  }

  // ---------- 骨架屏 ----------

  var SKELETON_HEIGHTS = [180, 220, 160, 240, 200, 190];

  function showSkeleton() {
    var container = document.createElement('div');
    container.className = 'skeleton-container';

    SKELETON_HEIGHTS.forEach(function (h) {
      var item = document.createElement('div');
      item.className = 'skeleton-item';

      var imgPlaceholder = document.createElement('div');
      imgPlaceholder.className = 'skeleton-img';
      imgPlaceholder.style.height = h + 'px';
      item.appendChild(imgPlaceholder);

      var textBlock = document.createElement('div');
      textBlock.className = 'skeleton-text';
      var line1 = document.createElement('div');
      line1.className = 'skeleton-line';
      var line2 = document.createElement('div');
      line2.className = 'skeleton-line';
      textBlock.appendChild(line1);
      textBlock.appendChild(line2);
      item.appendChild(textBlock);

      container.appendChild(item);
    });

    elements.galleryWaterfall.innerHTML = '';
    elements.galleryWaterfall.appendChild(container);
  }

  function clearGallery() {
    elements.galleryWaterfall.innerHTML = '';
  }

  // ---------- 加载状态 ----------

  function showLoadingSentinel() {
    elements.loadSentinel.classList.remove('hidden');
  }

  function hideLoadingSentinel() {
    elements.loadSentinel.style.display = 'none';
  }

  function showLoadEnd() {
    elements.loadEnd.style.display = '';
  }

  // ---------- Tab ----------

  function activateTab(tab) {
    document.querySelectorAll('.tab-btn').forEach(function (btn) {
      btn.classList.toggle('active', btn.getAttribute('data-tab') === tab);
    });

    if (tab === 'gallery') {
      elements.tabGallery.style.display = '';
      elements.tabFavorites.style.display = 'none';
    } else {
      elements.tabGallery.style.display = 'none';
      elements.tabFavorites.style.display = '';
    }
  }

  // ---------- 收藏徽章 ----------

  function updateFavCount(count) {
    if (count > 0) {
      elements.favCount.textContent = count;
      elements.favCount.style.display = '';
    } else {
      elements.favCount.style.display = 'none';
    }
  }

  // ---------- 画廊卡片收藏图标刷新 ----------

  function refreshGalleryFavIcons(galleryImages, isFavFn) {
    var items = elements.galleryWaterfall.querySelectorAll('.waterfall-item');
    items.forEach(function (item, idx) {
      var img = galleryImages[idx];
      if (!img) return;
      var icon = item.querySelector('.card-fav-icon');
      if (icon) {
        icon.classList.toggle('is-fav', isFavFn(img));
      }
    });
  }

  // ---------- 详情弹窗 ----------

  function showDetailOverlay() {
    elements.detailOverlay.classList.add('visible');
    document.body.style.overflow = 'hidden';
  }

  function hideDetailOverlay() {
    elements.detailOverlay.classList.remove('visible');
    document.body.style.overflow = '';
  }

  function isDetailVisible() {
    return elements.detailOverlay.classList.contains('visible');
  }

  function updateDetailContent(img) {
    elements.detailImg.classList.add('loading');
    elements.detailImg.src = Utils.buildImageUrl(img.urlbase, 'hd');
    elements.detailImg.onload = function () {
      elements.detailImg.classList.remove('loading');
    };
    elements.detailImg.onerror = function () {
      elements.detailImg.src = Utils.buildImageUrl(img.urlbase, 'thumb');
      elements.detailImg.classList.remove('loading');
    };

    elements.detailTitle.textContent = img.title || '';
    elements.detailCopyright.textContent = img.copyright || '';
    elements.detailDate.textContent = Utils.formatDate(img.startdate);
  }

  function updateDetailFavButton(isFav) {
    var iconSpan = elements.detailFavBtn.querySelector('.material-icons');
    var textSpan = elements.detailFavBtn.querySelectorAll('span')[1];

    if (isFav) {
      elements.detailFavBtn.classList.add('is-fav');
      iconSpan.textContent = 'favorite';
      if (textSpan) textSpan.textContent = '已收藏';
    } else {
      elements.detailFavBtn.classList.remove('is-fav');
      iconSpan.textContent = 'favorite_border';
      if (textSpan) textSpan.textContent = '收藏';
    }
  }

  function setExportLoading(loading) {
    var iconSpan = elements.detailExportBtn.querySelector('.material-icons');
    if (loading) {
      elements.detailExportBtn.classList.add('loading');
      iconSpan.textContent = 'hourglass_empty';
    } else {
      elements.detailExportBtn.classList.remove('loading');
      iconSpan.textContent = 'download';
    }
  }

  // ---------- 事件绑定入口 ----------

  /**
   * 绑定所有 UI 事件，接受回调对象
   * @param {object} handlers - { onTabSwitch, onDetailClose, onDetailNav, onDetailFav, onDetailExport, onOverlayClick }
   */
  function bindEvents(handlers) {
    // Tab 按钮
    document.querySelectorAll('.tab-btn').forEach(function (btn) {
      btn.addEventListener('click', function () {
        handlers.onTabSwitch(btn.getAttribute('data-tab'));
      });
    });

    // 详情弹窗关闭
    var closeBtn = elements.detailOverlay.querySelector('.detail-close');
    if (closeBtn) {
      closeBtn.addEventListener('click', handlers.onDetailClose);
    }

    // 详情弹窗导航
    var prevBtn = elements.detailOverlay.querySelector('.detail-nav.prev');
    var nextBtn = elements.detailOverlay.querySelector('.detail-nav.next');
    if (prevBtn) prevBtn.addEventListener('click', function () { handlers.onDetailNav(-1); });
    if (nextBtn) nextBtn.addEventListener('click', function () { handlers.onDetailNav(1); });

    // 详情弹窗收藏
    elements.detailFavBtn.addEventListener('click', handlers.onDetailFav);

    // 详情弹窗导出
    elements.detailExportBtn.addEventListener('click', handlers.onDetailExport);

    // 点击遮罩背景关闭
    elements.detailOverlay.addEventListener('click', function (e) {
      if (e.target === elements.detailOverlay
          || e.target.classList.contains('detail-body')
          || e.target.classList.contains('detail-img-wrapper')) {
        handlers.onDetailClose();
      }
    });
  }

  /** 获取加载哨兵元素（供 IntersectionObserver 使用） */
  function getLoadSentinel() {
    return elements.loadSentinel;
  }

  /** 获取详情弹窗 body 元素（供触摸手势使用） */
  function getDetailBody() {
    return elements.detailOverlay.querySelector('.detail-body');
  }

  return {
    showToast: showToast,
    createCard: createCard,
    renderGalleryCards: renderGalleryCards,
    renderFavoritesPage: renderFavoritesPage,
    showSkeleton: showSkeleton,
    clearGallery: clearGallery,
    showLoadingSentinel: showLoadingSentinel,
    hideLoadingSentinel: hideLoadingSentinel,
    showLoadEnd: showLoadEnd,
    activateTab: activateTab,
    updateFavCount: updateFavCount,
    refreshGalleryFavIcons: refreshGalleryFavIcons,
    showDetailOverlay: showDetailOverlay,
    hideDetailOverlay: hideDetailOverlay,
    isDetailVisible: isDetailVisible,
    updateDetailContent: updateDetailContent,
    updateDetailFavButton: updateDetailFavButton,
    setExportLoading: setExportLoading,
    bindEvents: bindEvents,
    getLoadSentinel: getLoadSentinel,
    getDetailBody: getDetailBody,
  };

})();
```

**要点：**
- DOM 引用集中在 `elements` 对象中，不暴露给外部
- 所有渲染函数只接受数据参数，不直接从 state 读取
- 事件绑定通过 `bindEvents` 接受回调对象，实现 UI 与业务逻辑解耦
- 使用 `createElement` 而非 `innerHTML`

---

### app.js — 入口与协调

该文件是唯一允许同时调用 state、api、ui 模块的地方，负责初始化和协调数据流。

```javascript
// scripts/app.js
'use strict';

(function () {

  var market = 'zh-CN';

  // ---------- 业务逻辑 ----------

  async function loadMore() {
    var s = AppState.get();
    if (s.isLoading || !s.hasMore) return;

    AppState.setLoading(true);
    UI.showLoadingSentinel();

    try {
      var images = await Api.fetchWallpapers(s.currentIdx, market);

      if (images.length === 0) {
        AppState.setNoMore();
        UI.hideLoadingSentinel();
        UI.showLoadEnd();
        return;
      }

      var unique = AppState.appendGalleryImages(images);
      AppState.advancePage(Api.PAGE_SIZE);
      UI.renderGalleryCards(unique, AppState.isFavorited, handleCardClick);

      if (images.length < Api.PAGE_SIZE) {
        AppState.setNoMore();
        UI.hideLoadingSentinel();
        UI.showLoadEnd();
      }
    } catch (err) {
      console.error('Failed to load wallpapers:', err);
      UI.showToast('加载失败，请检查网络连接');
    } finally {
      AppState.setLoading(false);
    }
  }

  function handleCardClick(img) {
    var s = AppState.get();
    var list = s.currentTab === 'favorites' ? s.favorites : s.galleryImages;
    var index = list.indexOf(img);
    if (index < 0) return;
    showDetail(index, s.currentTab === 'favorites' ? 'favorites' : 'gallery');
  }

  function showDetail(index, source) {
    AppState.setDetail(index, source);
    var list = AppState.getDetailList();
    var img = list[index];
    if (!img) return;

    UI.updateDetailContent(img);
    UI.updateDetailFavButton(AppState.isFavorited(img));
    UI.showDetailOverlay();
    Api.emitSelectedWallpaper(img).catch(function () {});
  }

  function handleDetailClose() {
    UI.hideDetailOverlay();
    AppState.clearDetail();
  }

  function handleDetailNav(direction) {
    var s = AppState.get();
    var list = AppState.getDetailList();
    var newIndex = s.detailIndex + direction;
    if (newIndex < 0 || newIndex >= list.length) return;

    AppState.setDetail(newIndex, s.detailSource);
    var img = list[newIndex];
    UI.updateDetailContent(img);
    UI.updateDetailFavButton(AppState.isFavorited(img));
    Api.emitSelectedWallpaper(img).catch(function () {});
  }

  async function handleToggleFavorite() {
    var list = AppState.getDetailList();
    var s = AppState.get();
    var img = list[s.detailIndex];
    if (!img) return;

    var wasFav = AppState.isFavorited(img);
    if (wasFav) {
      AppState.removeFavorite(img);
    } else {
      AppState.addFavorite(img);
    }

    try {
      await Api.saveFavorites(AppState.get().favorites);
      await Api.emitFavorites(AppState.get().favorites);
    } catch (err) {
      console.error('Failed to save favorites:', err);
    }

    UI.updateDetailFavButton(!wasFav);
    UI.updateFavCount(AppState.get().favorites.length);
    UI.refreshGalleryFavIcons(AppState.get().galleryImages, AppState.isFavorited);
    UI.showToast(wasFav ? '已取消收藏' : '已添加到收藏');

    if (AppState.get().currentTab === 'favorites') {
      UI.renderFavoritesPage(AppState.get().favorites, AppState.isFavorited, handleCardClick);
    }
  }

  async function handleExport() {
    var list = AppState.getDetailList();
    var s = AppState.get();
    var img = list[s.detailIndex];
    if (!img) return;

    UI.setExportLoading(true);

    try {
      var hdUrl = Utils.buildImageUrl(img.urlbase, 'hd');
      var response = await fetch(hdUrl);
      if (!response.ok) throw new Error('Download failed');
      var blob = await response.blob();
      var fileName = Utils.buildFileName(img.startdate, img.urlbase);

      var saved = await trySaveWithFilePicker(blob, fileName);
      if (!saved) {
        downloadViaAnchor(blob, fileName);
      }
    } catch (err) {
      console.error('Export failed:', err);
      UI.showToast('导出失败，请稍后重试');
    } finally {
      UI.setExportLoading(false);
    }
  }

  async function trySaveWithFilePicker(blob, fileName) {
    if (!window.showSaveFilePicker) return false;
    try {
      var handle = await window.showSaveFilePicker({
        suggestedName: fileName,
        types: [{ description: 'JPEG', accept: { 'image/jpeg': ['.jpg', '.jpeg'] } }],
      });
      var writable = await handle.createWritable();
      await writable.write(blob);
      await writable.close();
      UI.showToast('壁纸已保存');
      return true;
    } catch (err) {
      if (err.name === 'AbortError') {
        UI.showToast('已取消导出');
        return true; // 用户主动取消，不走降级
      }
      return false;
    }
  }

  function downloadViaAnchor(blob, fileName) {
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = fileName;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
    UI.showToast('壁纸已开始下载');
  }

  function handleTabSwitch(tab) {
    AppState.switchTab(tab);
    UI.activateTab(tab);
    if (tab === 'favorites') {
      UI.renderFavoritesPage(AppState.get().favorites, AppState.isFavorited, handleCardClick);
    }
  }

  // ---------- 基础设施 ----------

  function setupInfiniteScroll() {
    var observer = new IntersectionObserver(function (entries) {
      var s = AppState.get();
      if (entries[0].isIntersecting && !s.isLoading && s.hasMore && s.currentTab === 'gallery') {
        loadMore();
      }
    }, { threshold: 0.1 });
    observer.observe(UI.getLoadSentinel());
  }

  function setupKeyboard() {
    document.addEventListener('keydown', function (e) {
      if (!UI.isDetailVisible()) return;
      switch (e.key) {
        case 'Escape': handleDetailClose(); break;
        case 'ArrowLeft': handleDetailNav(-1); break;
        case 'ArrowRight': handleDetailNav(1); break;
      }
    });
  }

  function setupTouch() {
    var startX = 0;
    var startY = 0;
    var body = UI.getDetailBody();
    var MIN_SWIPE = 60;

    body.addEventListener('touchstart', function (e) {
      startX = e.touches[0].clientX;
      startY = e.touches[0].clientY;
    }, { passive: true });

    body.addEventListener('touchend', function (e) {
      var dx = e.changedTouches[0].clientX - startX;
      var dy = e.changedTouches[0].clientY - startY;
      if (Math.abs(dx) > MIN_SWIPE && Math.abs(dx) > Math.abs(dy)) {
        handleDetailNav(dx > 0 ? -1 : 1);
      }
    }, { passive: true });
  }

  // ---------- 初始化 ----------

  async function init() {
    try {
      market = await Api.loadMarketConfig();
    } catch (e) { /* use default */ }

    UI.showSkeleton();

    try {
      var favs = await Api.loadFavorites();
      AppState.setFavorites(favs);
      Api.emitFavorites(favs).catch(function () {});
    } catch (err) {
      console.error('Failed to load favorites:', err);
    }

    UI.updateFavCount(AppState.get().favorites.length);
    UI.clearGallery();
    await loadMore();

    UI.bindEvents({
      onTabSwitch: handleTabSwitch,
      onDetailClose: handleDetailClose,
      onDetailNav: handleDetailNav,
      onDetailFav: handleToggleFavorite,
      onDetailExport: handleExport,
    });

    setupInfiniteScroll();
    setupKeyboard();
    setupTouch();
  }

  init();

})();
```

**要点：**
- 这是唯一跨层调用的文件，负责协调 state → api → ui 的数据流
- 所有事件处理器在此定义，通过 `UI.bindEvents()` 注入
- 各 handler 函数职责明确，长度控制在 30 行以内
- HTML 中不再需要任何 `onclick` 属性

---

## 三、反模式对照表

### 1. 单体文件 vs 文件拆分

```javascript
// ❌ 所有逻辑在一个 IIFE 中（686 行）
(function () {
  var state = { /* ... */ };
  var $el = document.getElementById('xxx');
  async function fetchData() { /* ... */ }
  function renderUI() { /* ... */ }
  function handleClick() { /* ... */ }
  async function init() { /* ... */ }
  init();
})();

// ✅ 按职责拆分为独立模块
// utils.js  — 纯函数
// state.js  — 状态管理
// api.js    — 数据交互
// ui.js     — DOM 操作
// app.js    — 初始化与协调
```

### 2. innerHTML 拼接 vs createElement 构建

```javascript
// ❌ 字符串拼接 HTML（XSS 风险、难维护）
item.innerHTML =
  '<div class="' + favClass + '">' +
  '<span class="material-icons">favorite</span></div>' +
  '<img src="' + url + '" alt="' + escapeHtml(title) + '" />';

// ✅ 用 createElement 构建 DOM 树
var item = document.createElement('div');
item.className = 'waterfall-item';

var favIcon = document.createElement('div');
favIcon.className = isFav ? 'card-fav-icon is-fav' : 'card-fav-icon';
var heart = document.createElement('span');
heart.className = 'material-icons';
heart.textContent = 'favorite';
favIcon.appendChild(heart);
item.appendChild(favIcon);

var image = document.createElement('img');
image.src = url;
image.alt = title;   // textContent/alt 自动转义
item.appendChild(image);
```

### 3. window 挂载 + onclick vs addEventListener

```html
<!-- ❌ HTML 内联事件 + window 挂载函数 -->
<button onclick="switchTab('gallery')">画廊</button>
<script>
  window.switchTab = function(tab) { /* ... */ };
</script>

<!-- ✅ HTML 无事件属性，JS 中用 addEventListener -->
<button class="tab-btn" data-tab="gallery">画廊</button>
<script>
  document.querySelectorAll('.tab-btn').forEach(function(btn) {
    btn.addEventListener('click', function() {
      handleTabSwitch(btn.getAttribute('data-tab'));
    });
  });
</script>
```

### 4. 函数职责过多 vs 单一职责

```javascript
// ❌ toggleFavorite 同时操作数据 + 存储 + 4 处 DOM 更新
function toggleFavorite(img) {
  // 修改 state.favorites（数据层）
  // 调用 RainCurtain.storage.set（持久化层）
  // 更新按钮样式（UI 层）
  // 刷新卡片图标（UI 层）
  // 显示 toast（UI 层）
  // 判断是否刷新收藏页（UI 层）
}

// ✅ 拆分为数据操作 + 协调函数
// state.js 中：addFavorite(img) / removeFavorite(img) — 纯状态变更
// api.js 中：saveFavorites(favs) — 纯持久化
// app.js 中：handleToggleFavorite() — 协调各层
```

### 5. 魔法数字 vs 命名常量

```javascript
// ❌ 魔法数字散落在代码中
if (Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy)) { /* ... */ }
setTimeout(function() { /* ... */ }, 300);
var heights = [180, 220, 160, 240, 200, 190];

// ✅ 提取为命名常量
var MIN_SWIPE_DISTANCE = 60;
var TOAST_FADE_OUT_MS = 300;
var SKELETON_HEIGHTS = [180, 220, 160, 240, 200, 190];

if (Math.abs(dx) > MIN_SWIPE_DISTANCE && Math.abs(dx) > Math.abs(dy)) { /* ... */ }
setTimeout(function() { /* ... */ }, TOAST_FADE_OUT_MS);
```

### 6. 直接修改 state vs 状态变更函数

```javascript
// ❌ 在业务逻辑中直接修改 state 属性
state.isLoading = true;
state.galleryImages = state.galleryImages.concat(newImages);
state.currentIdx += 8;

// ✅ 通过专用函数变更状态
AppState.setLoading(true);
AppState.appendGalleryImages(newImages);
AppState.advancePage(Api.PAGE_SIZE);
```

---

## 四、ES Module 模式参考（可选）

对于更现代的插件，可使用 ES Module 替代 IIFE 模式：

```javascript
// scripts/utils.js
export const BING_BASE = 'https://www.bing.com';
export function formatDate(dateStr) { /* ... */ }
export function buildImageUrl(urlbase, quality) { /* ... */ }

// scripts/state.js
import { } from './utils.js'; // 如需引用常量
const state = { /* ... */ };
export function get() { return state; }
export function setLoading(v) { state.isLoading = v; }

// scripts/api.js
import { BING_BASE } from './utils.js';
export async function fetchWallpapers(idx, market) { /* ... */ }

// scripts/ui.js
import { formatDate, buildImageUrl } from './utils.js';
export function createCard(img, isFav, onClick) { /* ... */ }

// scripts/app.js
import * as AppState from './state.js';
import * as Api from './api.js';
import * as UI from './ui.js';
import * as Utils from './utils.js';

async function init() { /* ... */ }
init();
```

```html
<!-- index.html -->
<script type="module" src="scripts/app.js"></script>
```

**注意：** ES Module 模式下所有 `<script>` 标签必须设置 `type="module"`，且本地开发需要通过 HTTP 服务器访问（Rain Curtain 的 localhost 环境已满足此条件）。

---

## 五、事件通信模式（可选高级用法）

对于功能复杂的插件，可使用简单的发布-订阅模式解耦模块间通信：

```javascript
// scripts/events.js
var EventBus = (function () {
  var listeners = {};

  function on(event, callback) {
    if (!listeners[event]) listeners[event] = [];
    listeners[event].push(callback);
  }

  function off(event, callback) {
    if (!listeners[event]) return;
    listeners[event] = listeners[event].filter(function (cb) {
      return cb !== callback;
    });
  }

  function emit(event, data) {
    if (!listeners[event]) return;
    listeners[event].forEach(function (cb) {
      cb(data);
    });
  }

  return { on: on, off: off, emit: emit };
})();
```

使用示例：

```javascript
// state.js 中发出状态变更事件
function addFavorite(img) {
  state.favorites.unshift({ /* ... */ });
  EventBus.emit('favorites:changed', state.favorites);
}

// ui.js 中监听并更新 UI
EventBus.on('favorites:changed', function (favorites) {
  updateFavCount(favorites.length);
  refreshGalleryFavIcons(favorites);
});
```

此模式适用于模块间需要松耦合通信的场景，对于简单插件使用入口文件（app.js）直接协调即可。
