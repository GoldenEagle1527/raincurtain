import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'dialog_sync_bridge.dart';
/// 将 JS bridge 返回值规范为 bool（兼容 bool / 1 / "true"）。
@visibleForTesting
bool jsBridgeBoolTrue(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value == 1;
  if (value is String) return value == 'true' || value == '1';
  return false;
}

/// 浏览器 alert / confirm / prompt 拦截：JS 侧 MD3 弹窗 + WebView 原生钩子触发。
mixin DialogMixin {
  /// 注入 MD3 弹窗 CSS 与 window.__rainCurtainDialog API
  static const String polyfillJS = r"""
(function() {
  if (window.__raincurtainDialogPatched) return;
  window.__raincurtainDialogPatched = true;

  var DIALOG_CSS = `
    #raincurtain-dialog-root {
      position: fixed;
      inset: 0;
      z-index: 2147483646;
      display: none;
    }
    #raincurtain-dialog-root.open {
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .raincurtain-dialog-backdrop {
      position: absolute;
      inset: 0;
      background: color-mix(in srgb, var(--md-on-surface) 32%, transparent);
    }
    .raincurtain-dialog-card {
      position: relative;
      z-index: 2147483647;
      width: min(560px, calc(100vw - 48px));
      max-height: calc(100vh - 48px);
      overflow: auto;
      margin: 24px;
      padding: 24px;
      background: var(--md-surface-container-high);
      border: 1px solid var(--md-outline-variant);
      border-radius: 28px;
      box-shadow: var(--md-elevation-1);
      font-family: var(--md-font);
      color: var(--md-on-surface);
      box-sizing: border-box;
    }
    .raincurtain-dialog-message {
      font-size: 16px;
      line-height: 24px;
      white-space: pre-wrap;
      word-break: break-word;
      margin: 0 0 16px;
    }
    .raincurtain-dialog-input {
      display: block;
      width: 100%;
      box-sizing: border-box;
      margin: 0 0 20px;
      padding: 12px 16px;
      font-family: var(--md-font);
      font-size: 14px;
      line-height: 20px;
      color: var(--md-on-surface);
      background: color-mix(in srgb, var(--md-on-surface) 4%, var(--md-surface-container-high));
      border: 1px solid var(--md-outline-variant);
      border-radius: 8px;
      outline: none;
    }
    .raincurtain-dialog-input:focus {
      border-color: var(--md-primary);
      box-shadow: 0 0 0 1px var(--md-primary);
    }
    .raincurtain-dialog-actions {
      display: flex;
      justify-content: flex-end;
      gap: 8px;
      flex-wrap: wrap;
    }
    .raincurtain-dialog-btn {
      font-family: var(--md-font);
      font-size: 14px;
      line-height: 20px;
      padding: 10px 24px;
      border-radius: var(--md-radius-button, 20px);
      border: none;
      cursor: pointer;
      transition: background-color 0.15s ease, color 0.15s ease;
    }
    .raincurtain-dialog-btn-text {
      background: transparent;
      color: var(--md-primary);
    }
    .raincurtain-dialog-btn-text:hover {
      background: color-mix(in srgb, var(--md-on-surface) 8%, transparent);
    }
    .raincurtain-dialog-btn-filled {
      background: var(--md-primary);
      color: var(--md-on-primary);
    }
    .raincurtain-dialog-btn-filled:hover {
      background: color-mix(in srgb, var(--md-on-primary) 8%, var(--md-primary));
    }
  `;

  function injectStyles() {
    var style = document.getElementById('raincurtain-dialog-style');
    if (!style) {
      style = document.createElement('style');
      style.id = 'raincurtain-dialog-style';
      var parent = document.head || document.documentElement;
      if (parent) parent.appendChild(style);
    }
    style.textContent = DIALOG_CSS;
  }

  injectStyles();

  window.__rainCurtainDialog = {
    _queue: [],
    _active: null,
    _root: null,
    _savedOverflow: '',
    _keyHandler: null,

    showAlert: function(message) {
      var self = this;
      return this._enqueue('alert', { message: String(message == null ? '' : message) })
        .then(function() {});
    },

    showConfirm: function(message) {
      return this._enqueue('confirm', { message: String(message == null ? '' : message) });
    },

    showPrompt: function(message, defaultValue) {
      return this._enqueue('prompt', {
        message: String(message == null ? '' : message),
        defaultValue: defaultValue == null ? '' : String(defaultValue)
      });
    },

    _enqueue: function(type, options) {
      var self = this;
      return new Promise(function(resolve) {
        self._queue.push({ type: type, options: options, resolve: resolve });
        self._dequeue();
      });
    },

    _dequeue: function() {
      if (this._active || this._queue.length === 0) return;
      this._active = this._queue.shift();
      this._render(this._active);
    },

    _ensureRoot: function() {
      if (this._root && this._root.parentNode) return this._root;
      var root = document.getElementById('raincurtain-dialog-root');
      if (!root) {
        root = document.createElement('div');
        root.id = 'raincurtain-dialog-root';
        var mount = document.body || document.documentElement;
        mount.appendChild(root);
      }
      this._root = root;
      return root;
    },

    _close: function() {
      if (this._root) {
        this._root.innerHTML = '';
        this._root.classList.remove('open');
      }
      if (document.body) {
        document.body.style.overflow = this._savedOverflow || '';
      }
      if (this._keyHandler) {
        document.removeEventListener('keydown', this._keyHandler, true);
        this._keyHandler = null;
      }
    },

    _forceDismiss: function() {
      if (this._active) {
        var item = this._active;
        var type = item.type;
        if (type === 'alert') item.resolve(undefined);
        else if (type === 'confirm') item.resolve(false);
        else item.resolve(null);
        this._active = null;
      }
      while (this._queue.length > 0) {
        var queued = this._queue.shift();
        if (queued.type === 'alert') queued.resolve(undefined);
        else if (queued.type === 'confirm') queued.resolve(false);
        else queued.resolve(null);
      }
      this._close();
    },

    _render: function(item) {
      var self = this;

      function doRender() {
        injectStyles();
        var root = self._ensureRoot();
        root.innerHTML = '';
        root.classList.add('open');

        self._savedOverflow = document.body ? document.body.style.overflow : '';
        if (document.body) document.body.style.overflow = 'hidden';

        var type = item.type;
        var options = item.options;

        var backdrop = document.createElement('div');
        backdrop.className = 'raincurtain-dialog-backdrop';

        var card = document.createElement('div');
        card.className = 'raincurtain-dialog-card';
        card.setAttribute('role', 'dialog');
        card.setAttribute('aria-modal', 'true');

        var messageEl = document.createElement('div');
        messageEl.className = 'raincurtain-dialog-message';
        messageEl.textContent = options.message;
        card.appendChild(messageEl);

        var inputEl = null;
        if (type === 'prompt') {
          inputEl = document.createElement('input');
          inputEl.className = 'raincurtain-dialog-input';
          inputEl.type = 'text';
          inputEl.value = options.defaultValue || '';
          card.appendChild(inputEl);
        }

        var actions = document.createElement('div');
        actions.className = 'raincurtain-dialog-actions';

        var cancelBtn = null;
        if (type !== 'alert') {
          cancelBtn = document.createElement('button');
          cancelBtn.className = 'raincurtain-dialog-btn raincurtain-dialog-btn-text';
          cancelBtn.type = 'button';
          cancelBtn.textContent = '取消';
          actions.appendChild(cancelBtn);
        }

        var confirmBtn = document.createElement('button');
        confirmBtn.className = 'raincurtain-dialog-btn raincurtain-dialog-btn-filled';
        confirmBtn.type = 'button';
        confirmBtn.textContent = '确定';
        actions.appendChild(confirmBtn);

        card.appendChild(actions);
        root.appendChild(backdrop);
        root.appendChild(card);

        var settled = false;
        function finish(result) {
          if (settled) return;
          settled = true;
          self._close();
          item.resolve(result);
          self._active = null;
          self._dequeue();
        }

        function onConfirm() {
          if (type === 'alert') finish(undefined);
          else if (type === 'confirm') finish(true);
          else finish(inputEl ? inputEl.value : '');
        }

        function onCancel() {
          if (type === 'alert') finish(undefined);
          else if (type === 'confirm') finish(false);
          else finish(null);
        }

        confirmBtn.addEventListener('click', onConfirm);
        if (cancelBtn) cancelBtn.addEventListener('click', onCancel);

        backdrop.addEventListener('mousedown', function(e) {
          if (e.target === backdrop) onCancel();
        });

        card.addEventListener('mousedown', function(e) {
          e.stopPropagation();
        });

        self._keyHandler = function(e) {
          if (e.key === 'Escape') {
            e.preventDefault();
            e.stopPropagation();
            onCancel();
          } else if (e.key === 'Enter' && type !== 'alert') {
            if (type === 'prompt' && document.activeElement === inputEl) {
              e.preventDefault();
              onConfirm();
            } else if (type === 'confirm' && card.contains(document.activeElement)) {
              e.preventDefault();
              onConfirm();
            }
          }
        };
        document.addEventListener('keydown', self._keyHandler, true);

        var focusables = [];
        if (inputEl) focusables.push(inputEl);
        if (cancelBtn) focusables.push(cancelBtn);
        focusables.push(confirmBtn);

        card.addEventListener('keydown', function(e) {
          if (e.key !== 'Tab') return;
          var list = focusables.filter(function(el) { return el && !el.disabled; });
          if (list.length === 0) return;
          if (list.length === 1) {
            e.preventDefault();
            list[0].focus();
            return;
          }
          var idx = list.indexOf(document.activeElement);
          if (e.shiftKey) {
            if (idx <= 0) {
              e.preventDefault();
              list[list.length - 1].focus();
            }
          } else if (idx === -1 || idx >= list.length - 1) {
            e.preventDefault();
            list[0].focus();
          }
        });

        if (inputEl) inputEl.focus();
        else confirmBtn.focus();
      }

      if (document.body) {
        doRender();
      } else {
        var obs = new MutationObserver(function() {
          if (document.body) {
            obs.disconnect();
            doRender();
          }
        });
        obs.observe(document, { childList: true, subtree: true });
      }
    }
  };
})();
""";

  /// WebView 未可靠触发 onJs* 时，在 JS 层拦截 alert/confirm/prompt。
  /// 通过同步 XHR + [DialogSyncBridge] 在 Flutter 侧显示对话框并保持同步语义。
  static String nativeDialogOverrideJS(int port) {
    return '''
(function() {
  if (window.__raincurtainDialogOverridesInstalled) return;
  window.__raincurtainDialogOverridesInstalled = true;

  var base = 'http://localhost:$port/__raincurtain_dialog/sync/';

  function syncRequest(kind, message, defaultValue) {
    var url = base + kind + '?message=' + encodeURIComponent(String(message == null ? '' : message));
    if (kind === 'prompt') {
      url += '&defaultValue=' + encodeURIComponent(defaultValue == null ? '' : String(defaultValue));
    }
    var XHR = window.__raincurtainNativeXMLHttpRequest || XMLHttpRequest;
    var xhr = new XHR();
    xhr.open('GET', url, false);
    try {
      xhr.send(null);
    } catch (e) {
      console.error('[raincurtain] sync dialog request failed:', e);
      return kind === 'alert' ? undefined : (kind === 'confirm' ? false : null);
    }
    if (xhr.status !== 200) {
      return kind === 'alert' ? undefined : (kind === 'confirm' ? false : null);
    }
    try {
      var data = JSON.parse(xhr.responseText || '{}');
      if (kind === 'alert') return undefined;
      if (kind === 'confirm') return !!data.value;
      return data.value == null ? null : String(data.value);
    } catch (_) {
      return kind === 'alert' ? undefined : (kind === 'confirm' ? false : null);
    }
  }

  window.alert = function(message) {
    syncRequest('alert', message);
  };

  window.confirm = function(message) {
    return syncRequest('confirm', message);
  };

  window.prompt = function(message, defaultValue) {
    return syncRequest('prompt', message, defaultValue);
  };
})();
''';
  }

  void registerDialogBridge(BuildContext context) {
    DialogSyncBridge.instance.registerHost(
      showAlert: (message) => _showMaterialAlert(context, message),
      showConfirm: (message) => _showMaterialConfirm(context, message),
      showPrompt: (message, defaultValue) =>
          _showMaterialPrompt(context, message, defaultValue),
    );
  }

  void unregisterDialogBridge() {
    DialogSyncBridge.instance.unregisterHost();
  }

  Future<void> _showMaterialAlert(BuildContext context, String message) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showMaterialConfirm(BuildContext context, String message) async {
    if (!context.mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<String?> _showMaterialPrompt(
    BuildContext context,
    String message,
    String defaultValue,
  ) async {
    if (!context.mounted) return null;
    final controller = TextEditingController(text: defaultValue);
    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) => Navigator.pop(dialogContext, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, null),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<JsAlertResponse?> handleJsAlert(
    InAppWebViewController controller,
    JsAlertRequest request,
  ) async {
    try {
      final showAlert = DialogSyncBridge.instance.showAlert;
      if (showAlert != null) {
        await showAlert(request.message ?? '');
      }
      return JsAlertResponse(
        handledByClient: true,
        action: JsAlertResponseAction.CONFIRM,
      );
    } catch (e, stackTrace) {
      debugPrint('[DialogMixin] handleJsAlert failed: $e\n$stackTrace');
      return JsAlertResponse(
        handledByClient: true,
        action: JsAlertResponseAction.CONFIRM,
      );
    }
  }

  Future<JsConfirmResponse?> handleJsConfirm(
    InAppWebViewController controller,
    JsConfirmRequest request,
  ) async {
    try {
      final showConfirm = DialogSyncBridge.instance.showConfirm;
      final confirmed = showConfirm != null
          ? await showConfirm(request.message ?? '')
          : false;
      return JsConfirmResponse(
        handledByClient: true,
        action: confirmed
            ? JsConfirmResponseAction.CONFIRM
            : JsConfirmResponseAction.CANCEL,
      );
    } catch (e, stackTrace) {
      debugPrint('[DialogMixin] handleJsConfirm failed: $e\n$stackTrace');
      return JsConfirmResponse(
        handledByClient: true,
        action: JsConfirmResponseAction.CANCEL,
      );
    }
  }

  Future<JsPromptResponse?> handleJsPrompt(
    InAppWebViewController controller,
    JsPromptRequest request,
  ) async {
    try {
      final showPrompt = DialogSyncBridge.instance.showPrompt;
      final value = showPrompt != null
          ? await showPrompt(
              request.message ?? '',
              request.defaultValue ?? '',
            )
          : null;
      return JsPromptResponse(
        handledByClient: true,
        action: value != null
            ? JsPromptResponseAction.CONFIRM
            : JsPromptResponseAction.CANCEL,
        value: value,
      );
    } catch (e, stackTrace) {
      debugPrint('[DialogMixin] handleJsPrompt failed: $e\n$stackTrace');
      return JsPromptResponse(
        handledByClient: true,
        action: JsPromptResponseAction.CANCEL,
      );
    }
  }
}
